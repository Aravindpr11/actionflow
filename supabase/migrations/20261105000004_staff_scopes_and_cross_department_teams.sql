-- ============================================================================
-- Migration: 20261105000004_staff_scopes_and_cross_department_teams.sql
-- Description:
--   1. Create public.staff_scopes table and sync_staff_scopes RPC for Staff multi-scope.
--   2. Allow Staff signup requests to provide and store pending account_request_scopes.
--   3. Sync approved Staff scopes to public.staff_scopes upon account approval.
--   4. Fix cross-department team membership: allow Staff & Managers to belong to
--      multiple Teams across departments within the same organization while
--      strictly preserving tenant isolation and role/active checks.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Table: public.staff_scopes
-- Multi-scope assignment for Staff users across Department + Site combinations.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.staff_scopes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
  site_id UUID NOT NULL REFERENCES public.sites(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_staff_scope UNIQUE (staff_profile_id, department_id, site_id)
);

COMMENT ON TABLE public.staff_scopes IS
  'Operational scopes mapping a Staff user to specific Department + Site combinations.';
COMMENT ON CONSTRAINT uq_staff_scope ON public.staff_scopes IS
  'Prevents duplicate Department + Site scope assignments for the same staff member.';

CREATE INDEX IF NOT EXISTS idx_staff_scopes_profile ON public.staff_scopes (staff_profile_id);
CREATE INDEX IF NOT EXISTS idx_staff_scopes_department ON public.staff_scopes (department_id);
CREATE INDEX IF NOT EXISTS idx_staff_scopes_site ON public.staff_scopes (site_id);

-- Enforce Staff-Only constraint for staff_scopes:
CREATE OR REPLACE FUNCTION public.enforce_staff_only_scope()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_staff_role_id UUID;
  v_profile_role_id UUID;
BEGIN
  SELECT id INTO v_staff_role_id FROM public.roles WHERE code = 'staff';
  SELECT role_id INTO v_profile_role_id FROM public.profiles WHERE id = NEW.staff_profile_id;

  IF v_profile_role_id IS NULL OR v_profile_role_id != v_staff_role_id THEN
    RAISE EXCEPTION 'ActionFlow Governance Policy: Only profiles assigned the Staff role may be granted staff_scopes. User has role %.', v_profile_role_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_staff_only_scope ON public.staff_scopes;
CREATE TRIGGER trg_enforce_staff_only_scope
  BEFORE INSERT OR UPDATE ON public.staff_scopes
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_staff_only_scope();

-- Row Level Security (RLS) on public.staff_scopes
ALTER TABLE public.staff_scopes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read staff scopes" ON public.staff_scopes;
CREATE POLICY "Allow read staff scopes"
  ON public.staff_scopes FOR SELECT
  TO authenticated
  USING (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = staff_scopes.staff_profile_id
        AND p.organization_id = public.get_my_organization_id()
    )
  );

