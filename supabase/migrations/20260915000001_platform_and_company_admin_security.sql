-- ============================================================================
-- ActionFlow Security Foundation: Platform Admin vs Company Admin Scoping
-- Migration: 20260915000001_platform_and_company_admin_security.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Table: platform_admins
-- Dedicated table identifying users with platform-level administration privileges.
-- Keeps the internal application roles (admin, manager, staff) unchanged.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.platform_admins (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.platform_admins IS 'ActionFlow Platform Administrators with cross-tenant platform governance privileges.';
COMMENT ON COLUMN public.platform_admins.user_id IS 'Direct reference to auth.users for designated Platform Administrators.';

CREATE INDEX IF NOT EXISTS idx_platform_admins_user ON public.platform_admins (user_id);

ALTER TABLE public.platform_admins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Platform admin read platform admins" ON public.platform_admins;
CREATE POLICY "Platform admin read platform admins"
  ON public.platform_admins FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.platform_admins pa WHERE pa.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Platform admin manage platform admins" ON public.platform_admins;
CREATE POLICY "Platform admin manage platform admins"
  ON public.platform_admins FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.platform_admins pa WHERE pa.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.platform_admins pa WHERE pa.user_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- 2. Security Definer Helper: is_platform_admin()
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.platform_admins pa
    WHERE pa.user_id = auth.uid()
  );
END;
$$;

COMMENT ON FUNCTION public.is_platform_admin() IS 'Returns true if the authenticated caller is a designated Platform Administrator.';

REVOKE EXECUTE ON FUNCTION public.is_platform_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. Security Definer Helper: is_company_admin()
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_company_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN public.is_admin()
    AND public.get_my_organization_id() IS NOT NULL
    AND NOT public.is_platform_admin();
END;
$$;

COMMENT ON FUNCTION public.is_company_admin() IS 'Returns true if the authenticated caller is an Administrator bound to an organization.';

REVOKE EXECUTE ON FUNCTION public.is_company_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_company_admin() TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4. Relax profiles.organization_id NOT NULL for Platform Admins with Trigger
-- ----------------------------------------------------------------------------
ALTER TABLE public.profiles
  ALTER COLUMN organization_id DROP NOT NULL;

-- Enforce that non-platform users MUST have a non-null organization_id
CREATE OR REPLACE FUNCTION public.enforce_profile_organization_requirement()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.organization_id IS NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.platform_admins pa WHERE pa.user_id = NEW.id
    ) THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Company users (Admins, Managers, Staff) must belong to an organization (organization_id is required).';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_profile_org_requirement ON public.profiles;
CREATE TRIGGER trg_enforce_profile_org_requirement
  BEFORE INSERT OR UPDATE OF organization_id ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_profile_organization_requirement();

-- Protect organization_id from unauthorized modification
CREATE OR REPLACE FUNCTION public.enforce_profile_update_security()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
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

  -- Company Admins cannot change a user''s organization_id (only Platform Admin may do so)
  IF NOT public.is_platform_admin() THEN
    IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Only Platform Administrators may reassign user organization.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. Cross-Organization Consistency Triggers (No Cross-Tenant Relationships)
-- ----------------------------------------------------------------------------

-- A. manager_scopes: manager profile ↔ department ↔ site
CREATE OR REPLACE FUNCTION public.enforce_manager_scope_org_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_mgr_org_id UUID;
  v_dept_org_id UUID;
  v_site_org_id UUID;
BEGIN
  SELECT organization_id INTO v_mgr_org_id FROM public.profiles WHERE id = NEW.manager_profile_id;
  SELECT organization_id INTO v_dept_org_id FROM public.departments WHERE id = NEW.department_id;
  SELECT organization_id INTO v_site_org_id FROM public.sites WHERE id = NEW.site_id;

  IF v_mgr_org_id IS NULL OR v_dept_org_id IS NULL OR v_site_org_id IS NULL OR
     v_mgr_org_id != v_dept_org_id OR v_mgr_org_id != v_site_org_id THEN
    RAISE EXCEPTION 'ActionFlow Integrity Violation: Manager scope department and site must belong to the manager''s organization.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_manager_scope_org_consistency ON public.manager_scopes;
CREATE TRIGGER trg_validate_manager_scope_org_consistency
  BEFORE INSERT OR UPDATE ON public.manager_scopes
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_manager_scope_org_consistency();

-- B. account_request_scopes: account request ↔ department ↔ site
CREATE OR REPLACE FUNCTION public.enforce_account_request_scope_org_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_req_org_id UUID;
  v_dept_org_id UUID;
  v_site_org_id UUID;
