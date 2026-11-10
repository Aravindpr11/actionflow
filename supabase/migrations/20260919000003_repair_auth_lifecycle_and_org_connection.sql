-- ============================================================================
-- ActionFlow Critical Authentication & Organization Flow Repair
-- Migration: 20260919000003_repair_auth_lifecycle_and_org_connection.sql
-- ============================================================================
-- 1. Table-level DAC Privileges for Anonymous Applicants:
--    Grants SELECT on departments, sites, teams, roles, organizations to 'anon'
--    so unauthenticated users can load real company structures during signup.
--    Row Level Security (RLS) policies on these tables already enforce
--    (is_active = true) and isolate data.
-- 2. Enhanced handle_new_auth_user() Trigger:
--    Ensures public.account_requests receives a valid, verified organization_id
--    derived from the applicant's chosen Department/Site, resolving the
--    enforce_account_request_org_consistency trigger requirements.
--    Strictly ensures NO row in public.profiles is created prior to Admin approval.
-- 3. Atomic Account Approval RPC (approve_account_request):
--    Transactionally validates the account request, verifies email confirmation,
--    derives the exact Company Admin organization_id, creates the active profile,
--    links manager scopes or team memberships, and marks the request approved.
-- 4. Atomic Account Rejection RPC (reject_account_request):
--    Transactionally rejects an account request with a mandatory explanation reason.
-- 5. Atomic Company User Deletion RPC (delete_company_user):
--    Enforces strict multi-tenant boundary, protects Platform Owners, primary admins,
--    and other organizations, and permanently removes tenant users across
--    team_members, manager_scopes, account_requests, profiles, and auth.users.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Table-level DAC Grants for Anonymous Signup
-- ----------------------------------------------------------------------------
GRANT SELECT ON public.departments TO anon;
GRANT SELECT ON public.sites TO anon;
GRANT SELECT ON public.teams TO anon;
GRANT SELECT ON public.roles TO anon;
GRANT SELECT ON public.organizations TO anon;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon;

-- ----------------------------------------------------------------------------
-- 2. Update handle_new_auth_user() Trigger
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_full_name VARCHAR(150);
  v_phone VARCHAR(50);
  v_designation VARCHAR(150);
  v_requested_role VARCHAR(50);
  v_role_id UUID;
  v_dept_id UUID;
  v_site_id UUID;
  v_team_id UUID;
  v_org_id UUID;
  v_dept_org_id UUID;
  v_site_org_id UUID;
  v_team_org_id UUID;
  v_dept_id_raw TEXT;
  v_site_id_raw TEXT;
  v_team_id_raw TEXT;
  v_account_request_id UUID;
  v_scope_item JSONB;
  v_scope_count INT := 0;
  v_is_email_verified BOOLEAN := false;
  v_initial_status VARCHAR(50) := 'pending_email_verification';
  v_email_verified_at TIMESTAMPTZ := NULL;
