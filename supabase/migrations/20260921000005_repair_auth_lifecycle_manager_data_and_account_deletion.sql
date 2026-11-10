-- ============================================================================
-- Migration: 20260921000005_repair_auth_lifecycle_manager_data_and_account_deletion.sql
-- Description:
--   1. Allow system/migration scripts in enforce_profile_update_security()
--   2. Repair Manager (webonant@gmail.com) department_id, site_id, and teams
--   3. Add missing manager scope (test dept, test site) so staff is visible
--   4. Synchronize passwords for webonant and staff test accounts
--   5. Enhance delete_company_user to safely handle actions.created_by FK
--   6. Implement delete_self_account for Manager and Staff self-service deletion
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. System Guard in enforce_profile_update_security()
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_profile_update_security()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  -- System / migration execution (e.g. CLI db push or direct DB maintenance with no client auth)
  IF auth.uid() IS NULL OR current_user IN ('postgres', 'supabase_admin') THEN
    RETURN NEW;
  END IF;

  -- Check if caller is Platform Admin or Company Admin
  IF NOT (public.is_admin() OR public.is_platform_admin()) THEN
    -- Non-admin users can ONLY update personal details (full_name, phone, avatar_url)
    IF NEW.role_id IS DISTINCT FROM OLD.role_id OR
       NEW.department_id IS DISTINCT FROM OLD.department_id OR
       NEW.site_id IS DISTINCT FROM OLD.site_id OR
       NEW.organization_id IS DISTINCT FROM OLD.organization_id OR
       NEW.designation IS DISTINCT FROM OLD.designation OR
       NEW.status IS DISTINCT FROM OLD.status OR
       NEW.is_active IS DISTINCT FROM OLD.is_active OR
       NEW.is_primary_admin IS DISTINCT FROM OLD.is_primary_admin OR
       NEW.email IS DISTINCT FROM OLD.email OR
       NEW.id IS DISTINCT FROM OLD.id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Non-admin users may only update personal details (full_name, phone, avatar_url).';
    END IF;
  END IF;

  -- Company Admins cannot change a user's organization_id (only Platform Admin may do so)
  IF NOT public.is_platform_admin() THEN
    IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Only Platform Administrators may reassign user organization.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. Data Repair: Manager webonant@gmail.com
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_mgr_id UUID := '878d9145-7764-411f-8d26-f30f01e99e79';
  v_hse_dept_id UUID := 'f0ad05aa-c85a-40e5-b309-19f1e6629e7a'; -- HSE / Safety
  v_test_site_id UUID := '6abf4ba5-e8b7-4076-8c97-80f4a354f94b'; -- test site
  v_test_dept_id UUID := '6000544e-dfe7-4911-b2cc-4c4bebead468'; -- test dept
  v_team_insp_id UUID := '95c9b84e-c9e9-4838-babc-9f3171e36b9c'; -- Safety Inspection Team
  v_team_er_id UUID := '3e5465f5-a305-4356-a183-0abfa642d910';   -- HSE Emergency Response Team