BEGIN
  SELECT organization_id INTO v_req_org_id FROM public.account_requests WHERE id = NEW.account_request_id;
  SELECT organization_id INTO v_dept_org_id FROM public.departments WHERE id = NEW.department_id;
  SELECT organization_id INTO v_site_org_id FROM public.sites WHERE id = NEW.site_id;

  IF v_req_org_id IS NULL OR v_dept_org_id IS NULL OR v_site_org_id IS NULL OR
     v_req_org_id != v_dept_org_id OR v_req_org_id != v_site_org_id THEN
    RAISE EXCEPTION 'ActionFlow Integrity Violation: Account request scope department and site must belong to the request''s organization.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_account_request_scope_org_consistency ON public.account_request_scopes;
CREATE TRIGGER trg_validate_account_request_scope_org_consistency
  BEFORE INSERT OR UPDATE ON public.account_request_scopes
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_account_request_scope_org_consistency();

-- C. account_requests: account request ↔ department / site / team
CREATE OR REPLACE FUNCTION public.enforce_account_request_org_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_dept_org_id UUID;
  v_site_org_id UUID;
  v_team_org_id UUID;
BEGIN
  IF NEW.organization_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Integrity Violation: Account requests must specify an organization_id.';
  END IF;

  IF NEW.department_id IS NOT NULL THEN
    SELECT organization_id INTO v_dept_org_id FROM public.departments WHERE id = NEW.department_id;
    IF v_dept_org_id IS DISTINCT FROM NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Integrity Violation: Requested department does not belong to the requested organization.';
    END IF;
  END IF;

  IF NEW.site_id IS NOT NULL THEN
    SELECT organization_id INTO v_site_org_id FROM public.sites WHERE id = NEW.site_id;
    IF v_site_org_id IS DISTINCT FROM NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Integrity Violation: Requested site does not belong to the requested organization.';
    END IF;
  END IF;

  IF NEW.team_id IS NOT NULL THEN
    SELECT organization_id INTO v_team_org_id FROM public.teams WHERE id = NEW.team_id;
    IF v_team_org_id IS DISTINCT FROM NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Integrity Violation: Requested team does not belong to the requested organization.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_account_request_org_consistency ON public.account_requests;
CREATE TRIGGER trg_validate_account_request_org_consistency
  BEFORE INSERT OR UPDATE OF organization_id, department_id, site_id, team_id ON public.account_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_account_request_org_consistency();

-- D. team_members: team ↔ profile
CREATE OR REPLACE FUNCTION public.enforce_team_member_org_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_team_org_id UUID;
  v_profile_org_id UUID;
BEGIN
  SELECT organization_id INTO v_team_org_id FROM public.teams WHERE id = NEW.team_id;
  SELECT organization_id INTO v_profile_org_id FROM public.profiles WHERE id = NEW.profile_id;

  IF v_team_org_id IS DISTINCT FROM v_profile_org_id THEN
    RAISE EXCEPTION 'ActionFlow Integrity Violation: Team member profile must belong to the same organization as the team.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_team_member_org_consistency ON public.team_members;
CREATE TRIGGER trg_validate_team_member_org_consistency
  BEFORE INSERT OR UPDATE ON public.team_members
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_team_member_org_consistency();

-- E. teams: team ↔ department
CREATE OR REPLACE FUNCTION public.enforce_team_dept_org_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_dept_org_id UUID;
BEGIN
  SELECT organization_id INTO v_dept_org_id FROM public.departments WHERE id = NEW.department_id;
  IF NEW.organization_id IS DISTINCT FROM v_dept_org_id THEN
    RAISE EXCEPTION 'ActionFlow Integrity Violation: Team organization must match its department organization.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_team_dept_org_consistency ON public.teams;
CREATE TRIGGER trg_validate_team_dept_org_consistency
  BEFORE INSERT OR UPDATE OF department_id, organization_id ON public.teams
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_team_dept_org_consistency();

-- ----------------------------------------------------------------------------
-- 6. Updated RLS Policies on Core Tables (Tenant Isolation)
-- ----------------------------------------------------------------------------

-- A. organizations
DROP POLICY IF EXISTS "Admin read all organizations" ON public.organizations;
CREATE POLICY "Platform and company admin read organizations"
  ON public.organizations FOR SELECT
  TO authenticated
  USING (
    public.is_platform_admin()
    OR id = public.get_my_organization_id()
  );

DROP POLICY IF EXISTS "Admin manage organizations" ON public.organizations;
CREATE POLICY "Platform admin manage organizations"
  ON public.organizations FOR ALL
  TO authenticated
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

-- B. departments
DROP POLICY IF EXISTS "Public read active departments" ON public.departments;
DROP POLICY IF EXISTS "Read active departments" ON public.departments;
CREATE POLICY "Read active departments"
  ON public.departments FOR SELECT
  TO anon, authenticated
  USING (
    is_active = true
    AND (
      auth.uid() IS NULL
      OR public.is_platform_admin()
      OR organization_id = public.get_my_organization_id()
    )
  );

