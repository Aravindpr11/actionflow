-- ============================================================================
-- ActionFlow Database Schema: Organizational & Authentication Foundation
-- Migration: 20260912000001_org_auth_foundation.sql
-- ============================================================================

-- Enable pgcrypto extension for UUID generation if not already active
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. Helper Functions & Triggers
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ============================================================================
-- 2. Table: roles
-- Fixed application roles: Admin, Manager, Staff.
-- Senior Staff and Junior Staff roles are explicitly prohibited.
-- ============================================================================

CREATE TABLE public.roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(50) UNIQUE NOT NULL,
  code VARCHAR(50) UNIQUE NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_exact_application_roles CHECK (name IN ('Admin', 'Manager', 'Staff')),
  CONSTRAINT chk_exact_application_role_codes CHECK (code IN ('admin', 'manager', 'staff'))
);

COMMENT ON TABLE public.roles IS 'Fixed application authorization roles: Admin, Manager, and Staff.';
COMMENT ON CONSTRAINT chk_exact_application_roles ON public.roles IS 'Restricts roles strictly to Admin, Manager, and Staff.';

-- Seed the exact three application roles
INSERT INTO public.roles (name, code, description) VALUES
  ('Admin', 'admin', 'System & Organization Administrator with full governance privileges.'),
  ('Manager', 'manager', 'Department & Operations Manager overseeing actions, teams, and approvals.'),
  ('Staff', 'staff', 'Action Owner & Field Assignee executing tasks and submitting progress updates.')
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- 3. Table: departments
-- Major business functions (e.g. HSE, Operations, Maintenance).
-- Admin controls departments.
-- ============================================================================

CREATE TABLE public.departments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(100) UNIQUE NOT NULL,
  code VARCHAR(50) UNIQUE,
  division VARCHAR(100) NOT NULL DEFAULT 'Operations & HSSE',
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.departments IS 'Major organizational business functions (e.g. HSE, Maintenance, Operations).';

CREATE TRIGGER trg_departments_updated_at
  BEFORE UPDATE ON public.departments
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_updated_at();

-- Seed standard departments
INSERT INTO public.departments (name, code, division) VALUES
  ('HSE / Safety', 'HSE', 'Operations & HSSE'),
  ('Operations', 'OPS', 'Operations & HSSE'),
  ('Maintenance', 'MAINT', 'Operations & Engineering'),
  ('Projects', 'PROJ', 'Engineering & Projects'),
  ('Quality Assurance', 'QA', 'Technical Services'),
  ('Logistics', 'LOG', 'Supply Chain'),
  ('Accounts', 'ACC', 'Corporate Services'),
  ('Human Resources', 'HR', 'Corporate Services')
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- 4. Table: sites
-- Physical work locations and facilities.
-- Admin controls sites.
-- ============================================================================

CREATE TABLE public.sites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(150) UNIQUE NOT NULL,
  code VARCHAR(50) UNIQUE,
  location_type VARCHAR(100) DEFAULT 'Onshore / Offshore Facility',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.sites IS 'Physical sites and operational facilities (e.g. Platform Alpha, North Rig).';

CREATE TRIGGER trg_sites_updated_at
  BEFORE UPDATE ON public.sites
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_updated_at();

-- Seed standard sites
INSERT INTO public.sites (name, code) VALUES
  ('Platform Alpha', 'PLT-A'),
  ('Platform Bravo', 'PLT-B'),
  ('North Plant', 'NP-01'),
  ('Central Yard', 'CY-MAIN'),
  ('Warehouse B', 'WH-B'),
  ('Offshore Rig #4', 'RIG-04'),
  ('Corporate Headquarters', 'HQ')
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- 5. Table: teams
-- Functional groups within a department.
-- Teams belong to a department, NOT to a site. Teams can span multiple sites.
-- Used for grouping/filtering people, NOT as a Manager management hierarchy.
-- ============================================================================

CREATE TABLE public.teams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
  name VARCHAR(100) NOT NULL,
  code VARCHAR(50),
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_team_department_name UNIQUE (department_id, name)
);

COMMENT ON TABLE public.teams IS 'Functional groups within a department. Not tied to a single site; used for grouping/filtering.';
COMMENT ON CONSTRAINT uq_team_department_name ON public.teams IS 'Prevents duplicate team names within the same department.';

CREATE INDEX idx_teams_department ON public.teams (department_id);

CREATE TRIGGER trg_teams_updated_at
  BEFORE UPDATE ON public.teams
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================================
-- 6. Table: profiles
-- User profiles mapped 1:1 to Supabase Auth (auth.users).
-- Staff normally has one primary Department and one current Site.
-- Supervisor concept is removed.
-- Enforces strictly at most ONE active designated Admin account at database level.
-- ============================================================================

CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name VARCHAR(150) NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  phone VARCHAR(50),
  designation VARCHAR(150) NOT NULL,
  department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
  site_id UUID REFERENCES public.sites(id) ON DELETE SET NULL,
  role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE RESTRICT,
  status VARCHAR(50) NOT NULL DEFAULT 'active',
  is_active BOOLEAN NOT NULL DEFAULT true,
  is_primary_admin BOOLEAN NOT NULL DEFAULT false,
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_profile_status CHECK (status IN ('active', 'inactive', 'pending_approval', 'suspended'))
);

COMMENT ON TABLE public.profiles IS 'Application user profile referencing Supabase Auth users. Primary department and current site for staff.';
COMMENT ON COLUMN public.profiles.is_primary_admin IS 'System-maintained flag ensuring exactly one active admin via database unique index.';

CREATE INDEX idx_profiles_email ON public.profiles (email);
CREATE INDEX idx_profiles_role ON public.profiles (role_id);
CREATE INDEX idx_profiles_department ON public.profiles (department_id);
CREATE INDEX idx_profiles_site ON public.profiles (site_id);
CREATE INDEX idx_profiles_status ON public.profiles (status);

-- Database-level uniqueness guarantee for exactly one active Admin account.
-- Operates at the B-Tree storage level, ensuring total concurrency safety.
-- Inactive admin records (is_active = false) do NOT block new active admin creation.
CREATE UNIQUE INDEX uq_profiles_single_active_admin
  ON public.profiles (is_primary_admin)
  WHERE is_primary_admin = true AND is_active = true;

CREATE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================================
-- 7. Governance & Integrity Triggers on profiles
-- - handle_profile_email_sync: guarantees public.profiles.email is derived from authoritative auth.users.email
-- - handle_admin_role_sync: guarantees is_primary_admin matches Admin role & single-admin policy
-- - enforce_profile_update_security: prevents non-admins from changing protected organizational fields
-- - enforce_profile_team_department_consistency: ensures changing profile department does not leave orphaned cross-dept team memberships
-- ============================================================================

-- Database-level assurance: public.profiles.email must ALWAYS be derived directly
-- from the authoritative auth.users record, never blindly trusted from client/signup metadata.
CREATE OR REPLACE FUNCTION public.handle_profile_email_sync()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_auth_email VARCHAR(255);
BEGIN
  -- Eventual public.profiles.email is derived directly from the authoritative auth.users email,
  -- never blindly trusted from client/signup metadata or caller input.
  SELECT email INTO v_auth_email
  FROM auth.users
  WHERE id = NEW.id;

  IF v_auth_email IS NULL OR length(trim(v_auth_email)) = 0 THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: No authoritative email found in auth.users for profile ID (%).', NEW.id;
  END IF;

  NEW.email := v_auth_email;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auth_email_sync_profiles
  BEFORE INSERT OR UPDATE OF email, id ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_profile_email_sync();

CREATE OR REPLACE FUNCTION public.handle_admin_role_sync()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_admin_role_id UUID;
  v_active_admin_count INT;
BEGIN
  -- Look up Admin role ID dynamically (no hardcoded UUIDs)
  SELECT id INTO v_admin_role_id FROM public.roles WHERE code = 'admin';

  IF NEW.role_id = v_admin_role_id THEN
    NEW.is_primary_admin = true;

    -- Validate that no other active Admin exists before committing
    IF NEW.is_active = true THEN
      SELECT COUNT(*) INTO v_active_admin_count
      FROM public.profiles
      WHERE is_primary_admin = true
        AND is_active = true
        AND id != NEW.id;

      IF v_active_admin_count >= 1 THEN
        RAISE EXCEPTION 'ActionFlow Governance Policy: Exactly one active designated Admin account is permitted.';
      END IF;
    END IF;
  ELSE
    -- Non-Admin role cannot have is_primary_admin = true
    NEW.is_primary_admin = false;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_and_enforce_admin
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_admin_role_sync();

-- Database-level protection for self-profile updates:
-- Non-admin users can ONLY modify full_name, phone, and avatar_url.
CREATE OR REPLACE FUNCTION public.enforce_profile_update_security()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Check if the current user is an Administrator
  IF NOT public.is_admin() THEN
    -- Block modifications to any protected organizational or security fields
    IF NEW.role_id IS DISTINCT FROM OLD.role_id OR
       NEW.department_id IS DISTINCT FROM OLD.department_id OR
       NEW.site_id IS DISTINCT FROM OLD.site_id OR
       NEW.designation IS DISTINCT FROM OLD.designation OR
       NEW.status IS DISTINCT FROM OLD.status OR
       NEW.is_active IS DISTINCT FROM OLD.is_active OR
       NEW.is_primary_admin IS DISTINCT FROM OLD.is_primary_admin OR
       NEW.email IS DISTINCT FROM OLD.email OR
       NEW.id IS DISTINCT FROM OLD.id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Non-admin users may only update personal details (full_name, phone, avatar_url). Organizational and role assignments require Administrator authorization.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enforce_profile_update_security
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_profile_update_security();

