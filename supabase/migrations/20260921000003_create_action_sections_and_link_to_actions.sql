-- ============================================================================
-- ActionFlow Action Sections & Action Link Migration
-- Migration: 20260921000003_create_action_sections_and_link_to_actions.sql
-- ============================================================================
-- 1. Creates public.action_sections table with tenant isolation (organization_id)
-- 2. Adds section_id foreign key on public.actions
-- 3. Enforces case-insensitive uniqueness of section names per organization
-- 4. Multi-tier RLS policies covering SELECT, INSERT, UPDATE, DELETE
-- 5. Trigger validation ensuring active section selection for new actions
-- 6. Atomic safe deletion RPC (delete_action_section) checking action dependencies
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Table: public.action_sections
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.action_sections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name VARCHAR(150) NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Unique index per organization (case-insensitive name)
CREATE UNIQUE INDEX IF NOT EXISTS idx_action_sections_org_name_lower
  ON public.action_sections(organization_id, lower(name));

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_action_sections_org_active
  ON public.action_sections(organization_id, is_active);

CREATE INDEX IF NOT EXISTS idx_action_sections_created_at
  ON public.action_sections(created_at DESC);

-- ----------------------------------------------------------------------------
-- 2. Link Table: public.actions -> section_id
-- ----------------------------------------------------------------------------
ALTER TABLE public.actions
  ADD COLUMN IF NOT EXISTS section_id UUID REFERENCES public.action_sections(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_actions_section_id
  ON public.actions(section_id);

-- ----------------------------------------------------------------------------
-- 3. Enable RLS on public.action_sections
-- ----------------------------------------------------------------------------
ALTER TABLE public.action_sections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Platform admin full access on action_sections" ON public.action_sections;
DROP POLICY IF EXISTS "Authenticated users read own organization action_sections" ON public.action_sections;
DROP POLICY IF EXISTS "Company admins insert action_sections" ON public.action_sections;
DROP POLICY IF EXISTS "Company admins update action_sections" ON public.action_sections;
DROP POLICY IF EXISTS "Company admins delete action_sections" ON public.action_sections;

-- Platform Admin: unrestricted
CREATE POLICY "Platform admin full access on action_sections"
  ON public.action_sections FOR ALL
  TO authenticated
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

-- Authenticated Users: read own organization's sections
CREATE POLICY "Authenticated users read own organization action_sections"
  ON public.action_sections FOR SELECT
  TO authenticated
  USING (
    public.is_platform_admin()
    OR organization_id = public.get_my_organization_id()
  );

-- Company Admin: insert sections in own organization
CREATE POLICY "Company admins insert action_sections"
  ON public.action_sections FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  );

-- Company Admin: update sections in own organization
CREATE POLICY "Company admins update action_sections"
  ON public.action_sections FOR UPDATE
  TO authenticated
  USING (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  )
  WITH CHECK (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  );

-- Company Admin: delete sections in own organization
CREATE POLICY "Company admins delete action_sections"
  ON public.action_sections FOR DELETE
  TO authenticated
  USING (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  );

-- ----------------------------------------------------------------------------
-- 4. Trigger: Action Sections Before Write (bind org & timestamp)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_action_sections_before_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN
    NEW.organization_id := public.get_my_organization_id();
    IF NEW.organization_id IS NULL THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: User is not linked to an active organization.';
    END IF;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_action_sections_before_write ON public.action_sections;
CREATE TRIGGER trg_action_sections_before_write
  BEFORE INSERT OR UPDATE ON public.action_sections
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_action_sections_before_write();

-- ----------------------------------------------------------------------------
-- 5. Update Actions Validation Trigger: enforce section tenant & active rule
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
  v_assignee_org UUID;
  v_assignee_active BOOLEAN;
  v_assignee_status VARCHAR(50);
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NOT NULL THEN
    v_is_platform := public.is_platform_admin();
    v_is_company_admin := public.is_admin();
    v_is_mgr := public.is_manager();
    v_caller_org_id := public.get_my_organization_id();
  END IF;

  -- A. Enforce Organization Binding
  IF NOT v_is_platform THEN
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

  -- F. Manager Scope Enforcement
  IF v_is_mgr AND NOT v_is_company_admin AND NOT v_is_platform THEN
    IF NOT public.is_manager_of_scope(NEW.department_id, NEW.site_id) THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: You do not have manager authority over this department and site scope.';
    END IF;
  END IF;

  -- G. Assignee Validation (if assigned_to is specified)
  IF NEW.assigned_to IS NOT NULL THEN
    SELECT organization_id, is_active, status
    INTO v_assignee_org, v_assignee_active, v_assignee_status
    FROM public.profiles WHERE id = NEW.assigned_to;

    IF v_assignee_org IS NULL OR v_assignee_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Assigned user does not belong to this organization.';
    END IF;
    IF v_assignee_active IS NOT TRUE OR v_assignee_status != 'active' THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Assigned user is inactive or not approved.';
    END IF;
  END IF;

  -- H. Auto-maintain history log
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

  -- I. Due date / Created date bidirectional sync
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
-- 6. Atomic Safe Deletion RPC for Action Sections
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_action_section(p_section_id UUID)
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
  v_target_sec RECORD;
  v_action_count INT := 0;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Authentication required.';
  END IF;

  v_is_platform := public.is_platform_admin();
  v_is_company_admin := public.is_admin();

  IF NOT v_is_platform AND NOT v_is_company_admin THEN
    RAISE EXCEPTION 'Unauthorized: Only Company Administrators or Platform Admins can delete action sections.';
  END IF;

  SELECT * INTO v_target_sec FROM public.action_sections WHERE id = p_section_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Action section not found: %', p_section_id;
  END IF;

  IF NOT v_is_platform THEN
    v_caller_org_id := public.get_my_organization_id();
    IF v_caller_org_id IS NULL OR v_target_sec.organization_id != v_caller_org_id THEN
      RAISE EXCEPTION 'Unauthorized: You can only delete action sections within your own organization.';
    END IF;
  END IF;

  -- Count dependent actions
  SELECT count(*) INTO v_action_count FROM public.actions WHERE section_id = p_section_id;

  IF v_action_count > 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'DEPENDENCIES_EXIST',
      'message', format('Cannot delete section "%s": %s action(s) are linked to it. Please deactivate this section instead.', v_target_sec.name, v_action_count),
      'section_id', p_section_id,
      'section_name', v_target_sec.name,
      'action_count', v_action_count
    );
  END IF;

  DELETE FROM public.action_sections WHERE id = p_section_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', format('Section "%s" deleted successfully.', v_target_sec.name),
    'section_id', p_section_id
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 7. Permissions Grants
-- ----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON public.action_sections TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_action_section(UUID) TO authenticated;

