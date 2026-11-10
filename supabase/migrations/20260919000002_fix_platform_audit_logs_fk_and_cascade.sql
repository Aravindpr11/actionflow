-- ============================================================================
-- ActionFlow Platform Governance: Audit Log FK Fix & Tenant Deletion Integrity
-- Migration: 20260919000002_fix_platform_audit_logs_fk_and_cascade.sql
-- ============================================================================
-- 1. Modify foreign key constraint on public.platform_audit_logs:
--    Use ON DELETE SET NULL so deleting an organization preserves all historical
--    audit events and sets organization_id = NULL without constraint violations.
-- 2. Add immutable organization snapshot columns to public.platform_audit_logs:
--    organization_name VARCHAR(150), organization_code VARCHAR(50).
-- 3. Backfill existing audit rows from public.organizations and metadata.
-- 4. Update trg_audit_organization_changes() to:
--    - Skip delete trigger when delete_organization_cascade is running (actionflow.cascade_deleting = 'true')
--    - Set organization_id = NULL, organization_name = OLD.name, organization_code = OLD.code on delete
--    - Populate organization_name and organization_code on insert and update.
-- 5. Update delete_organization_cascade(p_organization_id UUID) to:
--    - Set actionflow.cascade_deleting = 'true'
--    - Insert audit record with organization_id = NULL, organization_name = v_org_name, organization_code = v_org_code
-- 6. Update record_platform_audit_event helper to accept organization snapshot fields.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Foreign Key Constraint: ON DELETE SET NULL
-- ----------------------------------------------------------------------------
ALTER TABLE public.platform_audit_logs
  DROP CONSTRAINT IF EXISTS platform_audit_logs_organization_id_fkey,
  ADD CONSTRAINT platform_audit_logs_organization_id_fkey
    FOREIGN KEY (organization_id)
    REFERENCES public.organizations(id)
    ON DELETE SET NULL;

-- ----------------------------------------------------------------------------
-- 2. Snapshot Columns: organization_name, organization_code
-- ----------------------------------------------------------------------------
ALTER TABLE public.platform_audit_logs
  ADD COLUMN IF NOT EXISTS organization_name VARCHAR(150),
  ADD COLUMN IF NOT EXISTS organization_code VARCHAR(50);

CREATE INDEX IF NOT EXISTS idx_platform_audit_logs_org_name
  ON public.platform_audit_logs (organization_name);

-- ----------------------------------------------------------------------------
-- 3. Backfill Existing Records
-- ----------------------------------------------------------------------------
UPDATE public.platform_audit_logs l
SET
  organization_name = COALESCE(l.organization_name, o.name, l.metadata->>'name', l.metadata->>'organization_name'),
  organization_code = COALESCE(l.organization_code, o.code, l.metadata->>'code', l.metadata->>'organization_code')
FROM public.organizations o
WHERE l.organization_id = o.id;

UPDATE public.platform_audit_logs
SET
  organization_name = COALESCE(organization_name, metadata->>'name', metadata->>'organization_name'),
  organization_code = COALESCE(organization_code, metadata->>'code', metadata->>'organization_code')
WHERE organization_name IS NULL
  AND (metadata->>'name' IS NOT NULL OR metadata->>'organization_name' IS NOT NULL);

-- ----------------------------------------------------------------------------
-- 4. Audit Logging Trigger for public.organizations
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_audit_organization_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor_email VARCHAR(255);
  v_actor_id UUID;
  v_event_type VARCHAR(100);
  v_description TEXT;
  v_category VARCHAR(50) := 'tenancy';
  v_severity VARCHAR(20) := 'info';
  v_metadata JSONB;
