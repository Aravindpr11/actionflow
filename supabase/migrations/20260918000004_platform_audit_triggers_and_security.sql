-- ============================================================================
-- ActionFlow Platform Governance: Audit Triggers & Authority RLS Hardening
-- Migration: 20260918000004_platform_audit_triggers_and_security.sql
-- ============================================================================
-- 1. Fix self-referencing RLS recursion on public.platform_admins:
--    Use public.is_platform_admin() security definer function instead of
--    direct subqueries on platform_admins to avoid Postgres RLS recursion.
-- 2. Add audit triggers on public.organizations and public.platform_settings
--    to guarantee real persistence in public.platform_audit_logs.
-- 3. Update public.delete_organization_cascade to log directly to platform_audit_logs.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Hardened RLS Policies on public.platform_admins
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Platform admin read platform admins" ON public.platform_admins;
CREATE POLICY "Platform admin read platform admins"
  ON public.platform_admins FOR SELECT
  TO authenticated
  USING (public.is_platform_admin());

DROP POLICY IF EXISTS "Platform admin manage platform admins" ON public.platform_admins;
CREATE POLICY "Platform admin manage platform admins"
  ON public.platform_admins FOR ALL
  TO authenticated
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

-- ----------------------------------------------------------------------------
-- 2. Audit Logging Trigger for public.organizations
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
      organization_id, target_type, target_id, description, metadata
    ) VALUES (
      v_event_type, v_category, v_severity, v_actor_id, v_actor_email,
      NEW.id, 'organization', NEW.id::text, v_description, v_metadata
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
      organization_id, target_type, target_id, description, metadata
    ) VALUES (
      v_event_type, v_category, v_severity, v_actor_id, v_actor_email,
      NEW.id, 'organization', NEW.id::text, v_description, v_metadata
    );

    RETURN NEW;
  ELSIF (TG_OP = 'DELETE') THEN
    v_event_type := 'organization_deleted';
    v_severity := 'warning';
    v_description := 'Organization "' || OLD.name || '" (' || OLD.code || ') deleted';
    v_metadata := jsonb_build_object(
      'organization_id', OLD.id,
      'name', OLD.name,
      'code', OLD.code
    );

    INSERT INTO public.platform_audit_logs (
      event_type, category, severity, actor_id, actor_email,
      organization_id, target_type, target_id, description, metadata
    ) VALUES (
      v_event_type, v_category, v_severity, v_actor_id, v_actor_email,
      OLD.id, 'organization', OLD.id::text, v_description, v_metadata
    );

    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_organizations ON public.organizations;
CREATE TRIGGER trg_audit_organizations
  AFTER INSERT OR UPDATE OR DELETE ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_audit_organization_changes();

-- ----------------------------------------------------------------------------
-- 3. Audit Logging Trigger for public.platform_settings
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_audit_platform_setting_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor_email VARCHAR(255);
  v_actor_id UUID;
  v_description TEXT;
  v_metadata JSONB;
BEGIN
  v_actor_id := auth.uid();
  IF v_actor_id IS NOT NULL THEN
    SELECT email INTO v_actor_email FROM auth.users WHERE id = v_actor_id;
  END IF;

  v_description := 'Platform setting "' || NEW.key || '" updated';
  v_metadata := jsonb_build_object(
    'key', NEW.key,
    'category', NEW.category,
    'value', NEW.value,
    'previous_value', CASE WHEN TG_OP = 'UPDATE' THEN OLD.value ELSE NULL END
  );

  INSERT INTO public.platform_audit_logs (
    event_type, category, severity, actor_id, actor_email,
    organization_id, target_type, target_id, description, metadata
  ) VALUES (
    'setting_updated', 'configuration', 'info', v_actor_id, v_actor_email,
    NULL, 'setting', NEW.key, v_description, v_metadata
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_platform_settings ON public.platform_settings;
CREATE TRIGGER trg_audit_platform_settings
  AFTER INSERT OR UPDATE ON public.platform_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_audit_platform_setting_changes();

-- ----------------------------------------------------------------------------
-- 4. Update delete_organization_cascade to log inside the transaction
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

  INSERT INTO public.platform_audit_logs (
    event_type, category, severity, actor_id, actor_email,
    organization_id, target_type, target_id, description, metadata
  ) VALUES (
    'organization_deleted',
    'tenancy',
    'warning',
    auth.uid(),
    v_actor_email,
    NULL,
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
      'deleted_teams_count', v_deleted_teams_count
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