-- Validates that if a profile's primary department is updated, they do not have active team memberships in the previous department
CREATE OR REPLACE FUNCTION public.enforce_profile_team_department_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.department_id IS DISTINCT FROM OLD.department_id THEN
    IF EXISTS (
      SELECT 1 FROM public.team_members tm
      JOIN public.teams t ON tm.team_id = t.id
      WHERE tm.profile_id = NEW.id
        AND t.department_id != NEW.department_id
    ) THEN
      RAISE EXCEPTION 'ActionFlow Integrity Violation: Cannot change profile department because the profile belongs to teams in their current department. Reassign or remove team memberships first.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_profile_dept_change
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_profile_team_department_consistency();

-- ============================================================================
-- 8. Table: manager_scopes
-- Multi-scope assignment for Managers across Department + Site combinations.
-- A Manager may manage multiple Department + Site combinations.
-- Example:
--   Manager A -> HSE / Site A
--   Manager A -> HSE / Site B
--   Manager A -> Operations / Site C
-- Only profiles with the Manager role may be assigned to manager_scopes.
-- ============================================================================

CREATE TABLE public.manager_scopes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  manager_profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
  site_id UUID NOT NULL REFERENCES public.sites(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_manager_scope UNIQUE (manager_profile_id, department_id, site_id)
);

COMMENT ON TABLE public.manager_scopes IS 'Operational management scopes mapping a Manager to specific Department + Site combinations.';
COMMENT ON CONSTRAINT uq_manager_scope ON public.manager_scopes IS 'Prevents duplicate Department + Site scope assignments for the same manager.';

CREATE INDEX idx_manager_scopes_profile ON public.manager_scopes (manager_profile_id);
CREATE INDEX idx_manager_scopes_department ON public.manager_scopes (department_id);
CREATE INDEX idx_manager_scopes_site ON public.manager_scopes (site_id);

-- Enforce Manager-Only constraint for manager_scopes:
-- Staff or Admin profiles must NOT be allowed to be added to manager_scopes.
CREATE OR REPLACE FUNCTION public.enforce_manager_only_scope()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_manager_role_id UUID;
  v_profile_role_id UUID;
BEGIN
  -- Resolve Manager role UUID dynamically
  SELECT id INTO v_manager_role_id FROM public.roles WHERE code = 'manager';
  SELECT role_id INTO v_profile_role_id FROM public.profiles WHERE id = NEW.manager_profile_id;

  IF v_profile_role_id IS NULL OR v_profile_role_id != v_manager_role_id THEN
    RAISE EXCEPTION 'ActionFlow Governance Policy: Only profiles assigned the Manager role may be granted manager_scopes. Staff and Admin profiles are not permitted in manager_scopes.';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_manager_scope_role
  BEFORE INSERT OR UPDATE ON public.manager_scopes
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_manager_only_scope();

-- Manager Role Change Cleanup:
-- If an existing Manager profile is changed to Staff or Admin, automatically remove
-- all rows from public.manager_scopes for that profile.
-- A Staff/Admin profile must never retain manager scope rows.
CREATE OR REPLACE FUNCTION public.handle_profile_role_change_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_manager_role_id UUID;
BEGIN
  -- Lookup Manager role UUID dynamically
  SELECT id INTO v_manager_role_id FROM public.roles WHERE code = 'manager';

  -- If old role was Manager and new role is not Manager, purge all assigned manager_scopes
  IF OLD.role_id = v_manager_role_id AND NEW.role_id != v_manager_role_id THEN
    DELETE FROM public.manager_scopes WHERE manager_profile_id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cleanup_manager_scopes_on_role_change
  AFTER UPDATE OF role_id ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_profile_role_change_cleanup();

-- ============================================================================
-- 9. Table: team_members
-- Many-to-many relationship between profiles and teams.
-- A profile may belong to a team optionally.
-- Team/Department Consistency: A profile may only belong to a Team whose department
-- matches the profile's primary department_id.
-- ============================================================================

CREATE TABLE public.team_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role_in_team VARCHAR(50) NOT NULL DEFAULT 'member',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_team_member UNIQUE (team_id, profile_id),
  CONSTRAINT chk_team_role CHECK (role_in_team IN ('manager', 'member', 'lead', 'observer'))
);

COMMENT ON TABLE public.team_members IS 'Many-to-many association between profiles and teams.';
COMMENT ON CONSTRAINT uq_team_member ON public.team_members IS 'Ensures a profile cannot be duplicated within the same team.';

CREATE INDEX idx_team_members_team ON public.team_members (team_id);
CREATE INDEX idx_team_members_profile ON public.team_members (profile_id);