BEGIN
  v_actor_id := auth.uid();
  IF v_actor_id IS NOT NULL THEN
    SELECT email INTO v_actor_email FROM auth.users WHERE id = v_actor_id;
  END IF;

  IF (TG_OP = 'INSERT') THEN
    v_event_type := 'organization_created';
    v_description := 'Organization "' || NEW.name || '" created (code: ' || NEW.code || ')';
    v_metadata := jsonb_build_object(
      'organization_id', NEW.id,
      'name', NEW.name,
      'code', NEW.code,
      'is_active', NEW.is_active
    );

    INSERT INTO public.platform_audit_logs (
      event_type, category, severity, actor_id, actor_email,
      organization_id, organization_name, organization_code,
      target_type, target_id, description, metadata
    ) VALUES (
      v_event_type, v_category, v_severity, v_actor_id, v_actor_email,
      NEW.id, NEW.name, NEW.code,
      'organization', NEW.id::text, v_description, v_metadata
    );

    RETURN NEW;
  ELSIF (TG_OP = 'UPDATE') THEN
    v_event_type := 'organization_updated';
    v_description := 'Organization "' || NEW.name || '" updated';
    v_metadata := jsonb_build_object(
      'organization_id', NEW.id,
      'old_name', OLD.name,
      'new_name', NEW.name,
      'old_code', OLD.code,
      'new_code', NEW.code,
      'old_is_active', OLD.is_active,
      'new_is_active', NEW.is_active
    );

    INSERT INTO public.platform_audit_logs (
      event_type, category, severity, actor_id, actor_email,
      organization_id, organization_name, organization_code,
      target_type, target_id, description, metadata
    ) VALUES (
      v_event_type, v_category, v_severity, v_actor_id, v_actor_email,
      NEW.id, NEW.name, NEW.code,
      'organization', NEW.id::text, v_description, v_metadata
    );

    RETURN NEW;
  ELSIF (TG_OP = 'DELETE') THEN
    -- If running inside delete_organization_cascade, skip trigger to avoid duplicate log
    IF current_setting('actionflow.cascade_deleting', true) = 'true' THEN
      RETURN OLD;
    END IF;

    v_event_type := 'organization_deleted';
    v_severity := 'warning';
    v_description := 'Organization "' || OLD.name || '" (' || OLD.code || ') deleted';
    v_metadata := jsonb_build_object(
      'organization_id', OLD.id,
      'name', OLD.name,
      'code', OLD.code,
      'is_deleted', true
    );

    -- Notice: organization_id is NULL because the organization was permanently deleted
    INSERT INTO public.platform_audit_logs (
      event_type, category, severity, actor_id, actor_email,
      organization_id, organization_name, organization_code,
      target_type, target_id, description, metadata
    ) VALUES (
      v_event_type, v_category, v_severity, v_actor_id, v_actor_email,
      NULL, OLD.name, OLD.code,
      'organization', OLD.id::text, v_description, v_metadata
    );

    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;

-- Re-attach trigger
DROP TRIGGER IF EXISTS trg_audit_organizations ON public.organizations;
CREATE TRIGGER trg_audit_organizations
  AFTER INSERT OR UPDATE OR DELETE ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_audit_organization_changes();

