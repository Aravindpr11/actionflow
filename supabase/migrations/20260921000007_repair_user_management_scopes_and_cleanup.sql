-- ============================================================================
-- Migration: 20260921000007_repair_user_management_scopes_and_cleanup.sql
-- Description:
--   1. Create public.sync_manager_scopes(p_manager_id UUID, p_scopes JSONB)
--      for atomic multi-scope management by Company Admin.
--   2. Create public.get_system_users_audit() to safely inspect and audit
--      accounts before demo user cleanup.
--   3. Ensure RLS policies and multi-tenant security are strictly preserved.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Atomic Manager Scopes Synchronization Function
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_manager_scopes(
  p_manager_id UUID,
  p_scopes JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_org_id UUID;
  v_is_plat_admin BOOLEAN;
  v_manager_org_id UUID;
  v_manager_role VARCHAR(50);
  v_manager_name VARCHAR(150);
  v_scope_count INT;
  v_elem JSONB;
  v_dept_id UUID;
  v_site_id UUID;
  v_dept_org_id UUID;
  v_site_org_id UUID;
  v_dept_active BOOLEAN;
  v_site_active BOOLEAN;
  v_seen_pairs TEXT[] := ARRAY[]::TEXT[];
  v_pair_key TEXT;
  v_primary_dept_id UUID := NULL;
  v_primary_site_id UUID := NULL;
BEGIN
  -- 1. Caller Authorization Guard: Must be Company Admin or Platform Admin
  v_caller_id := auth.uid();
  v_is_plat_admin := public.is_platform_admin();

  IF v_caller_id IS NULL OR NOT (public.is_admin() OR v_is_plat_admin) THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Only authenticated Company Administrators may configure manager scopes.';
  END IF;

  v_caller_org_id := public.get_my_organization_id();

  -- 2. Validate Manager Profile & Tenant Scoping
  SELECT p.organization_id, r.code, p.full_name
  INTO v_manager_org_id, v_manager_role, v_manager_name
  FROM public.profiles p
  JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = p_manager_id;

  IF v_manager_org_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Error: Manager profile % not found.', p_manager_id;
  END IF;

  IF v_manager_role != 'manager' THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Only users with the Manager role can have manager scopes (user has role "%").', v_manager_role;
  END IF;

  IF NOT v_is_plat_admin AND v_caller_id IS NOT NULL AND (v_manager_org_id IS DISTINCT FROM v_caller_org_id) THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Cannot modify manager scopes for another organization.';
  END IF;

  -- 3. Validate Scopes Payload
  IF p_scopes IS NULL OR jsonb_typeof(p_scopes) != 'array' THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Scopes payload must be a JSON array.';
  END IF;

  v_scope_count := jsonb_array_length(p_scopes);
  IF v_scope_count < 1 THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: At least one valid Manager scope (Department + Site) is required.';
  END IF;

  -- 4. Validate Each Scope (Tenant, Active Status, No Duplicates)
  FOR i IN 0..(v_scope_count - 1) LOOP
    v_elem := p_scopes->i;
    v_dept_id := (v_elem->>'department_id')::UUID;
    v_site_id := (v_elem->>'site_id')::UUID;

    IF v_dept_id IS NULL OR v_site_id IS NULL THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Each scope must contain valid department_id and site_id UUIDs.';
    END IF;

    -- Duplicate Check
    v_pair_key := v_dept_id::TEXT || ':' || v_site_id::TEXT;
    IF v_pair_key = ANY(v_seen_pairs) THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Duplicate scope detected for Department % and Site %.', v_dept_id, v_site_id;
    END IF;
    v_seen_pairs := array_append(v_seen_pairs, v_pair_key);

    -- Check Department belongs to manager org and is active
    SELECT organization_id, is_active
    INTO v_dept_org_id, v_dept_active
    FROM public.departments
    WHERE id = v_dept_id;

    IF v_dept_org_id IS NULL OR (v_dept_org_id IS DISTINCT FROM v_manager_org_id) THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Department % does not belong to the manager organization.', v_dept_id;
    END IF;

    IF NOT v_dept_active THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Cannot assign inactive department % to manager scope.', v_dept_id;
    END IF;

    -- Check Site belongs to manager org and is active
    SELECT organization_id, is_active
    INTO v_site_org_id, v_site_active
    FROM public.sites
    WHERE id = v_site_id;

    IF v_site_org_id IS NULL OR (v_site_org_id IS DISTINCT FROM v_manager_org_id) THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Site % does not belong to the manager organization.', v_site_id;
    END IF;

    IF NOT v_site_active THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Cannot assign inactive site % to manager scope.', v_site_id;
    END IF;

    -- Save first scope as default primary for profiles table compatibility
    IF i = 0 THEN
      v_primary_dept_id := v_dept_id;
      v_primary_site_id := v_site_id;
    END IF;
  END LOOP;

  -- 5. Atomic Replace of Manager Scopes in Database
  DELETE FROM public.manager_scopes
  WHERE manager_profile_id = p_manager_id;

  FOR i IN 0..(v_scope_count - 1) LOOP
    v_elem := p_scopes->i;
    v_dept_id := (v_elem->>'department_id')::UUID;
    v_site_id := (v_elem->>'site_id')::UUID;

    INSERT INTO public.manager_scopes (
      manager_profile_id,
      department_id,
      site_id
    ) VALUES (
      p_manager_id,
      v_dept_id,
      v_site_id
    );
  END LOOP;

  -- 6. Synchronize primary department & site on profile to ensure profile record consistency
  UPDATE public.profiles
  SET
    department_id = v_primary_dept_id,
    site_id = v_primary_site_id,
    updated_at = now()
  WHERE id = p_manager_id;

  RETURN jsonb_build_object(
    'success', true,
    'manager_id', p_manager_id,
    'scopes_count', v_scope_count
  );
END;
$$;

COMMENT ON FUNCTION public.sync_manager_scopes(UUID, JSONB) IS
  'Atomically replaces and validates multiple Department + Site management scopes for a Manager.';

REVOKE EXECUTE ON FUNCTION public.sync_manager_scopes(UUID, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_manager_scopes(UUID, JSONB) TO authenticated;


-- ----------------------------------------------------------------------------
-- 2. Audit Helper Function to Inspect System Users and Dependencies
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_system_users_audit()
RETURNS TABLE (
  user_id UUID,
  email TEXT,
  full_name TEXT,
  role_code TEXT,
  organization_id UUID,
  org_name TEXT,
  is_active BOOLEAN,
  is_primary_admin BOOLEAN,
  scopes_count BIGINT,
  teams_count BIGINT,
  actions_assigned_count BIGINT,
  actions_created_count BIGINT,
  is_protected BOOLEAN
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT
    COALESCE(p.id, u.id) AS user_id,
    COALESCE(p.email, u.email)::TEXT AS email,
    COALESCE(p.full_name, 'No Profile')::TEXT AS full_name,
    COALESCE(r.code, 'unknown')::TEXT AS role_code,
    p.organization_id,
    COALESCE(o.name, 'No Org')::TEXT AS org_name,
    COALESCE(p.is_active, true) AS is_active,
    COALESCE(p.is_primary_admin, false) AS is_primary_admin,
    COALESCE(ms.cnt, 0) AS scopes_count,
    COALESCE(tm.cnt, 0) AS teams_count,
    COALESCE(act_ass.cnt, 0) AS actions_assigned_count,
    COALESCE(act_cre.cnt, 0) AS actions_created_count,
    (COALESCE(p.email, u.email) IN (
      'arvin.pr1112@gmail.com',
      'aravind11.sobha@gmail.com',
      'webonant@gmail.com',
      'aravindpr.1111@gmail.com'
    )) AS is_protected
  FROM auth.users u
  FULL OUTER JOIN public.profiles p ON u.id = p.id
  LEFT JOIN public.roles r ON p.role_id = r.id
  LEFT JOIN public.organizations o ON p.organization_id = o.id
  LEFT JOIN (
    SELECT manager_profile_id, count(*) AS cnt
    FROM public.manager_scopes
    GROUP BY manager_profile_id
  ) ms ON ms.manager_profile_id = COALESCE(p.id, u.id)
  LEFT JOIN (
    SELECT profile_id, count(*) AS cnt
    FROM public.team_members
    GROUP BY profile_id
  ) tm ON tm.profile_id = COALESCE(p.id, u.id)
  LEFT JOIN (
    SELECT assigned_to, count(*) AS cnt
    FROM public.actions
    GROUP BY assigned_to
  ) act_ass ON act_ass.assigned_to = COALESCE(p.id, u.id)
  LEFT JOIN (
    SELECT created_by, count(*) AS cnt
    FROM public.actions
    GROUP BY created_by
  ) act_cre ON act_cre.created_by = COALESCE(p.id, u.id)
  ORDER BY COALESCE(p.created_at, u.created_at) ASC;
$$;

GRANT EXECUTE ON FUNCTION public.get_system_users_audit() TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_system_account_requests_audit()
RETURNS TABLE (
  request_id UUID,
  auth_user_id UUID,
  email TEXT,
  full_name TEXT,
  role_id UUID,
  status TEXT,
  is_email_verified BOOLEAN,
  organization_id UUID,
  created_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT
    id AS request_id,
    auth_user_id,
    email::TEXT,
    full_name::TEXT,
    requested_role_id AS role_id,
    status::TEXT,
    is_email_verified,
    organization_id,
    created_at
  FROM public.account_requests
  ORDER BY created_at ASC;
$$;

GRANT EXECUTE ON FUNCTION public.get_system_account_requests_audit() TO anon, authenticated;
