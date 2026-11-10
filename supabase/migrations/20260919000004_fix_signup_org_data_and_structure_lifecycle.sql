-- ============================================================================
-- ActionFlow Fix Signup Organization Data & Department/Site Structure Lifecycle
-- Migration: 20260919000004_fix_signup_org_data_and_structure_lifecycle.sql
-- ============================================================================
-- 1. Split RLS Policies for Anon vs Authenticated:
--    Fixes PostgreSQL error 42501 ("permission denied for function get_my_organization_id")
--    by ensuring anonymous queries evaluate clean policies without referencing
--    functions restricted to authenticated users.
--    Allows unauthenticated Manager & Staff signups to read active departments,
--    sites, and teams belonging strictly to active tenant organizations.
-- 2. Atomic Safe Department Deletion RPC (delete_department):
--    Verifies caller is authorized Company Admin or Platform Admin.
--    Checks all relational dependencies (profiles, teams, account_requests,
--    manager_scopes, account_request_scopes).
--    Blocks deletion if dependencies exist and returns structured error with
--    exact dependency counts and instructions to deactivate instead.
--    Allows permanent deletion if and only if truly unused (0 dependencies).
-- 3. Atomic Safe Site Deletion RPC (delete_site):
--    Verifies caller is authorized Company Admin or Platform Admin.
--    Checks all relational dependencies (profiles, account_requests,
--    manager_scopes, account_request_scopes).
--    Blocks deletion if dependencies exist and returns structured error.
--    Allows permanent deletion if truly unused.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Split RLS Policies for Departments, Sites, and Teams
-- ----------------------------------------------------------------------------

-- A. departments
DROP POLICY IF EXISTS "Read active departments" ON public.departments;
DROP POLICY IF EXISTS "Anon read active departments" ON public.departments;
DROP POLICY IF EXISTS "Authenticated read active departments" ON public.departments;

CREATE POLICY "Anon read active departments"
  ON public.departments FOR SELECT
  TO anon
  USING (
    is_active = true
    AND organization_id IN (SELECT id FROM public.organizations WHERE is_active = true)
  );

CREATE POLICY "Authenticated read active departments"
  ON public.departments FOR SELECT
  TO authenticated
  USING (
    is_active = true
    AND (
      public.is_platform_admin()
      OR organization_id = public.get_my_organization_id()
    )
  );

-- B. sites
DROP POLICY IF EXISTS "Read active sites" ON public.sites;
DROP POLICY IF EXISTS "Anon read active sites" ON public.sites;
DROP POLICY IF EXISTS "Authenticated read active sites" ON public.sites;

CREATE POLICY "Anon read active sites"
  ON public.sites FOR SELECT
  TO anon
  USING (
    is_active = true
    AND organization_id IN (SELECT id FROM public.organizations WHERE is_active = true)
  );

CREATE POLICY "Authenticated read active sites"
  ON public.sites FOR SELECT
  TO authenticated
  USING (
    is_active = true
    AND (
      public.is_platform_admin()
      OR organization_id = public.get_my_organization_id()
    )
  );

-- C. teams
DROP POLICY IF EXISTS "Read active teams" ON public.teams;
DROP POLICY IF EXISTS "Anon read active teams" ON public.teams;
DROP POLICY IF EXISTS "Authenticated read active teams" ON public.teams;

CREATE POLICY "Anon read active teams"
  ON public.teams FOR SELECT
  TO anon
  USING (
    is_active = true
    AND organization_id IN (SELECT id FROM public.organizations WHERE is_active = true)
  );

CREATE POLICY "Authenticated read active teams"
  ON public.teams FOR SELECT
  TO authenticated
  USING (
    is_active = true
    AND (
      public.is_platform_admin()
      OR organization_id = public.get_my_organization_id()
    )
  );

