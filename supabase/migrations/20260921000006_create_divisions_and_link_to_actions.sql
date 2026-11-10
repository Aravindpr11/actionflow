-- ============================================================================
-- ActionFlow Division Management & Action Link Migration
-- Migration: 20260921000006_create_divisions_and_link_to_actions.sql
-- ============================================================================
-- 1. Creates public.divisions table with tenant isolation (organization_id)
-- 2. Adds division_id foreign key on public.actions
-- 3. Enforces case-insensitive uniqueness of division names and codes per organization
-- 4. Multi-tier RLS policies covering SELECT, INSERT, UPDATE, DELETE
-- 5. Trigger validation ensuring active division selection for new actions
-- 6. Atomic safe deletion RPC (delete_division) checking action dependencies
-- 7. Seeds initial divisions for Sobha and backfills existing actions
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Table: public.divisions
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.divisions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name VARCHAR(150) NOT NULL,
  code VARCHAR(50) NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Unique indexes per organization (case-insensitive name & code)
CREATE UNIQUE INDEX IF NOT EXISTS idx_divisions_org_name_lower
  ON public.divisions(organization_id, lower(name));

CREATE UNIQUE INDEX IF NOT EXISTS idx_divisions_org_code_lower
  ON public.divisions(organization_id, lower(code));

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_divisions_org_active
  ON public.divisions(organization_id, is_active);

CREATE INDEX IF NOT EXISTS idx_divisions_created_at
  ON public.divisions(created_at DESC);

-- ----------------------------------------------------------------------------
-- 2. Link Table: public.actions -> division_id
-- ----------------------------------------------------------------------------
ALTER TABLE public.actions
  ADD COLUMN IF NOT EXISTS division_id UUID REFERENCES public.divisions(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_actions_division_id
  ON public.actions(division_id);

-- ----------------------------------------------------------------------------
-- 3. Enable RLS on public.divisions
-- ----------------------------------------------------------------------------
ALTER TABLE public.divisions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Platform admin full access on divisions" ON public.divisions;
DROP POLICY IF EXISTS "Authenticated users read own organization divisions" ON public.divisions;
DROP POLICY IF EXISTS "Company admins insert divisions" ON public.divisions;
DROP POLICY IF EXISTS "Company admins update divisions" ON public.divisions;
DROP POLICY IF EXISTS "Company admins delete divisions" ON public.divisions;

-- Platform Admin: unrestricted
CREATE POLICY "Platform admin full access on divisions"
  ON public.divisions FOR ALL
  TO authenticated
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

-- Authenticated Users: read own organization's divisions
CREATE POLICY "Authenticated users read own organization divisions"
  ON public.divisions FOR SELECT
  TO authenticated
  USING (
    public.is_platform_admin()
    OR organization_id = public.get_my_organization_id()
  );

-- Company Admin: insert divisions in own organization
CREATE POLICY "Company admins insert divisions"
  ON public.divisions FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  );

-- Company Admin: update divisions in own organization
CREATE POLICY "Company admins update divisions"
  ON public.divisions FOR UPDATE
  TO authenticated
  USING (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  )
  WITH CHECK (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  );

-- Company Admin: delete divisions in own organization
CREATE POLICY "Company admins delete divisions"
  ON public.divisions FOR DELETE
  TO authenticated
  USING (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  );

-- ----------------------------------------------------------------------------
-- 4. Trigger: Divisions Before Write (bind org & timestamp)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_divisions_before_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_platform_admin() THEN
    NEW.organization_id := public.get_my_organization_id();
    IF NEW.organization_id IS NULL THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: User is not linked to an active organization.';
    END IF;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_divisions_before_write ON public.divisions;
CREATE TRIGGER trg_divisions_before_write
  BEFORE INSERT OR UPDATE ON public.divisions
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_divisions_before_write();