DROP POLICY IF EXISTS "Admin manage staff scopes" ON public.staff_scopes;
CREATE POLICY "Admin manage staff scopes"
  ON public.staff_scopes FOR ALL
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (
      public.is_admin()
      AND EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = staff_scopes.staff_profile_id
          AND p.organization_id = public.get_my_organization_id()
      )
    )
  )
  WITH CHECK (
    public.is_platform_admin()
    OR (
      public.is_admin()
      AND EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = staff_scopes.staff_profile_id
          AND p.organization_id = public.get_my_organization_id()
      )
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.staff_scopes TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. Atomic Staff Scopes Synchronization Function: sync_staff_scopes
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sync_staff_scopes(
  p_staff_id UUID,
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
  v_staff_org_id UUID;
  v_staff_role VARCHAR(50);
  v_staff_name VARCHAR(150);
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
    RAISE EXCEPTION 'ActionFlow Security Violation: Only authenticated Company Administrators may configure staff scopes.';
  END IF;

  v_caller_org_id := public.get_my_organization_id();

  -- 2. Validate Staff Profile & Tenant Scoping
  SELECT p.organization_id, r.code, p.full_name
  INTO v_staff_org_id, v_staff_role, v_staff_name
  FROM public.profiles p
  JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = p_staff_id;

  IF v_staff_org_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Error: Staff profile % not found.', p_staff_id;
  END IF;

  IF v_staff_role != 'staff' THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Only users with the Staff role can have staff scopes (user has role "%").', v_staff_role;
  END IF;

  IF NOT v_is_plat_admin AND v_caller_id IS NOT NULL AND (v_staff_org_id IS DISTINCT FROM v_caller_org_id) THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Cannot modify staff scopes for another organization.';
  END IF;

  -- 3. Validate Scopes Payload
  IF p_scopes IS NULL OR jsonb_typeof(p_scopes) != 'array' THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Scopes payload must be a JSON array.';
  END IF;

  v_scope_count := jsonb_array_length(p_scopes);

  -- 4. Validate Each Scope (Tenant, Active Status, No Duplicates)
  IF v_scope_count > 0 THEN
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

      -- Check Department belongs to staff org and is active
      SELECT organization_id, is_active
      INTO v_dept_org_id, v_dept_active
      FROM public.departments
      WHERE id = v_dept_id;

      IF v_dept_org_id IS NULL OR (v_dept_org_id IS DISTINCT FROM v_staff_org_id) THEN
        RAISE EXCEPTION 'ActionFlow Security Violation: Department % does not belong to the staff organization.', v_dept_id;
      END IF;

      IF NOT v_dept_active THEN
        RAISE EXCEPTION 'ActionFlow Validation Error: Cannot assign inactive department % to staff scope.', v_dept_id;
      END IF;

      -- Check Site belongs to staff org and is active
      SELECT organization_id, is_active
      INTO v_site_org_id, v_site_active
      FROM public.sites
      WHERE id = v_site_id;

      IF v_site_org_id IS NULL OR (v_site_org_id IS DISTINCT FROM v_staff_org_id) THEN
        RAISE EXCEPTION 'ActionFlow Security Violation: Site % does not belong to the staff organization.', v_site_id;
      END IF;

      IF NOT v_site_active THEN
        RAISE EXCEPTION 'ActionFlow Validation Error: Cannot assign inactive site % to staff scope.', v_site_id;
      END IF;

      -- Save first scope as default primary for profiles table compatibility
      IF i = 0 THEN
        v_primary_dept_id := v_dept_id;
        v_primary_site_id := v_site_id;
      END IF;
    END LOOP;
  END IF;

  -- 5. Atomic Replace of Staff Scopes in Database
  DELETE FROM public.staff_scopes
  WHERE staff_profile_id = p_staff_id;

  IF v_scope_count > 0 THEN
    FOR i IN 0..(v_scope_count - 1) LOOP
      v_elem := p_scopes->i;
      v_dept_id := (v_elem->>'department_id')::UUID;
      v_site_id := (v_elem->>'site_id')::UUID;

      INSERT INTO public.staff_scopes (
        staff_profile_id,
        department_id,
        site_id
      ) VALUES (
        p_staff_id,
        v_dept_id,
        v_site_id
      );
    END LOOP;

    -- 6. Synchronize primary department & site on profile for compatibility
    UPDATE public.profiles
    SET
      department_id = v_primary_dept_id,
      site_id = v_primary_site_id,
      updated_at = now()
    WHERE id = p_staff_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'staff_id', p_staff_id,
    'scopes_count', v_scope_count
  );
END;
$$;

COMMENT ON FUNCTION public.sync_staff_scopes(UUID, JSONB) IS
  'Atomically replaces and validates multiple Department + Site scopes for a Staff user.';

REVOKE EXECUTE ON FUNCTION public.sync_staff_scopes(UUID, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_staff_scopes(UUID, JSONB) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. Extend Signup Scope Requests for Staff
-- ----------------------------------------------------------------------------

-- Allow account_request_scopes for both Manager and Staff requests
CREATE OR REPLACE FUNCTION public.enforce_account_request_scope_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_admin_role_id UUID;
  v_requested_role_id UUID;
BEGIN
  SELECT id INTO v_admin_role_id FROM public.roles WHERE code = 'admin';
  SELECT requested_role_id INTO v_requested_role_id FROM public.account_requests WHERE id = NEW.account_request_id;

  -- Strictly disallow Admin role in account_request_scopes
  IF v_requested_role_id = v_admin_role_id THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Admin requests cannot have account_request_scopes.';
  END IF;

  RETURN NEW;
END;
$$;

-- Update trigger function enforcing signup requested role rules
CREATE OR REPLACE FUNCTION public.enforce_valid_signup_requested_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_admin_role_id UUID;
  v_staff_role_id UUID;
  v_manager_role_id UUID;
  v_scope_count INT;
  v_auth_email VARCHAR(255);
BEGIN
  -- Always enforce that account_requests email matches authoritative auth.users email
  SELECT email INTO v_auth_email FROM auth.users WHERE id = NEW.auth_user_id;
  IF v_auth_email IS NOT NULL AND length(trim(v_auth_email)) > 0 THEN
    NEW.email := v_auth_email;
  END IF;

  -- Dynamically resolve role UUIDs
  SELECT id INTO v_admin_role_id FROM public.roles WHERE code = 'admin';
  SELECT id INTO v_staff_role_id FROM public.roles WHERE code = 'staff';
  SELECT id INTO v_manager_role_id FROM public.roles WHERE code = 'manager';

  -- Strictly forbid Admin role in signup account requests
  IF NEW.requested_role_id = v_admin_role_id THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Public signup requests are restricted to Manager and Staff roles. The Admin role cannot be requested.';
  END IF;

  -- Staff requests: must specify primary department and site (or derived from requested scopes)
  IF NEW.requested_role_id = v_staff_role_id THEN
    -- If no direct department/site, check if account_request_scopes has rows
    IF NEW.department_id IS NULL OR NEW.site_id IS NULL THEN
      SELECT COUNT(*) INTO v_scope_count
      FROM public.account_request_scopes
      WHERE account_request_id = NEW.id;

      IF v_scope_count = 0 AND NEW.status != 'pending_email_verification' THEN
        RAISE EXCEPTION 'ActionFlow Validation Error: Staff account requests must specify department and site scopes.';
      END IF;
    END IF;

    -- Staff optional team selection must belong to the applicant organization and be active
    IF NEW.team_id IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.teams
        WHERE id = NEW.team_id
          AND organization_id = NEW.organization_id
          AND is_active = true
      ) THEN
        RAISE EXCEPTION 'ActionFlow Validation Error: Selected team does not belong to the organization or is inactive.';
      END IF;
    END IF;
  END IF;

  -- Manager requests must define operational scopes via account_request_scopes, not team_id
  IF NEW.requested_role_id = v_manager_role_id THEN
    IF NEW.team_id IS NOT NULL THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Team selection is only applicable to Staff requests. Manager operational scopes must be defined via account_request_scopes.';
    END IF;

    -- Manager requests require at least one account_request_scopes row before approval
    IF NEW.status = 'approved' THEN
      SELECT COUNT(*) INTO v_scope_count
      FROM public.account_request_scopes
      WHERE account_request_id = NEW.id;

      IF v_scope_count = 0 THEN
        RAISE EXCEPTION 'ActionFlow Approval Error: Manager account requests must have at least one assigned department and site scope in account_request_scopes before approval.';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. Auth Lifecycle Trigger: handle_new_auth_user()
-- Allow Staff to provide scopes array on signup
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
  v_dept_id_raw TEXT;
  v_site_id_raw TEXT;
  v_team_id_raw TEXT;
  v_account_request_id UUID;
  v_scope_item JSONB;
  v_scope_count INT := 0;
  v_is_email_verified BOOLEAN := false;
  v_initial_status VARCHAR(50) := 'pending_email_verification';
  v_email_verified_at TIMESTAMPTZ := NULL;
  v_resolved_org_id UUID;
  v_has_scopes BOOLEAN := false;
BEGIN
  IF NEW.raw_user_meta_data IS NULL OR NEW.raw_user_meta_data = '{}'::jsonb THEN
    RETURN NEW;
  END IF;

  IF NEW.email IS NULL OR length(trim(NEW.email)) = 0 THEN
    RAISE EXCEPTION 'ActionFlow Signup Error: Authoritative email on auth.users is required.';
  END IF;

  IF NEW.email_confirmed_at IS NOT NULL THEN
    v_is_email_verified := true;
    v_initial_status := 'pending_admin_approval';
    v_email_verified_at := NEW.email_confirmed_at;
  END IF;

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

  v_has_scopes := (
    NEW.raw_user_meta_data ? 'scopes'
    AND jsonb_typeof(NEW.raw_user_meta_data -> 'scopes') = 'array'
    AND jsonb_array_length(NEW.raw_user_meta_data -> 'scopes') > 0
  );

  -- --------------------------------------------------------------------------
  -- Staff Signup Flow
  -- --------------------------------------------------------------------------
  IF v_requested_role = 'staff' THEN
    v_dept_id_raw := NEW.raw_user_meta_data ->> 'department_id';
    v_site_id_raw := NEW.raw_user_meta_data ->> 'site_id';
    v_team_id_raw := NEW.raw_user_meta_data ->> 'team_id';

    -- If scopes array was provided, derive primary from first scope if raw dept/site not given
    IF v_has_scopes THEN
      v_scope_item := (NEW.raw_user_meta_data -> 'scopes')->0;
      IF v_dept_id_raw IS NULL OR length(trim(v_dept_id_raw)) = 0 THEN
        v_dept_id_raw := v_scope_item ->> 'department_id';
      END IF;
      IF v_site_id_raw IS NULL OR length(trim(v_site_id_raw)) = 0 THEN
        v_site_id_raw := v_scope_item ->> 'site_id';
      END IF;
    END IF;

    IF v_dept_id_raw IS NULL OR length(trim(v_dept_id_raw)) = 0 THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Staff account requests must specify department_id or scopes.';
    END IF;

    IF v_site_id_raw IS NULL OR length(trim(v_site_id_raw)) = 0 THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Staff account requests must specify site_id or scopes.';
    END IF;

    v_dept_id := v_dept_id_raw::UUID;
    v_site_id := v_site_id_raw::UUID;

    -- Verify department exists and is active, resolve org
    SELECT organization_id INTO v_resolved_org_id
    FROM public.departments
    WHERE id = v_dept_id AND is_active = true;

    IF v_resolved_org_id IS NULL THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Selected department does not exist or is inactive.';
    END IF;

    -- Verify site exists, is active, and matches department organization
    IF NOT EXISTS (
      SELECT 1 FROM public.sites
      WHERE id = v_site_id
        AND organization_id = v_resolved_org_id
        AND is_active = true
    ) THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Selected site does not exist, is inactive, or belongs to another organization.';
    END IF;

    -- Optional team_id for Staff: must belong to the same organization and be active
    IF v_team_id_raw IS NOT NULL AND length(trim(v_team_id_raw)) > 0 THEN
      v_team_id := v_team_id_raw::UUID;
      IF NOT EXISTS (
        SELECT 1 FROM public.teams
        WHERE id = v_team_id
          AND organization_id = v_resolved_org_id
          AND is_active = true
      ) THEN
        RAISE EXCEPTION 'ActionFlow Signup Error: Selected team does not belong to your organization or is inactive.';
      END IF;
    ELSE
      v_team_id := NULL;
    END IF;

    -- Insert account_requests row for Staff
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
      v_resolved_org_id,
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
    ) RETURNING id INTO v_account_request_id;

    -- If scopes array was provided for Staff, insert each requested scope into account_request_scopes
    IF v_has_scopes THEN
      FOR v_scope_item IN SELECT * FROM jsonb_array_elements(NEW.raw_user_meta_data -> 'scopes')
      LOOP
        v_dept_id_raw := v_scope_item ->> 'department_id';
        v_site_id_raw := v_scope_item ->> 'site_id';

        IF v_dept_id_raw IS NOT NULL AND v_site_id_raw IS NOT NULL
           AND length(trim(v_dept_id_raw)) > 0 AND length(trim(v_site_id_raw)) > 0 THEN
          v_dept_id := v_dept_id_raw::UUID;
          v_site_id := v_site_id_raw::UUID;

          IF EXISTS (
            SELECT 1 FROM public.departments d
            JOIN public.sites s ON s.organization_id = d.organization_id
            WHERE d.id = v_dept_id AND d.is_active = true AND d.organization_id = v_resolved_org_id
              AND s.id = v_site_id AND s.is_active = true
          ) THEN
            INSERT INTO public.account_request_scopes (account_request_id, department_id, site_id)
            VALUES (v_account_request_id, v_dept_id, v_site_id)
            ON CONFLICT (account_request_id, department_id, site_id) DO NOTHING;
          END IF;
        END IF;
      END LOOP;
    END IF;

  -- --------------------------------------------------------------------------
  -- Manager Signup Flow
  -- --------------------------------------------------------------------------
  ELSIF v_requested_role = 'manager' THEN
    IF NEW.raw_user_meta_data ? 'team_id'
       AND NEW.raw_user_meta_data ->> 'team_id' IS NOT NULL
       AND length(trim(NEW.raw_user_meta_data ->> 'team_id')) > 0 THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Team selection is only applicable to Staff requests. Manager operational scopes must be defined via scopes array.';
    END IF;

    IF NOT v_has_scopes THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Manager requests must provide a non-empty scopes array containing Department + Site combinations.';
    END IF;

    -- Resolve organization from first scope department
    v_scope_item := (NEW.raw_user_meta_data -> 'scopes')->0;
    v_dept_id_raw := v_scope_item ->> 'department_id';
    IF v_dept_id_raw IS NULL OR length(trim(v_dept_id_raw)) = 0 THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: First scope department_id is missing.';
    END IF;

    SELECT organization_id INTO v_resolved_org_id
    FROM public.departments
    WHERE id = v_dept_id_raw::UUID AND is_active = true;

    IF v_resolved_org_id IS NULL THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Scope department does not exist or is inactive.';
    END IF;

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
      v_resolved_org_id,
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

      IF NOT EXISTS (SELECT 1 FROM public.departments WHERE id = v_dept_id AND organization_id = v_resolved_org_id AND is_active = true) THEN
        RAISE EXCEPTION 'ActionFlow Signup Error: Scope department (%) does not exist, is inactive, or belongs to another organization.', v_dept_id;
      END IF;

      IF NOT EXISTS (SELECT 1 FROM public.sites WHERE id = v_site_id AND organization_id = v_resolved_org_id AND is_active = true) THEN
        RAISE EXCEPTION 'ActionFlow Signup Error: Scope site (%) does not exist, is inactive, or belongs to another organization.', v_site_id;
      END IF;

      INSERT INTO public.account_request_scopes (account_request_id, department_id, site_id)
      VALUES (v_account_request_id, v_dept_id, v_site_id)
      ON CONFLICT (account_request_id, department_id, site_id) DO NOTHING;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. Account Approval Synchronization: handle_account_request_approval_sync()