BEGIN
  -- Bypass if metadata is absent or empty (e.g. system seeds / direct admin auth creations)
  IF NEW.raw_user_meta_data IS NULL OR NEW.raw_user_meta_data = '{}'::jsonb THEN
    RETURN NEW;
  END IF;

  -- Validate authoritative email from auth.users
  IF NEW.email IS NULL OR length(trim(NEW.email)) = 0 THEN
    RAISE EXCEPTION 'ActionFlow Signup Error: Authoritative email on auth.users is required.';
  END IF;

  -- If user was created with email already confirmed
  IF NEW.email_confirmed_at IS NOT NULL THEN
    v_is_email_verified := true;
    v_initial_status := 'pending_admin_approval';
    v_email_verified_at := NEW.email_confirmed_at;
  END IF;

  -- 1. Extract required basic profile metadata
  v_full_name := trim(COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''));
  v_phone := nullif(trim(COALESCE(NEW.raw_user_meta_data ->> 'phone', '')), '');
  v_designation := trim(COALESCE(NEW.raw_user_meta_data ->> 'designation', ''));
  v_requested_role := lower(trim(COALESCE(NEW.raw_user_meta_data ->> 'requested_role', '')));

  IF length(v_full_name) = 0 THEN
    RAISE EXCEPTION 'ActionFlow Signup Error: full_name is required in signup metadata.';
  END IF;

  IF length(v_designation) = 0 THEN
    RAISE EXCEPTION 'ActionFlow Signup Error: designation is required in signup metadata.';
  END IF;

  -- 2. Validate requested role (Must be Staff or Manager; Admin is strictly forbidden)
  IF v_requested_role = 'admin' THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Public signup requests are restricted to Manager and Staff roles. The Admin role cannot be requested.';
  END IF;

  IF v_requested_role NOT IN ('manager', 'staff') THEN
    RAISE EXCEPTION 'ActionFlow Signup Error: Invalid requested_role (%). Permitted roles are Manager and Staff.', v_requested_role;
  END IF;

  SELECT id INTO v_role_id FROM public.roles WHERE code = v_requested_role;
  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Signup Error: Role configuration error; role % not found.', v_requested_role;
  END IF;

  -- 3. Branch by requested role: Staff vs Manager
  IF v_requested_role = 'staff' THEN
    v_dept_id_raw := NEW.raw_user_meta_data ->> 'department_id';
    v_site_id_raw := NEW.raw_user_meta_data ->> 'site_id';
    v_team_id_raw := NEW.raw_user_meta_data ->> 'team_id';

    IF v_dept_id_raw IS NULL OR length(trim(v_dept_id_raw)) = 0 THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Staff account requests must specify department_id.';
    END IF;

    IF v_site_id_raw IS NULL OR length(trim(v_site_id_raw)) = 0 THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Staff account requests must specify site_id.';
    END IF;

    v_dept_id := v_dept_id_raw::UUID;
    v_site_id := v_site_id_raw::UUID;

    -- Verify department exists, is active, and fetch its organization_id
    SELECT organization_id INTO v_dept_org_id
    FROM public.departments
    WHERE id = v_dept_id AND is_active = true;

    IF v_dept_org_id IS NULL THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Selected department does not exist, is inactive, or has no organization.';
    END IF;

    v_org_id := v_dept_org_id;

    -- Verify site exists, is active, and belongs to the same organization
    SELECT organization_id INTO v_site_org_id
    FROM public.sites
    WHERE id = v_site_id AND is_active = true;

    IF v_site_org_id IS NULL OR v_site_org_id != v_org_id THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Selected site does not exist, is inactive, or belongs to another organization.';
    END IF;

    -- Optional team_id for Staff only
    IF v_team_id_raw IS NOT NULL AND length(trim(v_team_id_raw)) > 0 THEN
      v_team_id := v_team_id_raw::UUID;
      SELECT organization_id INTO v_team_org_id
      FROM public.teams
      WHERE id = v_team_id
        AND department_id = v_dept_id
        AND is_active = true;

      IF v_team_org_id IS NULL OR v_team_org_id != v_org_id THEN
        RAISE EXCEPTION 'ActionFlow Signup Error: Selected team does not belong to the selected department or organization.';
      END IF;
    ELSE
      v_team_id := NULL;
    END IF;

    -- Staff cannot supply scopes array
    IF NEW.raw_user_meta_data ? 'scopes'
       AND jsonb_typeof(NEW.raw_user_meta_data -> 'scopes') = 'array'
       AND jsonb_array_length(NEW.raw_user_meta_data -> 'scopes') > 0 THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Staff requests cannot provide scopes array.';
    END IF;

    -- Create account_requests row for Staff with resolved organization_id
    INSERT INTO public.account_requests (
      auth_user_id,
      organization_id,
      full_name,
      email,
      phone,
      designation,
      department_id,
      site_id,
      team_id,
      requested_role_id,
      status,
      is_email_verified,
      email_verified_at
    ) VALUES (
      NEW.id,
      v_org_id,
      v_full_name,
      NEW.email,
      v_phone,
      v_designation,
      v_dept_id,
      v_site_id,
      v_team_id,
      v_role_id,
      v_initial_status,
      v_is_email_verified,
      v_email_verified_at
    );

  ELSIF v_requested_role = 'manager' THEN
    -- Manager cannot supply team_id
    IF NEW.raw_user_meta_data ? 'team_id'
       AND NEW.raw_user_meta_data ->> 'team_id' IS NOT NULL
       AND length(trim(NEW.raw_user_meta_data ->> 'team_id')) > 0 THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Team selection is only applicable to Staff requests. Manager operational scopes must be defined via scopes array.';
    END IF;

    -- Scopes array is required for Manager
    IF NOT (NEW.raw_user_meta_data ? 'scopes')
       OR jsonb_typeof(NEW.raw_user_meta_data -> 'scopes') != 'array'
       OR jsonb_array_length(NEW.raw_user_meta_data -> 'scopes') = 0 THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Manager requests must provide a non-empty scopes array containing Department + Site combinations.';
    END IF;

    -- Derive organization_id from the first scope item
    v_dept_id_raw := NEW.raw_user_meta_data -> 'scopes' -> 0 ->> 'department_id';
    IF v_dept_id_raw IS NULL OR length(trim(v_dept_id_raw)) = 0 THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: First scope item must contain a valid department_id.';
    END IF;

    SELECT organization_id INTO v_org_id
    FROM public.departments
    WHERE id = v_dept_id_raw::UUID AND is_active = true;

    IF v_org_id IS NULL THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Scope department does not exist, is inactive, or has no organization.';
    END IF;

    -- Create account_requests row for Manager (department_id, site_id, team_id are NULL)
    INSERT INTO public.account_requests (
      auth_user_id,
      organization_id,
      full_name,
      email,
      phone,
      designation,
      department_id,
      site_id,
      team_id,
      requested_role_id,
      status,
      is_email_verified,
      email_verified_at
    ) VALUES (
      NEW.id,
      v_org_id,
      v_full_name,
      NEW.email,
      v_phone,
      v_designation,
      NULL,
      NULL,
      NULL,
      v_role_id,
      v_initial_status,
      v_is_email_verified,
      v_email_verified_at
    ) RETURNING id INTO v_account_request_id;

    -- Unpack and validate each scope combination
    FOR v_scope_item IN SELECT * FROM jsonb_array_elements(NEW.raw_user_meta_data -> 'scopes')
    LOOP
      v_dept_id_raw := v_scope_item ->> 'department_id';
      v_site_id_raw := v_scope_item ->> 'site_id';

      IF v_dept_id_raw IS NULL OR v_site_id_raw IS NULL
         OR length(trim(v_dept_id_raw)) = 0 OR length(trim(v_site_id_raw)) = 0 THEN
        RAISE EXCEPTION 'ActionFlow Signup Error: Each scope item must contain valid department_id and site_id.';
      END IF;

      v_dept_id := v_dept_id_raw::UUID;
      v_site_id := v_site_id_raw::UUID;

      -- Validate department exists, is active, and belongs to the derived organization
      SELECT organization_id INTO v_dept_org_id
      FROM public.departments
      WHERE id = v_dept_id AND is_active = true;

      IF v_dept_org_id IS NULL OR v_dept_org_id != v_org_id THEN
        RAISE EXCEPTION 'ActionFlow Signup Error: Scope department (%) does not belong to the requested organization.', v_dept_id;
      END IF;

      -- Validate site exists, is active, and belongs to the derived organization
      SELECT organization_id INTO v_site_org_id
      FROM public.sites
      WHERE id = v_site_id AND is_active = true;

      IF v_site_org_id IS NULL OR v_site_org_id != v_org_id THEN
        RAISE EXCEPTION 'ActionFlow Signup Error: Scope site (%) does not belong to the requested organization.', v_site_id;
      END IF;

      -- Insert validated scope into account_request_scopes
      INSERT INTO public.account_request_scopes (
        account_request_id,
        department_id,
        site_id
      ) VALUES (
        v_account_request_id,
        v_dept_id,
        v_site_id
      ) ON CONFLICT (account_request_id, department_id, site_id) DO NOTHING;

      v_scope_count := v_scope_count + 1;
    END LOOP;

    IF v_scope_count = 0 THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Manager requests must specify at least one valid scope.';
    END IF;
  END IF;

  -- CRITICAL SECURITY INVARIANT:
  -- Never insert into public.profiles during signup.
  -- Profiles are strictly created when approved by the Company Admin.
  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. Atomic Account Approval RPC (approve_account_request)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_account_request(
  p_request_id UUID,
  p_override_department_id UUID DEFAULT NULL,
  p_override_site_id UUID DEFAULT NULL,
  p_override_team_id UUID DEFAULT NULL,
  p_override_role_code TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_org_id UUID;
  v_req RECORD;
  v_role_id UUID;
  v_role_code VARCHAR(50);
  v_dept_id UUID;
  v_site_id UUID;
  v_team_id UUID;
  v_scope_count INT := 0;
BEGIN
  -- 1. Caller Authorization: Must be an authenticated Company Admin
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Only Company Administrators may approve account requests.';
  END IF;

  v_caller_org_id := public.get_my_organization_id();
  IF v_caller_org_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Caller is not associated with an organization.';
  END IF;

  -- 2. Fetch the target account request
  SELECT * INTO v_req
  FROM public.account_requests
  WHERE id = p_request_id;

  IF v_req.id IS NULL THEN
    RAISE EXCEPTION 'Account request not found (ID: %).', p_request_id;
  END IF;

  -- 3. Multi-Tenant Check: Request must belong to caller's organization
  IF v_req.organization_id IS DISTINCT FROM v_caller_org_id THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Cannot approve an account request for another organization.';
  END IF;

  -- 4. Lifecycle Check: Email must be verified and status must be pending_admin_approval
  IF v_req.status = 'approved' THEN
    RAISE EXCEPTION 'Account request is already approved.';
  END IF;

  IF v_req.is_email_verified != true THEN
    RAISE EXCEPTION 'ActionFlow Approval Error: Account request cannot be approved until email verification is complete.';
  END IF;

  IF v_req.status != 'pending_admin_approval' THEN
    RAISE EXCEPTION 'ActionFlow Approval Error: Request is in state "%" and is not awaiting approval.', v_req.status;
  END IF;

  -- 5. Resolve Target Role
  IF p_override_role_code IS NOT NULL AND length(trim(p_override_role_code)) > 0 THEN
    v_role_code := lower(trim(p_override_role_code));
  ELSE
    SELECT code INTO v_role_code FROM public.roles WHERE id = v_req.requested_role_id;
  END IF;

  IF v_role_code NOT IN ('staff', 'manager', 'admin') THEN
    v_role_code := 'staff';
  END IF;

  SELECT id INTO v_role_id FROM public.roles WHERE code = v_role_code;
  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Approval Error: Role "%" not found in system roles.', v_role_code;
  END IF;

  -- 6. Branch by Role: Staff vs Manager
  IF v_role_code = 'staff' THEN
    v_dept_id := COALESCE(p_override_department_id, v_req.department_id);
    v_site_id := COALESCE(p_override_site_id, v_req.site_id);
    v_team_id := COALESCE(p_override_team_id, v_req.team_id);

    IF v_dept_id IS NULL OR v_site_id IS NULL THEN
      RAISE EXCEPTION 'ActionFlow Approval Error: Staff account must have both department_id and site_id.';
    END IF;

    -- Verify department belongs to caller's organization
    IF NOT EXISTS (
      SELECT 1 FROM public.departments
      WHERE id = v_dept_id AND organization_id = v_caller_org_id AND is_active = true
    ) THEN
      RAISE EXCEPTION 'ActionFlow Approval Error: Department does not belong to your organization or is inactive.';
    END IF;

    -- Verify site belongs to caller's organization
    IF NOT EXISTS (
      SELECT 1 FROM public.sites
      WHERE id = v_site_id AND organization_id = v_caller_org_id AND is_active = true
    ) THEN
      RAISE EXCEPTION 'ActionFlow Approval Error: Site does not belong to your organization or is inactive.';
    END IF;

    -- Verify team if supplied
    IF v_team_id IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.teams
        WHERE id = v_team_id
          AND department_id = v_dept_id
          AND organization_id = v_caller_org_id
          AND is_active = true
      ) THEN
        RAISE EXCEPTION 'ActionFlow Approval Error: Selected team does not belong to the assigned department or organization.';
      END IF;
    END IF;

    -- Upsert profile in public.profiles
    INSERT INTO public.profiles (
      id,
      organization_id,
      full_name,
      email,
      phone,
      designation,
      department_id,
      site_id,
      role_id,
      status,
      is_active,
      is_primary_admin
    ) VALUES (
      v_req.auth_user_id,
      v_caller_org_id,
      v_req.full_name,
      v_req.email,
      v_req.phone,
      v_req.designation,
      v_dept_id,
      v_site_id,
      v_role_id,
      'active',
      true,
      false
    )
    ON CONFLICT (id) DO UPDATE SET
      organization_id = EXCLUDED.organization_id,
      full_name = EXCLUDED.full_name,
      phone = EXCLUDED.phone,
      designation = EXCLUDED.designation,
      department_id = EXCLUDED.department_id,
      site_id = EXCLUDED.site_id,
      role_id = EXCLUDED.role_id,
      status = 'active',
      is_active = true,
      updated_at = now();

    -- Upsert team membership if team was selected
    IF v_team_id IS NOT NULL THEN
      INSERT INTO public.team_members (team_id, profile_id, role_in_team)
      VALUES (v_team_id, v_req.auth_user_id, 'member')
      ON CONFLICT (team_id, profile_id) DO NOTHING;
    END IF;

  ELSIF v_role_code = 'manager' THEN
    -- Verify manager has scopes
    SELECT COUNT(*) INTO v_scope_count
    FROM public.account_request_scopes
    WHERE account_request_id = p_request_id;

    IF v_scope_count = 0 THEN
      RAISE EXCEPTION 'ActionFlow Approval Error: Manager request has no configured scopes in account_request_scopes.';
    END IF;

    -- Upsert manager profile with NULL primary department and site (scopes define management areas)
    INSERT INTO public.profiles (
      id,
      organization_id,
      full_name,
      email,
      phone,
      designation,
      department_id,
      site_id,
      role_id,
      status,
      is_active,
      is_primary_admin
    ) VALUES (
      v_req.auth_user_id,
      v_caller_org_id,
      v_req.full_name,
      v_req.email,
      v_req.phone,
      v_req.designation,
      NULL,
      NULL,
      v_role_id,
      'active',
      true,
      false
    )
    ON CONFLICT (id) DO UPDATE SET
      organization_id = EXCLUDED.organization_id,
      full_name = EXCLUDED.full_name,
      phone = EXCLUDED.phone,
      designation = EXCLUDED.designation,
      department_id = NULL,
      site_id = NULL,
      role_id = EXCLUDED.role_id,
      status = 'active',
      is_active = true,
      updated_at = now();

    -- Copy account_request_scopes to manager_scopes
    INSERT INTO public.manager_scopes (manager_profile_id, department_id, site_id)
    SELECT v_req.auth_user_id, ars.department_id, ars.site_id
    FROM public.account_request_scopes ars
    WHERE ars.account_request_id = p_request_id
    ON CONFLICT (manager_profile_id, department_id, site_id) DO NOTHING;

  ELSE
    -- Admin role override
    INSERT INTO public.profiles (
      id,
      organization_id,
      full_name,
      email,
      phone,
      designation,
      department_id,
      site_id,
      role_id,
      status,
      is_active,
      is_primary_admin
    ) VALUES (
      v_req.auth_user_id,
      v_caller_org_id,
      v_req.full_name,
      v_req.email,
      v_req.phone,
      v_req.designation,
      NULL,
      NULL,
      v_role_id,
      'active',
      true,
      false
    )
    ON CONFLICT (id) DO UPDATE SET
      organization_id = EXCLUDED.organization_id,
      full_name = EXCLUDED.full_name,
      phone = EXCLUDED.phone,
      designation = EXCLUDED.designation,
      role_id = EXCLUDED.role_id,
      status = 'active',
      is_active = true,
      updated_at = now();
  END IF;

  -- 7. Update account_requests to approved
  UPDATE public.account_requests
  SET
    status = 'approved',
    created_profile_id = v_req.auth_user_id,
    reviewed_by = auth.uid(),
    reviewed_at = now(),
    department_id = v_dept_id,
    site_id = v_site_id,
    team_id = v_team_id,
    updated_at = now()
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', p_request_id,
    'auth_user_id', v_req.auth_user_id,
    'role', v_role_code,
    'organization_id', v_caller_org_id
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. Atomic Account Rejection RPC (reject_account_request)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reject_account_request(
  p_request_id UUID,
  p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_org_id UUID;
  v_req RECORD;
  v_clean_reason TEXT;
BEGIN
  -- 1. Caller Authorization: Must be Company Admin
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Only Company Administrators may reject account requests.';
  END IF;

  v_caller_org_id := public.get_my_organization_id();
  IF v_caller_org_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Caller is not associated with an organization.';
  END IF;

  -- 2. Validate Reason
  v_clean_reason := trim(COALESCE(p_reason, ''));
  IF length(v_clean_reason) < 5 THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Rejection reason must be at least 5 characters.';
  END IF;

  -- 3. Fetch Request
  SELECT * INTO v_req
  FROM public.account_requests
  WHERE id = p_request_id;

  IF v_req.id IS NULL THEN
    RAISE EXCEPTION 'Account request not found (ID: %).', p_request_id;
  END IF;

  IF v_req.organization_id IS DISTINCT FROM v_caller_org_id THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Cannot reject an account request for another organization.';
  END IF;

  -- 4. Update Request
  UPDATE public.account_requests
  SET
    status = 'rejected',
    rejection_reason = v_clean_reason,
    reviewed_by = auth.uid(),
    reviewed_at = now(),
    updated_at = now()
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', p_request_id,
    'status', 'rejected'
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. Atomic Company User Deletion RPC (delete_company_user)
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
  -- 1. Caller Authorization: Must be an authenticated Company Admin
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Only Company Administrators may delete tenant users.';
  END IF;

  v_caller_org_id := public.get_my_organization_id();
  IF v_caller_org_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Caller is not associated with an organization.';
  END IF;

  -- 2. Self-Deletion Guard: Cannot delete self
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

  -- 5. Multi-Tenant Guard: Target must belong to caller's organization
  IF v_target_org_id IS DISTINCT FROM v_caller_org_id THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Cannot delete a user belonging to another organization.';
  END IF;

  -- 6. Primary Admin / Admin Invariant: Cannot delete Company Admin
  IF v_target_is_primary_admin = true OR v_target_role = 'admin' THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Company Administrators cannot be deleted from this interface.';
  END IF;

  -- 7. Cascade Deletion in strict reverse dependency order:
  -- A. team_members
  DELETE FROM public.team_members WHERE profile_id = p_user_id;

  -- B. manager_scopes
  DELETE FROM public.manager_scopes WHERE manager_profile_id = p_user_id;

  -- C. account_request_scopes
  DELETE FROM public.account_request_scopes
  WHERE account_request_id IN (
    SELECT id FROM public.account_requests WHERE auth_user_id = p_user_id
  );

  -- D. account_requests
  DELETE FROM public.account_requests WHERE auth_user_id = p_user_id;

  -- E. profiles
  DELETE FROM public.profiles WHERE id = p_user_id;

  -- F. auth.users (permanently purges GoTrue user so email can be reused)
  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'email', v_target_email,
    'name', v_target_name,
    'organization_id', v_caller_org_id
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. Grant Execute Permissions on RPCs
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.approve_account_request FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_account_request TO authenticated;

REVOKE EXECUTE ON FUNCTION public.reject_account_request FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reject_account_request TO authenticated;

REVOKE EXECUTE ON FUNCTION public.delete_company_user FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_company_user TO authenticated;