-- Enforce Team/Department consistency at database level:
-- HSE profile -> HSE team = allowed
-- HSE profile -> Operations team = rejected
CREATE OR REPLACE FUNCTION public.enforce_team_department_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_team_dept_id UUID;
  v_profile_dept_id UUID;
BEGIN
  SELECT department_id INTO v_team_dept_id FROM public.teams WHERE id = NEW.team_id;
  SELECT department_id INTO v_profile_dept_id FROM public.profiles WHERE id = NEW.profile_id;

  IF v_team_dept_id IS NOT NULL AND v_profile_dept_id IS NOT NULL THEN
    IF v_team_dept_id != v_profile_dept_id THEN
      RAISE EXCEPTION 'ActionFlow Integrity Violation: A profile may only belong to a Team whose department matches the profile primary department. Profile department (%) does not match Team department (%).',
        v_profile_dept_id, v_team_dept_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_team_department_consistency
  BEFORE INSERT OR UPDATE ON public.team_members
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_team_department_consistency();

-- ============================================================================
-- 10. Table: account_requests
-- Preserves signup submission details, workflow lifecycle, and audit trail.
-- Directly links to auth.users(id) via auth_user_id.
-- Prevents duplicate in-flight requests for the same auth account while allowing re-application after rejection.
-- Public signups are strictly restricted to Manager and Staff (Admin role forbidden).
-- Supervisor concept is removed.
-- ============================================================================

CREATE TABLE public.account_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name VARCHAR(150) NOT NULL,
  email VARCHAR(255) NOT NULL,
  phone VARCHAR(50),
  designation VARCHAR(150) NOT NULL,
  department_id UUID REFERENCES public.departments(id) ON DELETE RESTRICT,
  site_id UUID REFERENCES public.sites(id) ON DELETE RESTRICT,
  team_id UUID REFERENCES public.teams(id) ON DELETE SET NULL,
  requested_role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE RESTRICT,
  status VARCHAR(50) NOT NULL DEFAULT 'pending_email_verification',
  is_email_verified BOOLEAN NOT NULL DEFAULT false,
  email_verified_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  rejection_reason TEXT,
  created_profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_account_request_status CHECK (
    status IN (
      'pending_email_verification',
      'pending_admin_approval',
      'approved',
      'rejected'
    )
  ),
  CONSTRAINT chk_rejection_reason_required CHECK (
    status != 'rejected' OR (rejection_reason IS NOT NULL AND length(trim(rejection_reason)) > 0)
  )
);

COMMENT ON TABLE public.account_requests IS 'Signup account requests and administrative approval workflow tracking.';
COMMENT ON COLUMN public.account_requests.auth_user_id IS 'Direct foreign key link to auth.users created at initial signup.';
COMMENT ON COLUMN public.account_requests.requested_role_id IS 'Role requested by applicant at signup (restricted to Manager and Staff only).';
COMMENT ON COLUMN public.account_requests.department_id IS 'Primary department for Staff requests. Nullable for Manager requests which use account_request_scopes.';
COMMENT ON COLUMN public.account_requests.site_id IS 'Current site for Staff requests. Nullable for Manager requests which use account_request_scopes.';
COMMENT ON COLUMN public.account_requests.team_id IS 'Pre-validated team FK to disallow arbitrary/uncontrolled team names.';
COMMENT ON CONSTRAINT chk_rejection_reason_required ON public.account_requests IS 'Mandates an explanation reason whenever an account request is rejected.';

-- Partial unique index: prevents duplicate active / pending requests for the same user,
-- while cleanly permitting legitimate re-application after a rejection.
CREATE UNIQUE INDEX uq_account_requests_active_user
  ON public.account_requests (auth_user_id)
  WHERE status IN ('pending_email_verification', 'pending_admin_approval', 'approved');

CREATE INDEX idx_account_requests_auth_user ON public.account_requests (auth_user_id);
CREATE INDEX idx_account_requests_email ON public.account_requests (email);
CREATE INDEX idx_account_requests_status ON public.account_requests (status);
CREATE INDEX idx_account_requests_department ON public.account_requests (department_id);
CREATE INDEX idx_account_requests_created_at ON public.account_requests (created_at DESC);

CREATE TRIGGER trg_account_requests_updated_at
  BEFORE UPDATE ON public.account_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================================
-- 11. Table: account_request_scopes
-- Stores multiple Department + Site combinations requested during Manager signup.
-- Normal Staff requests use primary department_id and site_id on account_requests.
-- Manager requests use account_request_scopes to specify their operational scopes.
-- Example:
--   - HSE / Site A
--   - HSE / Site B
--   - Operations / Site C
-- ============================================================================

CREATE TABLE public.account_request_scopes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_request_id UUID NOT NULL REFERENCES public.account_requests(id) ON DELETE CASCADE,
  department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
  site_id UUID NOT NULL REFERENCES public.sites(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_account_request_scope UNIQUE (account_request_id, department_id, site_id)
);