-- Sync approved scopes for both Manager and Staff
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_account_request_approval_sync()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_manager_role_id UUID;
  v_staff_role_id UUID;
BEGIN
  SELECT id INTO v_manager_role_id FROM public.roles WHERE code = 'manager';
  SELECT id INTO v_staff_role_id FROM public.roles WHERE code = 'staff';

  IF NEW.status = 'approved' AND NEW.created_profile_id IS NOT NULL THEN
    -- If Manager request: copy to manager_scopes
    IF NEW.requested_role_id = v_manager_role_id THEN
      INSERT INTO public.manager_scopes (manager_profile_id, department_id, site_id)
      SELECT NEW.created_profile_id, ars.department_id, ars.site_id
      FROM public.account_request_scopes ars
      WHERE ars.account_request_id = NEW.id
      ON CONFLICT (manager_profile_id, department_id, site_id) DO NOTHING;

    -- If Staff request: copy to staff_scopes
    ELSIF NEW.requested_role_id = v_staff_role_id THEN
      INSERT INTO public.staff_scopes (staff_profile_id, department_id, site_id)
      SELECT NEW.created_profile_id, ars.department_id, ars.site_id
      FROM public.account_request_scopes ars
      WHERE ars.account_request_id = NEW.id
      ON CONFLICT (staff_profile_id, department_id, site_id) DO NOTHING;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. Atomic Account Approval RPC: approve_account_request
