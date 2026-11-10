-- ============================================================================
-- Migration: 20261109000002_staff_action_corrections_and_isolation.sql
-- Description: Staff Action Creation Repair, Manager Scopes Visibility & Action List Isolation
-- Environment: Local Docker Supabase first (do not modify Cloud Production)
-- ============================================================================

-- 1. Grant SELECT on public.manager_scopes to authenticated and add organization-scoped policy
-- This enables Staff users to view manager scopes so that Department Managers are discoverable.
GRANT SELECT ON public.manager_scopes TO authenticated;

DROP POLICY IF EXISTS "Allow read manager scopes in organization" ON public.manager_scopes;
CREATE POLICY "Allow read manager scopes in organization"
ON public.manager_scopes FOR SELECT
TO authenticated
USING (
  public.is_platform_admin()
  OR (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = manager_scopes.manager_profile_id
        AND p.organization_id = public.get_my_organization_id()
    )
  )
);

-- 2. Stored Function: public.get_department_managers(p_department_id uuid)
-- Dynamically returns active managers responsible for a specific department
-- either via primary profile department or via manager_scopes.
CREATE OR REPLACE FUNCTION public.get_department_managers(p_department_id uuid)
RETURNS TABLE (
  manager_id uuid,
  full_name text,
  email text,
  department_id uuid,
  role_code text
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT DISTINCT
    p.id AS manager_id,
    p.full_name::text,
    p.email::text,
    p_department_id AS department_id,
    COALESCE(r.code, 'manager')::text AS role_code
  FROM public.profiles p
  LEFT JOIN public.roles r ON p.role_id = r.id
  LEFT JOIN public.manager_scopes ms ON ms.manager_profile_id = p.id
  WHERE p.organization_id = public.get_my_organization_id()
    AND p.is_active = true
    AND LOWER(COALESCE(p.status, 'active')) = 'active'
    AND (
      LOWER(COALESCE(r.code, '')) = 'manager'
      OR LOWER(COALESCE(r.name, '')) = 'manager'
      OR LOWER(COALESCE(p.designation, '')) LIKE '%manager%'
    )
    AND NOT (
      LOWER(COALESCE(r.code, '')) = 'admin'
      OR LOWER(COALESCE(r.name, '')) LIKE '%admin%'
      OR p.is_primary_admin IS TRUE
    )
    AND (
      p.department_id = p_department_id
      OR ms.department_id = p_department_id
    );
$$;

REVOKE ALL ON FUNCTION public.get_department_managers(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_department_managers(uuid) TO authenticated, service_role;

-- 3. Update validate_action_before_write()
-- Fix caller profile resolution with LEFT JOIN, case-insensitive checks, and flexible staff_scopes site/dept lookup.
CREATE OR REPLACE FUNCTION public.validate_action_before_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_org_id UUID;
  v_is_platform BOOLEAN := false;
  v_is_company_admin BOOLEAN := false;
  v_is_mgr BOOLEAN := false;
  v_caller_is_active BOOLEAN;
  v_caller_status VARCHAR(50);
  v_caller_role_code VARCHAR(50);
  v_caller_dept UUID;
  v_caller_site UUID;
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
  v_assignee_role_code VARCHAR(50);
  v_assignee_role_name VARCHAR(100);
  v_assignee_is_primary_admin BOOLEAN;
BEGIN
  -- Caller context resolution
  v_caller_id := auth.uid();
  IF v_caller_id IS NOT NULL THEN
    v_is_platform := public.is_platform_admin();
    v_is_company_admin := public.is_admin();
    v_is_mgr := public.is_manager();
    v_caller_org_id := public.get_my_organization_id();

    SELECT p.is_active, p.status, p.department_id, p.site_id, r.code
    INTO v_caller_is_active, v_caller_status, v_caller_dept, v_caller_site, v_caller_role_code
    FROM public.profiles p
    LEFT JOIN public.roles r ON p.role_id = r.id
    WHERE p.id = v_caller_id;
  END IF;

  -- A. Enforce Organization Binding
  IF v_caller_id IS NOT NULL AND NOT v_is_platform THEN
    IF v_caller_org_id IS NULL THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: User is not linked to an active organization.';
    END IF;
    IF NEW.organization_id IS NOT NULL AND NEW.organization_id IS DISTINCT FROM v_caller_org_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Cannot create or move actions across organizations.';
    END IF;
    NEW.organization_id := v_caller_org_id;
  END IF;

  -- B. Auto-bind created_by on INSERT
  IF TG_OP = 'INSERT' THEN
    IF NEW.created_by IS NULL THEN
      NEW.created_by := v_caller_id;
    ELSIF NOT v_is_platform AND NEW.created_by != v_caller_id THEN
      NEW.created_by := v_caller_id;
    END IF;
  END IF;

  -- C. Derive & Validate scope_type
  IF NEW.scope_type IS NULL OR trim(NEW.scope_type) = '' THEN
    IF NEW.department_id IS NULL AND NEW.site_id IS NULL THEN
      NEW.scope_type := 'organization';
    ELSIF NEW.department_id IS NOT NULL AND NEW.site_id IS NULL THEN
      NEW.scope_type := 'department';
    ELSIF NEW.department_id IS NULL AND NEW.site_id IS NOT NULL THEN
      NEW.scope_type := 'site';
    ELSE
      NEW.scope_type := 'specific';
    END IF;
  END IF;

  -- D. Validate Department (if specified)
  IF NEW.department_id IS NOT NULL THEN
    SELECT is_active, organization_id INTO v_dept_active, v_dept_org
    FROM public.departments WHERE id = NEW.department_id;

    IF v_dept_org IS NULL OR v_dept_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Department does not belong to this organization.';
    END IF;

    IF TG_OP = 'INSERT' AND v_dept_active IS NOT TRUE THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Cannot create action for an inactive department.';
    ELSIF TG_OP = 'UPDATE' AND NEW.department_id IS DISTINCT FROM OLD.department_id THEN
      IF v_dept_active IS NOT TRUE THEN
        RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive department.';
      END IF;
    END IF;
  END IF;

  -- E. Validate Site (if specified)
  IF NEW.site_id IS NOT NULL THEN
    SELECT is_active, organization_id INTO v_site_active, v_site_org
    FROM public.sites WHERE id = NEW.site_id;

    IF v_site_org IS NULL OR v_site_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Site does not belong to this organization.';
    END IF;

    IF TG_OP = 'INSERT' AND v_site_active IS NOT TRUE THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Cannot create action for an inactive site.';
    ELSIF TG_OP = 'UPDATE' AND NEW.site_id IS DISTINCT FROM OLD.site_id THEN
      IF v_site_active IS NOT TRUE THEN
        RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive site.';
      END IF;
    END IF;
  END IF;

  -- F. Validate Section (if specified)
  IF NEW.section_id IS NOT NULL THEN
    SELECT is_active, organization_id INTO v_sec_active, v_sec_org
    FROM public.action_sections WHERE id = NEW.section_id;

    IF v_sec_org IS NULL OR v_sec_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Section does not belong to this organization.';
    END IF;

    IF TG_OP = 'INSERT' AND v_sec_active IS NOT TRUE THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Cannot create action for an inactive section.';
    ELSIF TG_OP = 'UPDATE' AND NEW.section_id IS DISTINCT FROM OLD.section_id THEN
      IF v_sec_active IS NOT TRUE THEN
        RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive section.';
      END IF;
    END IF;
  END IF;

  -- G. Validate Team (if specified)
  IF NEW.team_id IS NOT NULL THEN
    SELECT is_active, organization_id, department_id INTO v_team_active, v_team_org, v_team_dept
    FROM public.teams WHERE id = NEW.team_id;

    IF v_team_org IS NULL OR v_team_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Team does not belong to this organization.';
    END IF;
    IF v_team_active IS NOT TRUE THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive team.';
    END IF;
  END IF;

  -- H. Validate Division (if specified)
  IF NEW.division_id IS NOT NULL THEN
    SELECT is_active, organization_id INTO v_div_active, v_div_org
    FROM public.divisions WHERE id = NEW.division_id;

    IF v_div_org IS NULL OR v_div_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Division does not belong to this organization.';
    END IF;

    IF TG_OP = 'INSERT' AND v_div_active IS NOT TRUE THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Cannot create action for an inactive division.';
    ELSIF TG_OP = 'UPDATE' AND NEW.division_id IS DISTINCT FROM OLD.division_id THEN
      IF v_div_active IS NOT TRUE THEN
        RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive division.';
      END IF;
    END IF;
  END IF;

  -- I. Scope Authority Enforcement
  IF v_caller_id IS NOT NULL AND NOT v_is_platform AND NOT v_is_company_admin THEN
    IF NOT v_is_mgr THEN
      -- Staff caller restrictions
      IF TG_OP = 'INSERT' THEN
        IF v_caller_is_active IS NOT TRUE 
           OR LOWER(COALESCE(v_caller_status, '')) != 'active' 
           OR LOWER(COALESCE(v_caller_role_code, '')) NOT IN ('staff', 'worker', 'actionownerworker', 'action_owner_worker') THEN
          RAISE EXCEPTION 'ActionFlow Security Violation: Only active staff, managers, and administrators can create actions.';
        END IF;

        IF NEW.scope_type IS DISTINCT FROM 'specific' THEN
          RAISE EXCEPTION 'ActionFlow Security Violation: Staff can only create actions with specific scope.';
        END IF;

        IF NEW.department_id IS NULL OR (
          NEW.department_id IS DISTINCT FROM v_caller_dept
          AND NOT EXISTS (
            SELECT 1 FROM public.staff_scopes ss
            WHERE ss.staff_profile_id = v_caller_id
              AND ss.department_id = NEW.department_id
          )
        ) THEN
          RAISE EXCEPTION 'ActionFlow Security Violation: Staff can only create actions for their assigned department.';
        END IF;

        IF NEW.site_id IS NULL OR (
          NEW.site_id IS DISTINCT FROM v_caller_site
          AND NOT EXISTS (
            SELECT 1 FROM public.staff_scopes ss
            WHERE ss.staff_profile_id = v_caller_id
              AND ss.department_id = NEW.department_id
              AND ss.site_id = NEW.site_id
          )
        ) THEN
          RAISE EXCEPTION 'ActionFlow Security Violation: Staff can only create actions for their assigned site.';
        END IF;
      END IF;

      IF TG_OP = 'UPDATE' THEN
        -- Staff can only update actions assigned to them, created by them, or where they participate
        IF OLD.assigned_to != v_caller_id AND OLD.created_by != v_caller_id AND NOT app_private.is_action_participant(OLD.id) THEN
          RAISE EXCEPTION 'ActionFlow Security Violation: Staff can only update actions assigned to them, created by them, or where they participate.';
        END IF;

        -- Staff Closure Protection Guard
        IF NEW.status = 'Closed' AND OLD.status != 'Closed' THEN
          RAISE EXCEPTION 'ActionFlow Security Violation: Staff cannot directly close actions. Action closure requires an authorized Manager or Administrator.';
        END IF;

        IF NEW.closed_at IS DISTINCT FROM OLD.closed_at THEN
          RAISE EXCEPTION 'ActionFlow Security Violation: Staff cannot modify action closed_at.';
        END IF;

        IF NEW.closed_by IS DISTINCT FROM OLD.closed_by THEN
          RAISE EXCEPTION 'ActionFlow Security Violation: Staff cannot modify action closed_by.';
        END IF;
      END IF;
    ELSE
      -- Manager caller restrictions
      IF NEW.scope_type = 'specific' THEN
        IF NOT public.is_manager_of_scope(NEW.department_id, NEW.site_id) THEN
          RAISE EXCEPTION 'ActionFlow Security Violation: You do not have manager authority over this department and site scope.';
        END IF;
      ELSIF NEW.scope_type = 'department' THEN
        IF NOT public.is_manager_of_department_wide(NEW.department_id) THEN
          RAISE EXCEPTION 'ActionFlow Security Violation: Manager does not hold manager authority across all sites for department %.', NEW.department_id;
        END IF;
      ELSIF NEW.scope_type = 'site' THEN
        IF NOT public.is_manager_of_site_wide(NEW.site_id) THEN
          RAISE EXCEPTION 'ActionFlow Security Violation: Manager does not hold manager authority across all departments for site %.', NEW.site_id;
        END IF;
      ELSIF NEW.scope_type = 'organization' THEN
        IF NOT EXISTS (
          SELECT 1 FROM public.profiles p
          LEFT JOIN public.roles r ON p.role_id = r.id
          WHERE p.id = v_caller_id
            AND p.organization_id = NEW.organization_id
            AND p.is_active = true
            AND LOWER(COALESCE(r.code, '')) IN ('manager', 'admin')
        ) THEN
          RAISE EXCEPTION 'ActionFlow Security Violation: Only active managers can create organization-wide actions.';
        END IF;
      ELSE
        RAISE EXCEPTION 'ActionFlow Security Violation: Invalid action scope type.';
      END IF;
    END IF;
  END IF;

  -- J. Assignee Validation (if assigned_to is specified)
  IF NEW.assigned_to IS NOT NULL THEN
    SELECT p.organization_id, p.is_active, p.status, p.department_id, p.site_id,
           r.code, r.name, p.is_primary_admin
    INTO v_assignee_org, v_assignee_active, v_assignee_status, v_assignee_dept, v_assignee_site,
         v_assignee_role_code, v_assignee_role_name, v_assignee_is_primary_admin
    FROM public.profiles p
    LEFT JOIN public.roles r ON p.role_id = r.id
    WHERE p.id = NEW.assigned_to;

    IF v_assignee_org IS NULL OR v_assignee_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Assigned user does not belong to this organization.';
    END IF;
    IF v_assignee_active IS NOT TRUE OR LOWER(COALESCE(v_assignee_status, '')) != 'active' THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Assigned user is inactive or not approved.';
    END IF;

    -- Operational Assignee Role Exclusion: Admin-role users cannot be assignees
    IF LOWER(COALESCE(v_assignee_role_code, '')) = 'admin' 
       OR LOWER(COALESCE(v_assignee_role_name, '')) LIKE '%admin%' 
       OR v_assignee_is_primary_admin IS TRUE THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Admin-role users are excluded from operational assignees.';
    END IF;

    -- Caller staff restrictions:
    IF NOT v_is_mgr AND NOT v_is_company_admin AND NOT v_is_platform THEN
      IF NEW.assigned_to != v_caller_id THEN
        -- Permitted assignees: active Staff in creator's department OR active Manager in creator's department
        IF NOT (
          (LOWER(COALESCE(v_assignee_role_code, '')) IN ('staff', 'worker', 'actionownerworker', 'action_owner_worker') AND v_assignee_dept = NEW.department_id)
          OR (LOWER(COALESCE(v_assignee_role_code, '')) = 'manager' AND (
            v_assignee_dept = NEW.department_id
            OR EXISTS (
              SELECT 1 FROM public.manager_scopes ms
              WHERE ms.manager_profile_id = NEW.assigned_to
                AND ms.department_id = NEW.department_id
            )
          ))
        ) THEN
          RAISE EXCEPTION 'ActionFlow Security Violation: Staff can only assign actions to themselves, or active staff or managers in their department.';
        END IF;
      END IF;
    END IF;

    -- Caller manager restrictions:
    IF v_is_mgr AND NOT v_is_company_admin AND NOT v_is_platform THEN
      IF NEW.assigned_to != v_caller_id THEN
        IF NEW.scope_type = 'organization' THEN
          NULL;
        ELSIF NEW.scope_type = 'department' THEN
          IF v_assignee_dept IS NULL OR v_assignee_dept != NEW.department_id THEN
            RAISE EXCEPTION 'ActionFlow Security Violation: Assigned user must belong to department %.', NEW.department_id;
          END IF;
        ELSIF NEW.scope_type = 'site' THEN
          IF v_assignee_site IS NULL OR v_assignee_site != NEW.site_id THEN
            RAISE EXCEPTION 'ActionFlow Security Violation: Assigned user must belong to site %.', NEW.site_id;
          END IF;
        ELSIF NEW.scope_type = 'specific' THEN
          IF v_assignee_dept IS NULL OR v_assignee_site IS NULL OR
             v_assignee_dept != NEW.department_id OR v_assignee_site != NEW.site_id THEN
            RAISE EXCEPTION 'ActionFlow Security Violation: Assigned user must belong to the action department and site scope.';
          END IF;
        END IF;
      END IF;
    END IF;
  END IF;

  -- K. Auto-maintain history log
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
    IF NEW.history IS NULL THEN
      NEW.history := COALESCE(OLD.history, '[]'::jsonb);
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      NEW.history := NEW.history || jsonb_build_object(
        'action', 'Status changed from ' || COALESCE(OLD.status, 'None') || ' to ' || COALESCE(NEW.status, 'None'),
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

  -- L. Due date / Created date bidirectional sync
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

-- 4. Recreate RLS Policy "Staff insert actions"
DROP POLICY IF EXISTS "Staff insert actions" ON public.actions;
CREATE POLICY "Staff insert actions"
ON public.actions FOR INSERT
TO authenticated
WITH CHECK (
  public.is_active_user()
  AND organization_id = public.get_my_organization_id()
  AND created_by = auth.uid()
  AND scope_type = 'specific'
  AND (
    department_id = (SELECT department_id FROM public.profiles WHERE id = auth.uid() AND is_active = true AND status = 'active')
    OR EXISTS (
      SELECT 1 FROM public.staff_scopes ss
      WHERE ss.staff_profile_id = auth.uid()
        AND ss.department_id = actions.department_id
    )
  )
  AND (
    site_id = (SELECT site_id FROM public.profiles WHERE id = auth.uid() AND is_active = true AND status = 'active')
    OR EXISTS (
      SELECT 1 FROM public.staff_scopes ss
      WHERE ss.staff_profile_id = auth.uid()
        AND ss.department_id = actions.department_id
        AND ss.site_id = actions.site_id
    )
  )
);