DROP POLICY IF EXISTS "Admin read all departments" ON public.departments;
CREATE POLICY "Admin read all departments"
  ON public.departments FOR SELECT
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (public.is_admin() AND organization_id = public.get_my_organization_id())
  );

DROP POLICY IF EXISTS "Admin manage departments" ON public.departments;
CREATE POLICY "Admin manage departments"
  ON public.departments FOR ALL
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (public.is_admin() AND organization_id = public.get_my_organization_id())
  )
  WITH CHECK (
    public.is_platform_admin()
    OR (public.is_admin() AND organization_id = public.get_my_organization_id())
  );

-- C. sites
DROP POLICY IF EXISTS "Public read active sites" ON public.sites;
DROP POLICY IF EXISTS "Read active sites" ON public.sites;
CREATE POLICY "Read active sites"
  ON public.sites FOR SELECT
  TO anon, authenticated
  USING (
    is_active = true
    AND (
      auth.uid() IS NULL
      OR public.is_platform_admin()
      OR organization_id = public.get_my_organization_id()
    )
  );

DROP POLICY IF EXISTS "Admin read all sites" ON public.sites;
CREATE POLICY "Admin read all sites"
  ON public.sites FOR SELECT
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (public.is_admin() AND organization_id = public.get_my_organization_id())
  );

DROP POLICY IF EXISTS "Admin manage sites" ON public.sites;
CREATE POLICY "Admin manage sites"
  ON public.sites FOR ALL
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (public.is_admin() AND organization_id = public.get_my_organization_id())
  )
  WITH CHECK (
    public.is_platform_admin()
    OR (public.is_admin() AND organization_id = public.get_my_organization_id())
  );

-- D. teams
DROP POLICY IF EXISTS "Public read active teams" ON public.teams;
DROP POLICY IF EXISTS "Read active teams" ON public.teams;
CREATE POLICY "Read active teams"
  ON public.teams FOR SELECT
  TO anon, authenticated
  USING (
    is_active = true
    AND (
      auth.uid() IS NULL
      OR public.is_platform_admin()
      OR organization_id = public.get_my_organization_id()
    )
  );

DROP POLICY IF EXISTS "Admin read all teams" ON public.teams;
CREATE POLICY "Admin read all teams"
  ON public.teams FOR SELECT
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (public.is_admin() AND organization_id = public.get_my_organization_id())
  );

DROP POLICY IF EXISTS "Admin manage teams" ON public.teams;
CREATE POLICY "Admin manage teams"
  ON public.teams FOR ALL
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (public.is_admin() AND organization_id = public.get_my_organization_id())
  )
  WITH CHECK (
    public.is_platform_admin()
    OR (public.is_admin() AND organization_id = public.get_my_organization_id())
  );

-- E. profiles
DROP POLICY IF EXISTS "Admin manage all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Admin manage profiles" ON public.profiles;
CREATE POLICY "Admin manage profiles"
  ON public.profiles FOR ALL
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (public.is_admin() AND organization_id = public.get_my_organization_id())
  )
  WITH CHECK (
    public.is_platform_admin()
    OR (public.is_admin() AND organization_id = public.get_my_organization_id())
  );

DROP POLICY IF EXISTS "Manager view active profiles within managed scopes" ON public.profiles;
CREATE POLICY "Manager view active profiles within managed scopes"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (
    public.is_active_user()
    AND public.is_manager()
    AND is_active = true
    AND organization_id = public.get_my_organization_id()
    AND public.is_manager_of_scope(department_id, site_id)
  );

-- F. account_requests
DROP POLICY IF EXISTS "Applicant read own account request" ON public.account_requests;
DROP POLICY IF EXISTS "Applicant and admin read account request" ON public.account_requests;
CREATE POLICY "Applicant and admin read account request"
  ON public.account_requests FOR SELECT
  TO authenticated
  USING (
    auth_user_id = auth.uid()
    OR public.is_platform_admin()
    OR (public.is_admin() AND organization_id = public.get_my_organization_id())
  );

DROP POLICY IF EXISTS "Admin manage all account requests" ON public.account_requests;
DROP POLICY IF EXISTS "Admin manage account requests" ON public.account_requests;
CREATE POLICY "Admin manage account requests"
  ON public.account_requests FOR ALL
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (public.is_admin() AND organization_id = public.get_my_organization_id())
  )
  WITH CHECK (
    public.is_platform_admin()
    OR (public.is_admin() AND organization_id = public.get_my_organization_id())
  );