-- Support staff_scopes syncing and cross-department team assignment
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
  v_first_scope RECORD;
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

    -- If department/site not explicitly set, check first scope from account_request_scopes
    IF v_dept_id IS NULL OR v_site_id IS NULL THEN
      SELECT department_id, site_id INTO v_first_scope
      FROM public.account_request_scopes
      WHERE account_request_id = p_request_id
      LIMIT 1;

      IF v_first_scope.department_id IS NOT NULL THEN
        v_dept_id := COALESCE(v_dept_id, v_first_scope.department_id);
        v_site_id := COALESCE(v_site_id, v_first_scope.site_id);
      END IF;
    END IF;

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

    -- Verify team if supplied: MUST belong to caller's organization and be active (can cross departments)
    IF v_team_id IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.teams
        WHERE id = v_team_id
          AND organization_id = v_caller_org_id
          AND is_active = true
      ) THEN
        RAISE EXCEPTION 'ActionFlow Approval Error: Selected team does not belong to your organization or is inactive.';
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

    -- Copy account_request_scopes to staff_scopes if present
    INSERT INTO public.staff_scopes (staff_profile_id, department_id, site_id)
    SELECT v_req.auth_user_id, ars.department_id, ars.site_id
    FROM public.account_request_scopes ars
    WHERE ars.account_request_id = p_request_id
    ON CONFLICT (staff_profile_id, department_id, site_id) DO NOTHING;

    -- Also ensure primary scope is present in staff_scopes if staff_scopes was populated
    IF EXISTS (SELECT 1 FROM public.staff_scopes WHERE staff_profile_id = v_req.auth_user_id) THEN
      INSERT INTO public.staff_scopes (staff_profile_id, department_id, site_id)
      VALUES (v_req.auth_user_id, v_dept_id, v_site_id)
      ON CONFLICT (staff_profile_id, department_id, site_id) DO NOTHING;
    END IF;

    -- Upsert team membership if team was selected (cross-department within org allowed)
    IF v_team_id IS NOT NULL THEN
      INSERT INTO public.team_members (team_id, profile_id, role_in_team)
      VALUES (v_team_id, v_req.auth_user_id, 'member')
      ON CONFLICT (team_id, profile_id) DO NOTHING;
    END IF;

  ELSIF v_role_code = 'manager' THEN
    SELECT COUNT(*) INTO v_scope_count
    FROM public.account_request_scopes
    WHERE account_request_id = p_request_id;

    IF v_scope_count = 0 THEN
      RAISE EXCEPTION 'ActionFlow Approval Error: Manager request has no configured scopes in account_request_scopes.';
    END IF;

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
      department_id = NULL,
      site_id = NULL,
      role_id = EXCLUDED.role_id,
      status = 'active',
      is_active = true,
      updated_at = now();
  END IF;

  -- 7. Update Account Request status to 'approved' and record audit metadata
  UPDATE public.account_requests
  SET
    status = 'approved',
    created_profile_id = v_req.auth_user_id,
    reviewed_by = auth.uid(),
    reviewed_at = now(),
    updated_at = now()
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', p_request_id,
    'profile_id', v_req.auth_user_id,
    'role', v_role_code,
    'organization_id', v_caller_org_id
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 7. Fix Cross-Department Team Membership Triggers
-- ----------------------------------------------------------------------------

