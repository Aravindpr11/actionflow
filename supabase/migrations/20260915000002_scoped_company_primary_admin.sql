-- ============================================================================
-- Migration: 20260915000002_scoped_company_primary_admin.sql
-- Description: Scope Company Primary Admin uniqueness per organization and
--              update handle_admin_role_sync() trigger for multi-tenancy.
-- Safe to apply: Yes (Non-destructive, does not modify Sobha Admin, validates existing rows)
-- ============================================================================

-- 1. Drop the legacy global unique index enforcing single active admin across the entire database
DROP INDEX IF EXISTS public.uq_profiles_single_active_admin;

-- 2. Create organization-scoped unique index
-- Enforces that within any single organization, there can be AT MOST ONE active primary admin.
-- Platform Admins (organization_id IS NULL) are explicitly excluded from this index.
-- Multiple secondary company admins (is_primary_admin = false) within the same organization are fully supported.
CREATE UNIQUE INDEX uq_profiles_single_active_primary_admin_per_org
  ON public.profiles (organization_id)
  WHERE is_primary_admin = true AND is_active = true AND organization_id IS NOT NULL;

COMMENT ON INDEX public.uq_profiles_single_active_primary_admin_per_org IS
  'Ensures at most one active primary Company Admin per organization. Excludes Platform Admins (organization_id IS NULL).';

-- 3. Update handle_admin_role_sync trigger function
-- - Scopes primary admin uniqueness validation strictly to NEW.organization_id.
-- - Designates first admin of an organization as primary admin if none exists.
-- - Permits secondary company admins with is_primary_admin = false.
-- - Prevents duplicate primary admins within the same organization.
-- - Ensures non-admins and platform admins (organization_id IS NULL) have is_primary_admin = false.
CREATE OR REPLACE FUNCTION public.handle_admin_role_sync()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_admin_role_id UUID;
  v_active_admin_count INT;
BEGIN
  -- Look up Admin role ID dynamically (no hardcoded UUIDs)
  SELECT id INTO v_admin_role_id FROM public.roles WHERE code = 'admin';

  IF NEW.role_id = v_admin_role_id THEN
    -- If profile belongs to an organization (Company Admin)
    IF NEW.organization_id IS NOT NULL THEN
      -- Count existing active primary admins for THIS organization (excluding this user)
      SELECT COUNT(*) INTO v_active_admin_count
      FROM public.profiles
      WHERE organization_id = NEW.organization_id
        AND is_primary_admin = true
        AND is_active = true
        AND id != NEW.id;

      -- If no active primary admin exists for this organization, and caller did not explicitly
      -- pass false, automatically designate this user as the primary Company Admin
      IF v_active_admin_count = 0 AND NEW.is_primary_admin IS NOT FALSE THEN
        NEW.is_primary_admin := true;
      END IF;

      -- If this user is marked as active primary admin, enforce single primary admin rule for this org
      IF NEW.is_primary_admin = true AND NEW.is_active = true THEN
        IF v_active_admin_count >= 1 THEN
          RAISE EXCEPTION 'ActionFlow Governance Policy: Exactly one active primary Company Admin is permitted per organization.';
        END IF;
      END IF;
    ELSE
      -- Profiles with organization_id NULL (Platform Admins) cannot be company primary admins
      NEW.is_primary_admin := false;
    END IF;
  ELSE
    -- Non-Admin roles (manager, staff) cannot have is_primary_admin = true
    NEW.is_primary_admin := false;
  END IF;

  RETURN NEW;
END;
$$;

-- 4. Update documentation comment on is_primary_admin column
COMMENT ON COLUMN public.profiles.is_primary_admin IS
  'System-maintained flag ensuring at most one active primary Company Admin per organization via uq_profiles_single_active_primary_admin_per_org index.';