-- G. account_request_scopes
DROP POLICY IF EXISTS "Applicant read own account request scopes" ON public.account_request_scopes;
CREATE POLICY "Applicant read own account request scopes"
  ON public.account_request_scopes FOR SELECT
  TO authenticated
  USING (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1 FROM public.account_requests ar
      WHERE ar.id = account_request_id
        AND (
          ar.auth_user_id = auth.uid()
          OR (public.is_admin() AND ar.organization_id = public.get_my_organization_id())
        )
    )
  );

DROP POLICY IF EXISTS "Admin manage all account request scopes" ON public.account_request_scopes;
DROP POLICY IF EXISTS "Admin manage account request scopes" ON public.account_request_scopes;
CREATE POLICY "Admin manage account request scopes"
  ON public.account_request_scopes FOR ALL
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (
      public.is_admin()
      AND EXISTS (
        SELECT 1 FROM public.account_requests ar
        WHERE ar.id = account_request_id
          AND ar.organization_id = public.get_my_organization_id()
      )
    )
  )
  WITH CHECK (
    public.is_platform_admin()
    OR (
      public.is_admin()
      AND EXISTS (
        SELECT 1 FROM public.account_requests ar
        WHERE ar.id = account_request_id
          AND ar.organization_id = public.get_my_organization_id()
      )
    )
  );

-- H. manager_scopes
DROP POLICY IF EXISTS "Managers read own scopes" ON public.manager_scopes;
CREATE POLICY "Managers read own scopes"
  ON public.manager_scopes FOR SELECT
  TO authenticated
  USING (
    manager_profile_id = auth.uid()
    OR public.is_platform_admin()
    OR (
      public.is_admin()
      AND EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = manager_profile_id
          AND p.organization_id = public.get_my_organization_id()
      )
    )
  );

DROP POLICY IF EXISTS "Admin manage all manager scopes" ON public.manager_scopes;
DROP POLICY IF EXISTS "Admin manage manager scopes" ON public.manager_scopes;
CREATE POLICY "Admin manage manager scopes"
  ON public.manager_scopes FOR ALL
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (
      public.is_admin()
      AND EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = manager_profile_id
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
        WHERE p.id = manager_profile_id
          AND p.organization_id = public.get_my_organization_id()
      )
    )
  );

-- I. team_members
DROP POLICY IF EXISTS "Allow read team members" ON public.team_members;
CREATE POLICY "Allow read team members"
  ON public.team_members FOR SELECT
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (
      public.is_active_user()
      AND EXISTS (
        SELECT 1 FROM public.teams t
        WHERE t.id = team_id
          AND t.organization_id = public.get_my_organization_id()
      )
    )
  );

DROP POLICY IF EXISTS "Admin and Manager manage team members" ON public.team_members;
CREATE POLICY "Admin and Manager manage team members"
  ON public.team_members FOR ALL
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (
      (public.is_admin() OR public.is_manager())
      AND EXISTS (
        SELECT 1 FROM public.teams t
        WHERE t.id = team_id
          AND t.organization_id = public.get_my_organization_id()
      )
    )
  )
  WITH CHECK (
    public.is_platform_admin()
    OR (
      (public.is_admin() OR public.is_manager())
      AND EXISTS (
        SELECT 1 FROM public.teams t
        WHERE t.id = team_id
          AND t.organization_id = public.get_my_organization_id()
      )
    )
  );

-- J. directory_profiles View Update
CREATE OR REPLACE VIEW public.directory_profiles
WITH (security_barrier = true)
AS
SELECT
  p.id,
  p.full_name,
  p.designation,
  p.department_id,
  d.name AS department_name,
  p.site_id,
  s.name AS site_name,
  p.role_id,
  r.name AS role_name,
  p.avatar_url,
  p.is_active
FROM public.profiles p
JOIN public.roles r ON p.role_id = r.id
LEFT JOIN public.departments d ON p.department_id = d.id
LEFT JOIN public.sites s ON p.site_id = s.id
WHERE p.is_active = true
  AND public.is_active_user()
  AND (
    -- Platform Admin has complete visibility across all organizations
    public.is_platform_admin()
    -- Scoped to user's own organization
    OR (
      p.organization_id = public.get_my_organization_id()
      AND (
        -- Company Admin has visibility across their own organization
        public.is_admin()
        -- Managers have visibility strictly restricted to active profiles in their managed scopes
        OR (public.is_manager() AND public.is_manager_of_scope(p.department_id, p.site_id))
        -- Staff visibility is strictly restricted to colleagues in their assigned department
        OR (NOT public.is_manager() AND p.department_id IS NOT NULL AND p.department_id = public.get_my_department_id())
        -- Users can always see their own directory entry
        OR p.id = auth.uid()
      )
    )
  );