-- Replace restrictive enforce_team_department_consistency() with cross-department,
-- tenant-isolated, active-only verification
CREATE OR REPLACE FUNCTION public.enforce_team_department_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_team_org_id UUID;
  v_team_active BOOLEAN;
  v_profile_org_id UUID;
  v_profile_active BOOLEAN;
  v_profile_role VARCHAR(50);
BEGIN
  -- 1. Fetch team details
  SELECT organization_id, is_active
  INTO v_team_org_id, v_team_active
  FROM public.teams
  WHERE id = NEW.team_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ActionFlow Integrity Violation: Specified Team % does not exist.', NEW.team_id;
  END IF;

  IF NOT v_team_active THEN
    RAISE EXCEPTION 'ActionFlow Integrity Violation: Cannot assign members to an inactive Team.';
  END IF;

  -- 2. Fetch profile details
  SELECT p.organization_id, p.is_active, r.code
  INTO v_profile_org_id, v_profile_active, v_profile_role
  FROM public.profiles p
  JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = NEW.profile_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ActionFlow Integrity Violation: Specified Profile % does not exist.', NEW.profile_id;
  END IF;

  IF NOT v_profile_active THEN
    RAISE EXCEPTION 'ActionFlow Integrity Violation: Inactive users cannot be assigned to Teams.';
  END IF;

  -- 3. Strict Organization Isolation: User and Team must belong to the exact same organization
  IF v_team_org_id IS DISTINCT FROM v_profile_org_id THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Cross-organization team membership is forbidden. Profile org (%) does not match Team org (%).',
      v_profile_org_id, v_team_org_id;
  END IF;

  -- 4. Role eligibility: Managers, Staff, and Admins are eligible
  IF v_profile_role NOT IN ('manager', 'staff', 'admin', 'company_admin') THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Role "%" is not eligible for team membership.', v_profile_role;
  END IF;

  RETURN NEW;