COMMENT ON TABLE public.account_request_scopes IS 'Multiple Department + Site scopes submitted during Manager signup account requests.';
COMMENT ON CONSTRAINT uq_account_request_scope ON public.account_request_scopes IS 'Prevents duplicate Department + Site scope assignments within the same account request.';

CREATE INDEX idx_account_request_scopes_req ON public.account_request_scopes (account_request_id);
CREATE INDEX idx_account_request_scopes_dept ON public.account_request_scopes (department_id);
CREATE INDEX idx_account_request_scopes_site ON public.account_request_scopes (site_id);

-- Enforce that account_request_scopes is ONLY assigned to Manager requests.
-- Staff requests must not use account_request_scopes.
CREATE OR REPLACE FUNCTION public.enforce_account_request_scope_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_manager_role_id UUID;
  v_requested_role_id UUID;
BEGIN
  SELECT id INTO v_manager_role_id FROM public.roles WHERE code = 'manager';
  SELECT requested_role_id INTO v_requested_role_id FROM public.account_requests WHERE id = NEW.account_request_id;

  IF v_requested_role_id IS NULL OR v_requested_role_id != v_manager_role_id THEN
    RAISE EXCEPTION 'ActionFlow Integrity Error: account_request_scopes may only be assigned to Manager account requests. Staff requests use primary department and site on account_requests.';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_account_request_scope_role
  BEFORE INSERT OR UPDATE ON public.account_request_scopes
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_account_request_scope_role();

-- Trigger enforcing signup request rules:
-- 1. Admin role cannot be requested by public applicants.
-- 2. Staff requests must specify both primary department_id and site_id, and cannot have account_request_scopes.
-- 3. Manager requests require at least one account_request_scopes row before approval.
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

  -- Staff requests must provide primary department and site
  IF NEW.requested_role_id = v_staff_role_id THEN
    IF NEW.department_id IS NULL OR NEW.site_id IS NULL THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Staff account requests must specify both primary department_id and site_id.';
    END IF;

    -- Staff optional team selection must belong to the requested primary department
    IF NEW.team_id IS NOT NULL THEN
      IF (SELECT department_id FROM public.teams WHERE id = NEW.team_id) != NEW.department_id THEN
        RAISE EXCEPTION 'ActionFlow Validation Error: Selected team department does not match requested primary department.';
      END IF;
    END IF;

    -- Staff requests cannot have associated account_request_scopes
    IF TG_OP = 'UPDATE' THEN
      IF EXISTS (SELECT 1 FROM public.account_request_scopes WHERE account_request_id = NEW.id) THEN
        RAISE EXCEPTION 'ActionFlow Integrity Error: Staff requests cannot have associated account_request_scopes.';
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

CREATE TRIGGER trg_validate_requested_role
  BEFORE INSERT OR UPDATE ON public.account_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_valid_signup_requested_role();