-- ----------------------------------------------------------------------------
-- 2. Atomic Safe Department Deletion RPC
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_department(p_department_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_org_id UUID;
  v_is_platform BOOLEAN := false;
  v_is_company_admin BOOLEAN := false;
  v_target_dept RECORD;
  v_user_count INT := 0;
  v_team_count INT := 0;
  v_req_count INT := 0;
  v_mgr_scope_count INT := 0;
  v_req_scope_count INT := 0;
  v_total_deps INT := 0;
  v_dep_msg TEXT;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Authentication required.';
  END IF;

  v_is_platform := public.is_platform_admin();
  v_is_company_admin := public.is_admin();

  IF NOT v_is_platform AND NOT v_is_company_admin THEN
    RAISE EXCEPTION 'Unauthorized: Only Company Administrators or Platform Admins can delete departments.';
  END IF;

  SELECT * INTO v_target_dept FROM public.departments WHERE id = p_department_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Department not found: %', p_department_id;
  END IF;

  IF NOT v_is_platform THEN
    v_caller_org_id := public.get_my_organization_id();
    IF v_caller_org_id IS NULL OR v_target_dept.organization_id != v_caller_org_id THEN
      RAISE EXCEPTION 'Unauthorized: You can only delete departments within your own organization.';
    END IF;
  END IF;

  -- Count dependencies
  SELECT count(*) INTO v_user_count FROM public.profiles WHERE department_id = p_department_id;
  SELECT count(*) INTO v_team_count FROM public.teams WHERE department_id = p_department_id;
  SELECT count(*) INTO v_req_count FROM public.account_requests WHERE department_id = p_department_id;
  SELECT count(*) INTO v_mgr_scope_count FROM public.manager_scopes WHERE department_id = p_department_id;
  SELECT count(*) INTO v_req_scope_count FROM public.account_request_scopes WHERE department_id = p_department_id;

  v_total_deps := v_user_count + v_team_count + v_req_count + v_mgr_scope_count + v_req_scope_count;

  IF v_total_deps > 0 THEN
    v_dep_msg := format(
      'Cannot delete department "%s": %s assigned user(s), %s team(s), %s pending request(s), and %s manager scope(s) are linked to it. Please deactivate this department or reassign dependencies first.',
      v_target_dept.name,
      v_user_count,
      v_team_count,
      v_req_count,
      (v_mgr_scope_count + v_req_scope_count)
    );

    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'DEPENDENCIES_EXIST',
      'message', v_dep_msg,
      'department_id', p_department_id,
      'department_name', v_target_dept.name,
      'dependencies', jsonb_build_object(
        'users', v_user_count,
        'teams', v_team_count,
        'account_requests', v_req_count,
        'manager_scopes', (v_mgr_scope_count + v_req_scope_count)
      )
    );
  END IF;

  DELETE FROM public.departments WHERE id = p_department_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', format('Department "%s" deleted successfully.', v_target_dept.name),
    'department_id', p_department_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_department TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_department TO service_role;

-- ----------------------------------------------------------------------------
-- 3. Atomic Safe Site Deletion RPC
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_site(p_site_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_org_id UUID;
  v_is_platform BOOLEAN := false;
  v_is_company_admin BOOLEAN := false;
  v_target_site RECORD;
  v_user_count INT := 0;
  v_req_count INT := 0;
  v_mgr_scope_count INT := 0;
  v_req_scope_count INT := 0;
  v_total_deps INT := 0;
  v_dep_msg TEXT;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Authentication required.';
  END IF;

  v_is_platform := public.is_platform_admin();
  v_is_company_admin := public.is_admin();

  IF NOT v_is_platform AND NOT v_is_company_admin THEN
    RAISE EXCEPTION 'Unauthorized: Only Company Administrators or Platform Admins can delete sites.';
  END IF;

  SELECT * INTO v_target_site FROM public.sites WHERE id = p_site_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Site not found: %', p_site_id;
  END IF;

  IF NOT v_is_platform THEN
    v_caller_org_id := public.get_my_organization_id();
    IF v_caller_org_id IS NULL OR v_target_site.organization_id != v_caller_org_id THEN
      RAISE EXCEPTION 'Unauthorized: You can only delete sites within your own organization.';
    END IF;
  END IF;

  -- Count dependencies
  SELECT count(*) INTO v_user_count FROM public.profiles WHERE site_id = p_site_id;
  SELECT count(*) INTO v_req_count FROM public.account_requests WHERE site_id = p_site_id;
  SELECT count(*) INTO v_mgr_scope_count FROM public.manager_scopes WHERE site_id = p_site_id;
  SELECT count(*) INTO v_req_scope_count FROM public.account_request_scopes WHERE site_id = p_site_id;

  v_total_deps := v_user_count + v_req_count + v_mgr_scope_count + v_req_scope_count;

  IF v_total_deps > 0 THEN
    v_dep_msg := format(
      'Cannot delete site "%s": %s assigned user(s), %s pending request(s), and %s manager scope(s) are linked to it. Please deactivate this site or reassign dependencies first.',
      v_target_site.name,
      v_user_count,
      v_req_count,
      (v_mgr_scope_count + v_req_scope_count)
    );

    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'DEPENDENCIES_EXIST',
      'message', v_dep_msg,
      'site_id', p_site_id,
      'site_name', v_target_site.name,
      'dependencies', jsonb_build_object(
        'users', v_user_count,
        'account_requests', v_req_count,
        'manager_scopes', (v_mgr_scope_count + v_req_scope_count)
      )
    );
  END IF;

  DELETE FROM public.sites WHERE id = p_site_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', format('Site "%s" deleted successfully.', v_target_site.name),
    'site_id', p_site_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_site TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_site TO service_role;