-- ----------------------------------------------------------------------------
-- 5. Update Actions Server-Side Validation Trigger: enforce division tenant & active rule
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_action_before_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_org_id UUID;
  v_is_platform BOOLEAN := false;
  v_is_company_admin BOOLEAN := false;
  v_is_mgr BOOLEAN := false;
  v_dept_active BOOLEAN;
  v_dept_org UUID;
  v_site_active BOOLEAN;
  v_site_org UUID;
  v_sec_active BOOLEAN;
  v_sec_org UUID;
  v_div_active BOOLEAN;
  v_div_org UUID;
  v_team_active BOOLEAN;
  v_team_org UUID;
  v_team_dept UUID;
  v_assignee_org UUID;
  v_assignee_active BOOLEAN;
  v_assignee_status VARCHAR(50);
  v_assignee_dept UUID;
  v_assignee_site UUID;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NOT NULL THEN
    v_is_platform := public.is_platform_admin();
    v_is_company_admin := public.is_admin();
    v_is_mgr := public.is_manager();
    v_caller_org_id := public.get_my_organization_id();
  END IF;

  -- A. Enforce Organization Binding (when called in authenticated user context)
  IF v_caller_id IS NOT NULL AND NOT v_is_platform THEN
    IF v_caller_org_id IS NULL THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: User is not linked to an active organization.';
    END IF;
    -- Always force organization_id to caller's authoritative organization
    NEW.organization_id := v_caller_org_id;
  END IF;

  -- B. Auto-bind created_by on INSERT
  IF TG_OP = 'INSERT' THEN
    IF NEW.created_by IS NULL THEN
      NEW.created_by := v_caller_id;
    ELSIF NOT v_is_platform AND NEW.created_by != v_caller_id THEN
      -- Cannot create on behalf of someone else
      NEW.created_by := v_caller_id;
    END IF;
  END IF;

  -- C. Validate Department (must exist, belong to org, and be active)
  SELECT is_active, organization_id INTO v_dept_active, v_dept_org
  FROM public.departments WHERE id = NEW.department_id;
  IF v_dept_org IS NULL OR v_dept_org != NEW.organization_id THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Department does not belong to this organization.';
  END IF;
  IF v_dept_active IS NOT TRUE THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive department.';
  END IF;

  -- D. Validate Site (must exist, belong to org, and be active)
  SELECT is_active, organization_id INTO v_site_active, v_site_org
  FROM public.sites WHERE id = NEW.site_id;
  IF v_site_org IS NULL OR v_site_org != NEW.organization_id THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Site does not belong to this organization.';
  END IF;
  IF v_site_active IS NOT TRUE THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive site.';
  END IF;

  -- E. Validate Section (if specified: must belong to org; if new or changing, must be active)
  IF NEW.section_id IS NOT NULL THEN
    SELECT is_active, organization_id INTO v_sec_active, v_sec_org
    FROM public.action_sections WHERE id = NEW.section_id;

    IF v_sec_org IS NULL OR v_sec_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Section does not belong to this organization.';
    END IF;

    IF TG_OP = 'INSERT' THEN
      IF v_sec_active IS NOT TRUE THEN
        RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate new action with an inactive section.';
      END IF;
    ELSIF TG_OP = 'UPDATE' AND NEW.section_id IS DISTINCT FROM OLD.section_id THEN
      IF v_sec_active IS NOT TRUE THEN
        RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive section.';
      END IF;
    END IF;
  END IF;

  -- F. Validate Division (if specified: must belong to org; if new or changing, must be active)
  IF NEW.division_id IS NOT NULL THEN
    SELECT is_active, organization_id INTO v_div_active, v_div_org
    FROM public.divisions WHERE id = NEW.division_id;

    IF v_div_org IS NULL OR v_div_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Division does not belong to this organization.';
    END IF;

    IF TG_OP = 'INSERT' THEN
      IF v_div_active IS NOT TRUE THEN
        RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate new action with an inactive division.';
      END IF;
    ELSIF TG_OP = 'UPDATE' AND NEW.division_id IS DISTINCT FROM OLD.division_id THEN
      IF v_div_active IS NOT TRUE THEN
        RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive division.';
      END IF;
    END IF;
  END IF;

  -- G. Validate Team (if specified: must exist, belong to org, match department, and be active)
  IF NEW.team_id IS NOT NULL THEN
    SELECT is_active, organization_id, department_id
    INTO v_team_active, v_team_org, v_team_dept
    FROM public.teams WHERE id = NEW.team_id;

    IF v_team_org IS NULL OR v_team_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Team does not belong to this organization.';
    END IF;
    IF v_team_dept IS NULL OR v_team_dept != NEW.department_id THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Team does not belong to the selected department.';
    END IF;
    IF v_team_active IS NOT TRUE THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive team.';
    END IF;
  END IF;

  -- H. Manager Scope Authority Enforcement on Department + Site
  IF v_is_mgr AND NOT v_is_company_admin AND NOT v_is_platform THEN
    IF NOT public.is_manager_of_scope(NEW.department_id, NEW.site_id) THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: You do not have manager authority over this department and site scope.';
    END IF;
  END IF;

  -- I. Assignee Validation (if assigned_to is specified)
  -- ACTION SITE/LOCATION MUST NOT FILTER INTERNAL PERSON ASSIGNMENT
  IF NEW.assigned_to IS NOT NULL THEN
    SELECT organization_id, is_active, status, department_id, site_id
    INTO v_assignee_org, v_assignee_active, v_assignee_status, v_assignee_dept, v_assignee_site
    FROM public.profiles WHERE id = NEW.assigned_to;

    IF v_assignee_org IS NULL OR v_assignee_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Assigned user does not belong to this organization.';
    END IF;
    IF v_assignee_active IS NOT TRUE OR v_assignee_status != 'active' THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Assigned user is inactive or not approved.';
    END IF;

    -- If caller is a manager (not company admin, not platform admin):
    -- Assignee must be in-scope for this manager OR self-assigned OR in action department/site
    IF v_is_mgr AND NOT v_is_company_admin AND NOT v_is_platform THEN
      IF NEW.assigned_to != v_caller_id
         AND NOT public.is_manager_of_scope(v_assignee_dept, v_assignee_site)
         AND NOT (v_assignee_dept = NEW.department_id AND (v_assignee_site = NEW.site_id OR v_assignee_site IS NULL)) THEN
        RAISE EXCEPTION 'ActionFlow Security Violation: Assigned user is outside manager permitted scope.';
      END IF;
    END IF;
  END IF;

  -- J. Auto-maintain history log
  IF TG_OP = 'INSERT' THEN
    IF NEW.history IS NULL OR jsonb_array_length(NEW.history) = 0 THEN
      NEW.history := jsonb_build_array(
        jsonb_build_object(
          'action', 'Action Created',
          'actor_id', v_caller_id,
          'timestamp', now()
        )
      );
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.updated_at := now();
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      NEW.history := NEW.history || jsonb_build_object(
        'action', 'Status changed from ' || OLD.status || ' to ' || NEW.status,
        'actor_id', v_caller_id,
        'timestamp', now()
      );
    END IF;
    IF NEW.percent_complete IS DISTINCT FROM OLD.percent_complete THEN
      NEW.history := NEW.history || jsonb_build_object(
        'action', 'Progress updated to ' || NEW.percent_complete::text || '%',
        'actor_id', v_caller_id,
        'timestamp', now()
      );
    END IF;
  END IF;

  -- K. Due date / Created date bidirectional sync
  IF NEW.due_date IS NOT NULL AND (NEW.target_date IS NULL OR NEW.target_date IS DISTINCT FROM NEW.due_date) THEN
    NEW.target_date := NEW.due_date;
  ELSIF NEW.target_date IS NOT NULL AND NEW.due_date IS NULL THEN
    NEW.due_date := NEW.target_date;
  END IF;

  IF NEW.created_date IS NOT NULL AND (NEW.date_raised IS NULL OR NEW.date_raised IS DISTINCT FROM NEW.created_date) THEN
    NEW.date_raised := NEW.created_date;
  ELSIF NEW.date_raised IS NOT NULL AND NEW.created_date IS NULL THEN
    NEW.created_date := NEW.date_raised;
  END IF;

  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. Atomic Safe Deletion RPC for Divisions
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_division(p_division_id UUID)
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
  v_target_div RECORD;
  v_action_count INT := 0;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Authentication required.';
  END IF;

  v_is_platform := public.is_platform_admin();
  v_is_company_admin := public.is_admin();

  IF NOT v_is_platform AND NOT v_is_company_admin THEN
    RAISE EXCEPTION 'Unauthorized: Only Company Administrators or Platform Admins can delete divisions.';
  END IF;

  SELECT * INTO v_target_div FROM public.divisions WHERE id = p_division_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Division not found: %', p_division_id;
  END IF;

  IF NOT v_is_platform THEN
    v_caller_org_id := public.get_my_organization_id();
    IF v_caller_org_id IS NULL OR v_target_div.organization_id != v_caller_org_id THEN
      RAISE EXCEPTION 'Unauthorized: You can only delete divisions within your own organization.';
    END IF;
  END IF;

  -- Count dependent actions
  SELECT count(*) INTO v_action_count FROM public.actions WHERE division_id = p_division_id;

  IF v_action_count > 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'DEPENDENCIES_EXIST',
      'message', format('Cannot delete division "%s": %s action(s) are linked to it. Please deactivate this division instead.', v_target_div.name, v_action_count),
      'division_id', p_division_id,
      'division_name', v_target_div.name,
      'action_count', v_action_count
    );
  END IF;

  DELETE FROM public.divisions WHERE id = p_division_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', format('Division "%s" deleted successfully.', v_target_div.name),
    'division_id', p_division_id
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 7. Permissions Grants
-- ----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON public.divisions TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_division(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- 8. Seed Initial Divisions for Sobha & Backfill Existing Actions
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_sobha_id UUID := '00000000-0000-0000-0000-000000000001';
  v_ops_div_id UUID := '10000000-0000-0000-0000-000000000001';
  v_prj_div_id UUID := '10000000-0000-0000-0000-000000000002';
  v_corp_div_id UUID := '10000000-0000-0000-0000-000000000003';
BEGIN
  IF EXISTS (SELECT 1 FROM public.organizations WHERE id = v_sobha_id) THEN
    -- Insert standard divisions
    INSERT INTO public.divisions (id, organization_id, name, code, description, is_active)
    VALUES
      (v_ops_div_id, v_sobha_id, 'Operations', 'OPS', 'Operational execution and facilities management', true),
      (v_prj_div_id, v_sobha_id, 'Projects', 'PRJ', 'Capital projects, engineering, and infrastructure delivery', true),
      (v_corp_div_id, v_sobha_id, 'Corporate', 'CORP', 'Corporate governance, compliance, and enterprise strategy', true)
    ON CONFLICT (organization_id, lower(code)) DO NOTHING;

    -- Backfill existing Sobha actions without division_id to the Operations division
    UPDATE public.actions
    SET division_id = v_ops_div_id
    WHERE organization_id = v_sobha_id AND division_id IS NULL;
  END IF;
END;
$$;
