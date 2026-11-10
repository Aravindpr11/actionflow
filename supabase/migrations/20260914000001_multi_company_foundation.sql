-- ============================================================================
-- ActionFlow Multi-Company Foundation: Organizations & Tenant Scoping
-- Migration: 20260914000001_multi_company_foundation.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Table: organizations
-- Central tenant entity representing companies in the multi-company architecture.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(150) NOT NULL,
  code VARCHAR(50) UNIQUE NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_organizations_name UNIQUE (name),
  CONSTRAINT chk_organization_code_format CHECK (code ~ '^[a-z0-9_-]+$')
);

COMMENT ON TABLE public.organizations IS 'Tenant organizations (companies) in the multi-company architecture.';
COMMENT ON COLUMN public.organizations.id IS 'Primary unique identifier for the organization.';
COMMENT ON COLUMN public.organizations.name IS 'Display name of the organization/company (e.g. Sobha).';
COMMENT ON COLUMN public.organizations.code IS 'Unique URL-safe / short slug identifier for the organization (e.g. sobha).';
COMMENT ON COLUMN public.organizations.is_active IS 'Active status flag indicating if the organization is operational.';

CREATE INDEX IF NOT EXISTS idx_organizations_code ON public.organizations (code);
CREATE INDEX IF NOT EXISTS idx_organizations_is_active ON public.organizations (is_active);

-- Updated_at trigger for organizations
DROP TRIGGER IF EXISTS trg_organizations_updated_at ON public.organizations;
CREATE TRIGGER trg_organizations_updated_at
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_updated_at();

-- ----------------------------------------------------------------------------
-- 2. Seed Sobha as Organization #1
-- Uses fixed deterministic UUID for consistent reference across environments and tests.
-- ----------------------------------------------------------------------------
INSERT INTO public.organizations (id, name, code, is_active)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'Sobha',
  'sobha',
  true
)
ON CONFLICT (code) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 3. Add organization_id to Company-Owned Tables
-- Adds foreign key referencing public.organizations(id) with default to Sobha.
-- ----------------------------------------------------------------------------

-- A. departments
ALTER TABLE public.departments
  ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE RESTRICT;

-- B. sites
ALTER TABLE public.sites
  ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE RESTRICT;

-- C. teams
ALTER TABLE public.teams
  ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE RESTRICT;

-- D. profiles (users belong to an organization; includes current Admin)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE RESTRICT;

-- E. account_requests (signup requests belong to an organization)
ALTER TABLE public.account_requests
  ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE RESTRICT;

-- ----------------------------------------------------------------------------
-- 4. Associate Existing Sobha Environment Data
-- Backfills existing rows with Sobha organization ID.
-- ----------------------------------------------------------------------------
UPDATE public.departments
SET organization_id = '00000000-0000-0000-0000-000000000001'
WHERE organization_id IS NULL;

UPDATE public.sites
SET organization_id = '00000000-0000-0000-0000-000000000001'
WHERE organization_id IS NULL;

UPDATE public.teams
SET organization_id = '00000000-0000-0000-0000-000000000001'
WHERE organization_id IS NULL;

UPDATE public.profiles
SET organization_id = '00000000-0000-0000-0000-000000000001'
WHERE organization_id IS NULL;

UPDATE public.account_requests
SET organization_id = '00000000-0000-0000-0000-000000000001'
WHERE organization_id IS NULL;

-- Set default to Sobha organization for seamless backward compatibility
-- during the transition before client signup screens send organization_id explicitly
ALTER TABLE public.departments
  ALTER COLUMN organization_id SET DEFAULT '00000000-0000-0000-0000-000000000001',
  ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.sites
  ALTER COLUMN organization_id SET DEFAULT '00000000-0000-0000-0000-000000000001',
  ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.teams
  ALTER COLUMN organization_id SET DEFAULT '00000000-0000-0000-0000-000000000001',
  ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.profiles
  ALTER COLUMN organization_id SET DEFAULT '00000000-0000-0000-0000-000000000001',
  ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.account_requests
  ALTER COLUMN organization_id SET DEFAULT '00000000-0000-0000-0000-000000000001',
  ALTER COLUMN organization_id SET NOT NULL;

-- ----------------------------------------------------------------------------
-- 5. Safe Indexes on Foreign Keys
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_departments_organization ON public.departments (organization_id);
CREATE INDEX IF NOT EXISTS idx_sites_organization ON public.sites (organization_id);
CREATE INDEX IF NOT EXISTS idx_teams_organization ON public.teams (organization_id);
CREATE INDEX IF NOT EXISTS idx_profiles_organization ON public.profiles (organization_id);
CREATE INDEX IF NOT EXISTS idx_account_requests_organization ON public.account_requests (organization_id);

-- ----------------------------------------------------------------------------
-- 6. Helper Function: get_my_organization_id()
-- Resolves the current authenticated user's organization_id in a safe,
-- security-definer, non-recursive manner for future RLS policies.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_organization_id()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org_id UUID;
BEGIN
  SELECT organization_id INTO v_org_id
  FROM public.profiles
  WHERE id = auth.uid();
  RETURN v_org_id;
END;
$$;

COMMENT ON FUNCTION public.get_my_organization_id() IS 'Returns the organization_id of the currently authenticated user from public.profiles.';

REVOKE EXECUTE ON FUNCTION public.get_my_organization_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_organization_id() TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 7. Row Level Security (RLS) on public.organizations
-- Allows authenticated and anonymous users to view active organizations.
-- Full management is restricted to Admin.
-- ----------------------------------------------------------------------------
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.organizations TO authenticated, anon;

DROP POLICY IF EXISTS "Allow read active organizations" ON public.organizations;
CREATE POLICY "Allow read active organizations"
  ON public.organizations FOR SELECT
  TO anon, authenticated
  USING (is_active = true);

DROP POLICY IF EXISTS "Admin read all organizations" ON public.organizations;
CREATE POLICY "Admin read all organizations"
  ON public.organizations FOR SELECT
  TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "Admin manage organizations" ON public.organizations;
CREATE POLICY "Admin manage organizations"
  ON public.organizations FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());