-- Approval Flow Preparation:
-- Automatically converts approved Manager request scopes into public.manager_scopes
-- when the manager profile is created and linked via created_profile_id.
CREATE OR REPLACE FUNCTION public.handle_account_request_approval_sync()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_manager_role_id UUID;
BEGIN
  SELECT id INTO v_manager_role_id FROM public.roles WHERE code = 'manager';

  -- When request is approved and created_profile_id is assigned for a Manager request
  IF NEW.status = 'approved' AND NEW.created_profile_id IS NOT NULL AND NEW.requested_role_id = v_manager_role_id THEN
    -- Populate public.manager_scopes from account_request_scopes
    INSERT INTO public.manager_scopes (manager_profile_id, department_id, site_id)
    SELECT NEW.created_profile_id, ars.department_id, ars.site_id
    FROM public.account_request_scopes ars
    WHERE ars.account_request_id = NEW.id
    ON CONFLICT (manager_profile_id, department_id, site_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_approved_manager_scopes
  AFTER INSERT OR UPDATE OF status, created_profile_id ON public.account_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_account_request_approval_sync();

-- ============================================================================
-- 12. Supabase Auth Lifecycle Triggers (auth.users)
-- Handles pre-email-verification signup account request creation and
-- automated transition on email confirmation.
-- ============================================================================

-- Function 1: Captures initial signup details from auth.users metadata
-- Executes atomically within the signup transaction.
-- Guarantees direct auth.users linkage, validates metadata against database tables,
-- enforces Manager vs Staff rules, and sets status to pending_email_verification.
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
BEGIN
  -- If metadata is absent or empty (e.g. Supabase dashboard user creation / system seeds),
  -- bypass account request generation.
  IF NEW.raw_user_meta_data IS NULL OR NEW.raw_user_meta_data = '{}'::jsonb THEN
    RETURN NEW;
  END IF;

  -- Validate authoritative email from auth.users (never trust raw_user_meta_data for email)
  IF NEW.email IS NULL OR length(trim(NEW.email)) = 0 THEN
    RAISE EXCEPTION 'ActionFlow Signup Error: Authoritative email on auth.users is required.';
  END IF;

  -- If user is created with email already confirmed (e.g. developer environment / admin invite)
  IF NEW.email_confirmed_at IS NOT NULL THEN
    v_is_email_verified := true;
    v_initial_status := 'pending_admin_approval';
    v_email_verified_at := NEW.email_confirmed_at;
  END IF;

  -- 1. Extract and validate required basic profile metadata
  -- raw_user_meta_data is strictly limited to initial non-authoritative signup fields
  -- (full_name, phone, designation, requested_role, department_id, site_id, team_id, scopes).
  -- Email is strictly sourced from NEW.email (auth.users) and NEVER from raw_user_meta_data.
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

  -- 2. Validate requested role
  -- Normal public signup cannot request or create Admin.
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
    -- Staff requires primary department_id and site_id
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

    -- Verify department exists and is active
    IF NOT EXISTS (SELECT 1 FROM public.departments WHERE id = v_dept_id AND is_active = true) THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Selected department does not exist or is inactive.';
    END IF;

    -- Verify site exists and is active
    IF NOT EXISTS (SELECT 1 FROM public.sites WHERE id = v_site_id AND is_active = true) THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Selected site does not exist or is inactive.';
    END IF;

    -- Optional team_id for Staff only
    IF v_team_id_raw IS NOT NULL AND length(trim(v_team_id_raw)) > 0 THEN
      v_team_id := v_team_id_raw::UUID;
      -- Verify team exists, is active, and belongs to selected department
      IF NOT EXISTS (
        SELECT 1 FROM public.teams
        WHERE id = v_team_id
          AND department_id = v_dept_id
          AND is_active = true
      ) THEN
        RAISE EXCEPTION 'ActionFlow Signup Error: Selected team does not belong to the selected department or is inactive.';
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

    -- Create account_requests row for Staff
    -- email is strictly set from NEW.email (the authoritative Supabase Auth email), NOT raw_user_meta_data
    INSERT INTO public.account_requests (
      auth_user_id,
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

    -- Create account_requests row for Manager (department_id, site_id, team_id are NULL)
    -- email is strictly set from NEW.email (the authoritative Supabase Auth email), NOT raw_user_meta_data
    INSERT INTO public.account_requests (
      auth_user_id,
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

      -- Validate department exists and is active
      IF NOT EXISTS (SELECT 1 FROM public.departments WHERE id = v_dept_id AND is_active = true) THEN
        RAISE EXCEPTION 'ActionFlow Signup Error: Scope department (%) does not exist or is inactive.', v_dept_id;
      END IF;

      -- Validate site exists and is active
      IF NOT EXISTS (SELECT 1 FROM public.sites WHERE id = v_site_id AND is_active = true) THEN
        RAISE EXCEPTION 'ActionFlow Signup Error: Scope site (%) does not exist or is inactive.', v_site_id;
      END IF;

      -- Check for duplicate scope within this request
      IF EXISTS (
        SELECT 1 FROM public.account_request_scopes
        WHERE account_request_id = v_account_request_id
          AND department_id = v_dept_id
          AND site_id = v_site_id
      ) THEN
        RAISE EXCEPTION 'ActionFlow Signup Error: Duplicate scope detected in request (department: %, site: %).', v_dept_id, v_site_id;
      END IF;

      INSERT INTO public.account_request_scopes (
        account_request_id,
        department_id,
        site_id
      ) VALUES (
        v_account_request_id,
        v_dept_id,
        v_site_id
      );

      v_scope_count := v_scope_count + 1;
    END LOOP;

    IF v_scope_count = 0 THEN
      RAISE EXCEPTION 'ActionFlow Signup Error: Manager requests must provide at least one valid Department + Site scope.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user();

-- Function 2: Automatically updates account_requests status when email is verified
-- Listens for GoTrue updating email_confirmed_at.
-- Advances status from pending_email_verification to pending_admin_approval.
CREATE OR REPLACE FUNCTION public.handle_auth_user_email_verified()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- When email_confirmed_at transitions from NULL to verified timestamp
  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL THEN
    UPDATE public.account_requests
    SET
      is_email_verified = true,
      email_verified_at = NEW.email_confirmed_at,
      status = 'pending_admin_approval',
      updated_at = now()
    WHERE auth_user_id = NEW.id
      AND status = 'pending_email_verification';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_on_auth_user_email_verified
  AFTER UPDATE OF email_confirmed_at ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_auth_user_email_verified();

-- Function 3: Automatically propagates auth.users email updates to public.profiles and public.account_requests
-- Ensures auth.users remains the single authoritative source of truth for email across the lifecycle.
CREATE OR REPLACE FUNCTION public.handle_auth_user_email_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.email IS DISTINCT FROM NEW.email THEN
    -- Synchronize authoritative email to account_requests
    UPDATE public.account_requests
    SET email = NEW.email, updated_at = now()
    WHERE auth_user_id = NEW.id;

    -- Synchronize authoritative email to profiles
    UPDATE public.profiles
    SET email = NEW.email, updated_at = now()
    WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_on_auth_user_email_updated
  AFTER UPDATE OF email ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_auth_user_email_change();

-- ============================================================================
-- 13. Security Definer Authorization Helpers (Safe & Non-Recursive)
-- Uses fixed search_path = public, pg_temp to prevent hijacking.
-- Runs with definer privileges to bypass RLS during evaluation, eliminating recursion.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_is_admin BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    JOIN public.roles r ON p.role_id = r.id
    WHERE p.id = auth.uid()
      AND r.code = 'admin'
      AND p.is_active = true
  ) INTO v_is_admin;
  RETURN COALESCE(v_is_admin, false);
END;
$$;

CREATE OR REPLACE FUNCTION public.is_manager()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_is_manager BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    JOIN public.roles r ON p.role_id = r.id
    WHERE p.id = auth.uid()
      AND r.code = 'manager'
      AND p.is_active = true
  ) INTO v_is_manager;
  RETURN COALESCE(v_is_manager, false);
END;
$$;

CREATE OR REPLACE FUNCTION public.is_active_user()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_is_active BOOLEAN;
BEGIN
  SELECT is_active INTO v_is_active
  FROM public.profiles
  WHERE id = auth.uid();
  RETURN COALESCE(v_is_active, false);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_department_id()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_dept_id UUID;
BEGIN
  SELECT department_id INTO v_dept_id
  FROM public.profiles
  WHERE id = auth.uid();
  RETURN v_dept_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_manager_of_scope(p_dept_id UUID, p_site_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_dept_id IS NULL OR p_site_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM public.manager_scopes ms
    JOIN public.profiles p ON ms.manager_profile_id = p.id
    WHERE ms.manager_profile_id = auth.uid()
      AND ms.department_id = p_dept_id
      AND ms.site_id = p_site_id
      AND p.is_active = true
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- Security Hardening: Function Execution Privileges (Least Privilege)
-- Restricts execution of authorization helpers to authenticated users and service_role.
-- Revokes default PUBLIC/anon execution to prevent unauthenticated/anonymous RPC access.
-- ----------------------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.is_manager() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_manager() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.is_active_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_active_user() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.get_my_department_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_department_id() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.is_manager_of_scope(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_manager_of_scope(UUID, UUID) TO authenticated, service_role;

-- ============================================================================
-- 14. Row Level Security (RLS) Policies on Core Tables
-- Strict PII isolation and least-privilege enforcement.
-- ============================================================================

ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.manager_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_request_scopes ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- Table Privileges: Grant table SELECT to authenticated client
-- Row Level Security (RLS) policies defined below enforce row-level access control.
-- ----------------------------------------------------------------------------

GRANT SELECT ON public.profiles TO authenticated;
GRANT SELECT ON public.roles TO authenticated;
GRANT SELECT ON public.departments TO authenticated;
GRANT SELECT ON public.sites TO authenticated;

-- ----------------------------------------------------------------------------
-- Roles: Read-only access for authenticated and anonymous users
-- ----------------------------------------------------------------------------
CREATE POLICY "Allow read access to roles"
  ON public.roles FOR SELECT
  TO authenticated, anon
  USING (true);

-- ----------------------------------------------------------------------------
-- Departments & Sites: Public read for active, Admin full management
-- ----------------------------------------------------------------------------
CREATE POLICY "Public read active departments"
  ON public.departments FOR SELECT
  TO anon, authenticated
  USING (is_active = true);

CREATE POLICY "Admin read all departments"
  ON public.departments FOR SELECT
  TO authenticated
  USING (public.is_admin());

CREATE POLICY "Admin manage departments"
  ON public.departments FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "Public read active sites"
  ON public.sites FOR SELECT
  TO anon, authenticated
  USING (is_active = true);

CREATE POLICY "Admin read all sites"
  ON public.sites FOR SELECT
  TO authenticated
  USING (public.is_admin());

CREATE POLICY "Admin manage sites"
  ON public.sites FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ----------------------------------------------------------------------------
-- Teams: Active team read, Admin full management
-- ----------------------------------------------------------------------------
CREATE POLICY "Public read active teams"
  ON public.teams FOR SELECT
  TO anon, authenticated
  USING (is_active = true);

CREATE POLICY "Admin read all teams"
  ON public.teams FOR SELECT
  TO authenticated
  USING (public.is_admin());

CREATE POLICY "Admin manage teams"
  ON public.teams FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ----------------------------------------------------------------------------
-- Profiles: Strict PII protection
-- - Full profile access restricted to:
--   1. The user's own profile (auth.uid() = id)
--   2. Admin (full management)
--   3. Active Managers (restricted strictly to their assigned Department + Site scopes in manager_scopes)
-- - Staff users CANNOT read unrestricted full profile rows for other users.
-- - Broad/public read access is strictly denied.
-- ----------------------------------------------------------------------------
CREATE POLICY "User read own profile"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (id = auth.uid());

CREATE POLICY "Admin manage all profiles"
  ON public.profiles FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "User update own profile permitted fields"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

CREATE POLICY "Manager view active profiles within managed scopes"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (
    public.is_active_user()
    AND public.is_manager()
    AND is_active = true
    AND public.is_manager_of_scope(department_id, site_id)
  );

-- ----------------------------------------------------------------------------
-- Manager Scopes:
-- - Admin can manage all scopes
-- - Managers can read their own scopes
-- - Non-managers cannot create manager scopes
-- ----------------------------------------------------------------------------
CREATE POLICY "Admin manage all manager scopes"
  ON public.manager_scopes FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "Managers read own scopes"
  ON public.manager_scopes FOR SELECT
  TO authenticated
  USING (manager_profile_id = auth.uid() OR public.is_admin());

-- ----------------------------------------------------------------------------
-- Team Members: Active members read, Admin and Manager write
-- ----------------------------------------------------------------------------
CREATE POLICY "Allow read team members"
  ON public.team_members FOR SELECT
  TO authenticated
  USING (public.is_active_user());

CREATE POLICY "Admin and Manager manage team members"
  ON public.team_members FOR ALL
  TO authenticated
  USING (public.is_admin() OR public.is_manager())
  WITH CHECK (public.is_admin() OR public.is_manager());

-- ----------------------------------------------------------------------------
-- Account Requests:
-- - Applicant can read their own request via direct auth.uid() link once authenticated.
-- - Account request creation is performed by the trusted SECURITY DEFINER auth.users trigger.
-- - Direct client INSERT policies are disabled to prevent unauthenticated or spoofed creation.
-- - Admin can view, approve, or reject all account requests.
-- ----------------------------------------------------------------------------
CREATE POLICY "Applicant read own account request"
  ON public.account_requests FOR SELECT
  TO authenticated
  USING (auth_user_id = auth.uid() OR public.is_admin());

CREATE POLICY "Admin manage all account requests"
  ON public.account_requests FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ----------------------------------------------------------------------------
-- Account Request Scopes:
-- - Applicant can read scopes belonging to their own account_request once authenticated.
-- - Creation is performed by the trusted SECURITY DEFINER auth.users trigger.
-- - Direct client INSERT policies are disabled to prevent unauthenticated or spoofed creation.
-- - Admin can manage all.
-- - Other users cannot access them.
-- ----------------------------------------------------------------------------
CREATE POLICY "Applicant read own account request scopes"
  ON public.account_request_scopes FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.account_requests ar
      WHERE ar.id = account_request_id
        AND ar.auth_user_id = auth.uid()
    )
    OR public.is_admin()
  );

CREATE POLICY "Admin manage all account request scopes"
  ON public.account_request_scopes FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ============================================================================
-- 15. Sanitized Directory View for Operational Lookups
-- Exposes safe operational fields (full_name, designation, department, site, avatar)
-- without leaking sensitive PII (phone number, email address, internal security flags).
-- 
-- Mechanism Architecture:
-- - Uses security_barrier = true to prevent query optimizer from pushing
--   user-supplied filter functions down past the security WHERE clause.
-- - View runs with definer privileges to read non-PII fields from profiles,
--   while enforcing strict least-privilege scoping directly in the WHERE clause:
--   1. Admins see all active profiles across the organization.
--   2. Managers see active profiles strictly within their assigned Department + Site scopes.
--   3. Staff see ONLY active colleagues within their own assigned department.
--   4. Any active user can see their own directory record.
--   5. Inactive / unauthenticated requests return zero rows.
-- ============================================================================

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
    -- Admins have complete organizational visibility
    public.is_admin()
    -- Managers have visibility strictly restricted to active profiles in their exact Department + Site scopes
    OR (public.is_manager() AND public.is_manager_of_scope(p.department_id, p.site_id))
    -- Staff visibility is strictly restricted to colleagues in their assigned department
    OR (NOT public.is_manager() AND p.department_id IS NOT NULL AND p.department_id = public.get_my_department_id())
    -- Users can always see their own directory entry
    OR p.id = auth.uid()
  );

COMMENT ON VIEW public.directory_profiles IS 'Sanitized directory view with security barrier; exposes safe operational fields scoped by role and department without PII.';

GRANT SELECT ON public.directory_profiles TO authenticated;