BEGIN
  -- A. Set primary department and site on profile
  UPDATE public.profiles
  SET
    department_id = v_hse_dept_id,
    site_id = v_test_site_id,
    updated_at = now()
  WHERE id = v_mgr_id;

  -- B. Remove mismatched team memberships (e.g. Field Operations in Operations dept)
  DELETE FROM public.team_members
  WHERE profile_id = v_mgr_id
    AND team_id NOT IN (
      SELECT id FROM public.teams WHERE department_id = v_hse_dept_id
    );

  -- C. Ensure manager belongs to HSE Safety teams
  IF NOT EXISTS (SELECT 1 FROM public.team_members WHERE profile_id = v_mgr_id AND team_id = v_team_insp_id) THEN
    INSERT INTO public.team_members (team_id, profile_id, role_in_team)
    VALUES (v_team_insp_id, v_mgr_id, 'manager');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.team_members WHERE profile_id = v_mgr_id AND team_id = v_team_er_id) THEN
    INSERT INTO public.team_members (team_id, profile_id, role_in_team)
    VALUES (v_team_er_id, v_mgr_id, 'manager');
  END IF;

  -- D. Ensure manager has scope for (test dept, test site) so staff registered in (test, test) is visible
  IF NOT EXISTS (
    SELECT 1 FROM public.manager_scopes
    WHERE manager_profile_id = v_mgr_id
      AND department_id = v_test_dept_id
      AND site_id = v_test_site_id
  ) THEN
    INSERT INTO public.manager_scopes (
      manager_profile_id,
      department_id,
      site_id
    ) VALUES (
      v_mgr_id,
      v_test_dept_id,
      v_test_site_id
    );
  END IF;

  -- E. Set predictable password for webonant@gmail.com and staff aravindpr.1111@gmail.com
  UPDATE auth.users
  SET encrypted_password = extensions.crypt('Password123!', extensions.gen_salt('bf'))
  WHERE email IN ('webonant@gmail.com', 'aravindpr.1111@gmail.com');

END $$;