-- ----------------------------------------------------------------------------
-- 5. Atomic delete_organization_cascade with NULL organization_id in audit log
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_organization_cascade(p_organization_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org_name VARCHAR(150);
  v_org_code VARCHAR(50);
  v_deleted_profiles_count INT := 0;
  v_deleted_depts_count INT := 0;
  v_deleted_sites_count INT := 0;
  v_deleted_teams_count INT := 0;
  v_actor_email VARCHAR(255);
BEGIN
  -- 1. Caller Authorization: Must be a verified Platform Administrator
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Only Platform Administrators may delete organizations.';
  END IF;

  -- 2. Anchor Organization Protection: Sobha (#1) is permanent
  IF p_organization_id = '00000000-0000-0000-0000-000000000001'::UUID THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Default organization Sobha (#1) is permanent and cannot be deleted.';
  END IF;

  SELECT name, code INTO v_org_name, v_org_code
  FROM public.organizations
  WHERE id = p_organization_id;

  IF v_org_name IS NULL THEN
    RAISE EXCEPTION 'Organization not found: %', p_organization_id;
  END IF;

  IF lower(v_org_code) = 'sobha' THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Default organization Sobha is permanent and cannot be deleted.';
  END IF;

  -- Suppress duplicate deletion log in trg_audit_organization_changes
  PERFORM set_config('actionflow.cascade_deleting', 'true', true);

  -- 3. Delete dependencies in exact reverse foreign key order:
  DELETE FROM public.account_request_scopes
  WHERE account_request_id IN (
    SELECT id FROM public.account_requests WHERE organization_id = p_organization_id
  );

  DELETE FROM public.account_requests
  WHERE organization_id = p_organization_id;

  DELETE FROM public.manager_scopes
  WHERE manager_profile_id IN (
    SELECT id FROM public.profiles WHERE organization_id = p_organization_id
  );

  DELETE FROM public.team_members
  WHERE team_id IN (
    SELECT id FROM public.teams WHERE organization_id = p_organization_id
  ) OR profile_id IN (
    SELECT id FROM public.profiles WHERE organization_id = p_organization_id
  );

  DELETE FROM public.teams
  WHERE organization_id = p_organization_id;
  GET DIAGNOSTICS v_deleted_teams_count = ROW_COUNT;

  DELETE FROM public.departments
  WHERE organization_id = p_organization_id;
  GET DIAGNOSTICS v_deleted_depts_count = ROW_COUNT;

  DELETE FROM public.sites
  WHERE organization_id = p_organization_id;
  GET DIAGNOSTICS v_deleted_sites_count = ROW_COUNT;

  DELETE FROM public.profiles
  WHERE organization_id = p_organization_id
    AND id NOT IN (SELECT user_id FROM public.platform_admins);
  GET DIAGNOSTICS v_deleted_profiles_count = ROW_COUNT;

  DELETE FROM public.organizations
  WHERE id = p_organization_id;

  -- Record audit log inside the transaction
  SELECT email INTO v_actor_email FROM auth.users WHERE id = auth.uid();

  -- Notice: organization_id is NULL because the organization was permanently deleted,
  -- and snapshot fields organization_name & organization_code preserve historical context.
  INSERT INTO public.platform_audit_logs (
    event_type, category, severity, actor_id, actor_email,
    organization_id, organization_name, organization_code,
    target_type, target_id, description, metadata
  ) VALUES (
    'organization_deleted',
    'tenancy',
    'warning',
    auth.uid(),
    v_actor_email,
    NULL,
    v_org_name,
    v_org_code,
    'organization',
    p_organization_id::text,
    'Organization "' || v_org_name || '" (' || v_org_code || ') deleted with ' || v_deleted_profiles_count || ' profiles and child records',
    jsonb_build_object(
      'organization_id', p_organization_id,
      'organization_name', v_org_name,
      'organization_code', v_org_code,
      'deleted_profiles_count', v_deleted_profiles_count,
      'deleted_departments_count', v_deleted_depts_count,
      'deleted_sites_count', v_deleted_sites_count,
      'deleted_teams_count', v_deleted_teams_count,
      'is_deleted', true
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'organization_id', p_organization_id,
    'organization_name', v_org_name,
    'organization_code', v_org_code,
    'deleted_profiles_count', v_deleted_profiles_count,
    'deleted_departments_count', v_deleted_depts_count,
    'deleted_sites_count', v_deleted_sites_count,
    'deleted_teams_count', v_deleted_teams_count
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. Update record_platform_audit_event RPC
-- ----------------------------------------------------------------------------
-- Drop old 8-parameter overload to prevent ambiguity
DROP FUNCTION IF EXISTS public.record_platform_audit_event(
  VARCHAR, VARCHAR, VARCHAR, TEXT, UUID, VARCHAR, VARCHAR, JSONB
);

CREATE OR REPLACE FUNCTION public.record_platform_audit_event(
  p_event_type VARCHAR(100),
  p_category VARCHAR(50),
  p_severity VARCHAR(20),
  p_description TEXT,
  p_organization_id UUID DEFAULT NULL,
  p_target_type VARCHAR(50) DEFAULT NULL,
  p_target_id VARCHAR(255) DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb,
  p_organization_name VARCHAR(150) DEFAULT NULL,
  p_organization_code VARCHAR(50) DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_new_id UUID;
  v_actor_email VARCHAR(255);
  v_org_name VARCHAR(150);
  v_org_code VARCHAR(50);
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Only Platform Administrators may record platform audit events.';
  END IF;

  SELECT email INTO v_actor_email
  FROM auth.users
  WHERE id = auth.uid();

  v_org_name := p_organization_name;
  v_org_code := p_organization_code;

  IF p_organization_id IS NOT NULL AND v_org_name IS NULL THEN
    SELECT name, code INTO v_org_name, v_org_code
    FROM public.organizations
    WHERE id = p_organization_id;
  END IF;

  INSERT INTO public.platform_audit_logs (
    event_type,
    category,
    severity,
    actor_id,
    actor_email,
    organization_id,
    organization_name,
    organization_code,
    target_type,
    target_id,
    description,
    metadata
  ) VALUES (
    p_event_type,
    COALESCE(p_category, 'governance'),
    COALESCE(p_severity, 'info'),
    auth.uid(),
    v_actor_email,
    p_organization_id,
    v_org_name,
    v_org_code,
    p_target_type,
    p_target_id,
    p_description,
    COALESCE(p_metadata, '{}'::jsonb)
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_platform_audit_event(VARCHAR, VARCHAR, VARCHAR, TEXT, UUID, VARCHAR, VARCHAR, JSONB, VARCHAR, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_platform_audit_event(VARCHAR, VARCHAR, VARCHAR, TEXT, UUID, VARCHAR, VARCHAR, JSONB, VARCHAR, VARCHAR) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.delete_organization_cascade(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_organization_cascade(UUID) TO authenticated, service_role;