END;
$$;

-- Relax enforce_profile_team_department_consistency() to allow changing primary department
-- without requiring dropping cross-department team memberships in the same organization
CREATE OR REPLACE FUNCTION public.enforce_profile_team_department_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Cross-department team membership within the same organization is permitted.
  -- Verify all teams the profile belongs to belong to the new organization if org changes.
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    IF EXISTS (
      SELECT 1 FROM public.team_members tm
      JOIN public.teams t ON tm.team_id = t.id
      WHERE tm.profile_id = NEW.id
        AND t.organization_id != NEW.organization_id
    ) THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Cannot change profile organization because profile has team memberships in another organization.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. Cascade Deletion in delete_company_user
-- ----------------------------------------------------------------------------

-- Add explicit cleanup for staff_scopes in delete_company_user
CREATE OR REPLACE FUNCTION public.delete_company_user(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_org_id UUID;
  v_target_org_id UUID;
  v_target_role VARCHAR(50);
  v_target_is_primary_admin BOOLEAN;
  v_target_name VARCHAR(150);
  v_is_platform_admin BOOLEAN;
BEGIN
  v_caller_id := auth.uid();
  v_is_platform_admin := public.is_platform_admin();

  IF v_caller_id IS NOT NULL AND NOT (public.is_admin() OR v_is_platform_admin) THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Only Company Administrators or Platform Admins may delete company users.';
  END IF;

  IF v_caller_id = p_user_id THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Administrators cannot delete their own account through user management. Use self-deletion flow.';
  END IF;

  SELECT p.organization_id, r.code, p.is_primary_admin, p.full_name
  INTO v_target_org_id, v_target_role, v_target_is_primary_admin, v_target_name
  FROM public.profiles p
  JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = p_user_id;

  IF v_target_org_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Error: User profile % not found.', p_user_id;
  END IF;

  IF v_target_is_primary_admin = true THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: The primary Company Administrator account cannot be deleted.';
  END IF;

  IF v_target_role IN ('admin', 'company_admin', 'platform_admin') AND NOT v_is_platform_admin THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Company Administrators cannot delete other Administrator accounts.';
  END IF;

  v_caller_org_id := public.get_my_organization_id();
  IF NOT v_is_platform_admin AND v_caller_id IS NOT NULL AND (v_target_org_id IS DISTINCT FROM v_caller_org_id) THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Cannot delete users from another organization.';
  END IF;

  -- Reverse-dependency cascade
  DELETE FROM public.team_members WHERE profile_id = p_user_id;
  DELETE FROM public.manager_scopes WHERE manager_profile_id = p_user_id;
  DELETE FROM public.staff_scopes WHERE staff_profile_id = p_user_id;
  DELETE FROM public.account_request_scopes
  WHERE account_request_id IN (
    SELECT id FROM public.account_requests WHERE auth_user_id = p_user_id
  );
  DELETE FROM public.account_requests WHERE auth_user_id = p_user_id;
  DELETE FROM public.profiles WHERE id = p_user_id;
  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'deleted_user_id', p_user_id,
    'deleted_user_name', v_target_name
  );
END;
$$;

COMMIT;

