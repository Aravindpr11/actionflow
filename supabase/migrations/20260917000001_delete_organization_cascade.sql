-- ============================================================================
-- ActionFlow Multi-Company: Transactional Organization Deletion
-- Migration: 20260917000001_delete_organization_cascade.sql
-- ============================================================================
-- Allows Platform Administrators to atomically delete a non-anchor tenant
-- organization and all its relational records in strict reverse foreign key order.
-- Prevents accidental deletion of Sobha (Organization #1) and Platform Admins.
-- ============================================================================

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
  -- A. account_request_scopes (child of account_requests)
  DELETE FROM public.account_request_scopes
  WHERE account_request_id IN (
    SELECT id FROM public.account_requests WHERE organization_id = p_organization_id
  );

  -- B. account_requests (child of organizations, departments, sites, teams)
  DELETE FROM public.account_requests
  WHERE organization_id = p_organization_id;

  -- C. manager_scopes (child of profiles, departments, sites)
  DELETE FROM public.manager_scopes
  WHERE manager_profile_id IN (
    SELECT id FROM public.profiles WHERE organization_id = p_organization_id
  );

  -- D. team_members (child of teams and profiles)
  DELETE FROM public.team_members
  WHERE team_id IN (
    SELECT id FROM public.teams WHERE organization_id = p_organization_id
  ) OR profile_id IN (
    SELECT id FROM public.profiles WHERE organization_id = p_organization_id
  );

  -- E. teams (child of departments and organizations)
  DELETE FROM public.teams
  WHERE organization_id = p_organization_id;
  GET DIAGNOSTICS v_deleted_teams_count = ROW_COUNT;

  -- F. departments & sites (child of organizations)
  DELETE FROM public.departments
  WHERE organization_id = p_organization_id;
  GET DIAGNOSTICS v_deleted_depts_count = ROW_COUNT;

  DELETE FROM public.sites
  WHERE organization_id = p_organization_id;
  GET DIAGNOSTICS v_deleted_sites_count = ROW_COUNT;

  -- G. profiles (tenant users: Company Admins, Managers, Staff)
  -- CRITICAL SECURITY INVARIANT: NEVER delete any Platform Admin profile
  DELETE FROM public.profiles
  WHERE organization_id = p_organization_id
    AND id NOT IN (SELECT user_id FROM public.platform_admins);
  GET DIAGNOSTICS v_deleted_profiles_count = ROW_COUNT;

  -- H. organizations (the tenant company entity)
  DELETE FROM public.organizations
  WHERE id = p_organization_id;

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

COMMENT ON FUNCTION public.delete_organization_cascade(UUID) IS
  'Atomically deletes a non-anchor tenant organization and all child records. Restricted strictly to Platform Admins. Protects Sobha and Platform Admins.';

REVOKE EXECUTE ON FUNCTION public.delete_organization_cascade(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_organization_cascade(UUID) TO authenticated, service_role;