-- ----------------------------------------------------------------------------
-- 3. Enhanced delete_company_user(p_user_id UUID)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_company_user(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_org_id UUID;
  v_target_org_id UUID;
  v_target_is_primary_admin BOOLEAN;
  v_target_role VARCHAR(50);
  v_target_email VARCHAR(255);
  v_target_name VARCHAR(150);
BEGIN
  -- 1. Caller Authorization: Must be an authenticated Company Admin or Platform Admin
  IF NOT (public.is_admin() OR public.is_platform_admin()) THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Only Company Administrators may delete tenant users.';
  END IF;

  v_caller_org_id := public.get_my_organization_id();
  IF NOT public.is_platform_admin() AND v_caller_org_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Caller is not associated with an organization.';
  END IF;

  -- 2. Self-Deletion Guard: Cannot delete self through company admin tool
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: You cannot delete your own active administrator account.';
  END IF;

  -- 3. Platform Admin Protection: Never delete any Platform Administrator
  IF EXISTS (SELECT 1 FROM public.platform_admins WHERE user_id = p_user_id) THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Platform Administrators cannot be deleted by Company Administrators.';
  END IF;

  -- 4. Inspect Target in profiles
  SELECT
    p.organization_id,
    p.is_primary_admin,
    r.code,
    p.email,
    p.full_name
  INTO
    v_target_org_id,
    v_target_is_primary_admin,
    v_target_role,
    v_target_email,
    v_target_name
  FROM public.profiles p
  LEFT JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = p_user_id;

  IF v_target_org_id IS NULL THEN
    -- Fall back to checking account_requests if profile was never created
    SELECT organization_id, email, full_name
    INTO v_target_org_id, v_target_email, v_target_name
    FROM public.account_requests
    WHERE auth_user_id = p_user_id;

    IF v_target_org_id IS NULL THEN
      RAISE EXCEPTION 'User not found or has no profile/account request.';
    END IF;
  END IF;

  -- 5. Multi-Tenant Guard: Target must belong to caller's organization (unless Platform Admin)
  IF NOT public.is_platform_admin() AND (v_target_org_id IS DISTINCT FROM v_caller_org_id) THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Cannot delete a user belonging to another organization.';
  END IF;

  -- 6. Primary Admin / Admin Invariant: Cannot delete Company Admin
  IF v_target_is_primary_admin = true OR v_target_role = 'admin' THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Company Administrators cannot be deleted from this interface.';
  END IF;

  -- 7. Safe Action References Handling (prevents foreign key RESTRICT violations):
  -- A. Reassign created_by actions to the deleting admin to preserve organizational action history
  UPDATE public.actions
  SET created_by = auth.uid()
  WHERE created_by = p_user_id;

  -- B. Nullify assignment on pending/open actions
  UPDATE public.actions
  SET assigned_to = NULL
  WHERE assigned_to = p_user_id;

  -- C. Nullify verified_by on actions
  UPDATE public.actions
  SET verified_by = NULL
  WHERE verified_by = p_user_id;

  -- 8. Cascade Deletion in strict reverse dependency order:
  DELETE FROM public.team_members WHERE profile_id = p_user_id;
  DELETE FROM public.manager_scopes WHERE manager_profile_id = p_user_id;
  DELETE FROM public.account_request_scopes
  WHERE account_request_id IN (
    SELECT id FROM public.account_requests WHERE auth_user_id = p_user_id
  );
  DELETE FROM public.account_requests WHERE auth_user_id = p_user_id;
  DELETE FROM public.profiles WHERE id = p_user_id;
  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'email', v_target_email,
    'name', v_target_name,
    'organization_id', v_target_org_id
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. Self-Service Account Deletion RPC: delete_self_account()
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_self_account()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_org_id UUID;
  v_is_primary_admin BOOLEAN;
  v_is_platform_admin BOOLEAN;
  v_primary_admin_id UUID;
  v_target_email VARCHAR(255);
  v_target_name VARCHAR(150);
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Unauthenticated caller cannot delete account.';
  END IF;

  -- 1. Check Platform Admin protection
  IF EXISTS (SELECT 1 FROM public.platform_admins WHERE user_id = v_caller_id) THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Platform Administrator accounts cannot be self-deleted.';
  END IF;

  -- 2. Inspect caller profile
  SELECT
    p.organization_id,
    p.is_primary_admin,
    p.email,
    p.full_name
  INTO
    v_caller_org_id,
    v_is_primary_admin,
    v_target_email,
    v_target_name
  FROM public.profiles p
  WHERE p.id = v_caller_id;

  -- 3. Check Primary Company Admin protection
  IF v_is_primary_admin = true THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Primary Company Administrator accounts cannot be self-deleted.';
  END IF;

  -- 4. Find organization primary admin for action stewardship
  SELECT id INTO v_primary_admin_id
  FROM public.profiles
  WHERE organization_id = v_caller_org_id
    AND is_primary_admin = true
  LIMIT 1;

  IF v_primary_admin_id IS NULL THEN
    SELECT id INTO v_primary_admin_id
    FROM public.profiles p
    JOIN public.roles r ON p.role_id = r.id
    WHERE p.organization_id = v_caller_org_id
      AND (r.code = 'admin' OR r.name = 'Admin')
    LIMIT 1;
  END IF;

  -- 5. Safe Action References Handling:
  -- Reassign created_by actions to organization admin to preserve action history
  IF v_primary_admin_id IS NOT NULL THEN
    UPDATE public.actions
    SET created_by = v_primary_admin_id
    WHERE created_by = v_caller_id;
  END IF;

  -- Nullify assignment on actions
  UPDATE public.actions
  SET assigned_to = NULL
  WHERE assigned_to = v_caller_id;

  -- Nullify verification on actions
  UPDATE public.actions
  SET verified_by = NULL
  WHERE verified_by = v_caller_id;

  -- 6. Cascade Deletion in strict reverse dependency order:
  DELETE FROM public.team_members WHERE profile_id = v_caller_id;
  DELETE FROM public.manager_scopes WHERE manager_profile_id = v_caller_id;
  DELETE FROM public.account_request_scopes
  WHERE account_request_id IN (
    SELECT id FROM public.account_requests WHERE auth_user_id = v_caller_id
  );
  DELETE FROM public.account_requests WHERE auth_user_id = v_caller_id;
  DELETE FROM public.profiles WHERE id = v_caller_id;
  DELETE FROM auth.users WHERE id = v_caller_id;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_caller_id,
    'email', v_target_email,
    'name', v_target_name,
    'organization_id', v_caller_org_id
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. Grant Permissions on Deletion Functions
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.delete_company_user(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_company_user(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.delete_self_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_self_account() TO authenticated;

