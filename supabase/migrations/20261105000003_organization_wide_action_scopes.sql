-- ============================================================================
-- Migration: 20261105000003_organization_wide_action_scopes.sql
-- Description: Implement and harden Organization-Wide, Department-Wide, Site-Wide,
--              and Department/Site-Specific Action Scopes in public.actions.
-- Authority: Confirmed business requirements with full security reconciliation.
-- ============================================================================

-- 1. Table Schema Alterations on public.actions
-- ----------------------------------------------------------------------------
-- Allow NULL department_id and site_id to support organization-wide and single-dimension scopes
ALTER TABLE public.actions ALTER COLUMN department_id DROP NOT NULL;
ALTER TABLE public.actions ALTER COLUMN site_id DROP NOT NULL;

-- Add scope_type column with default 'specific' for 100% backward compatibility
ALTER TABLE public.actions ADD COLUMN IF NOT EXISTS scope_type character varying(20) NOT NULL DEFAULT 'specific';

-- Enforce strict scope consistency across scope_type, department_id, and site_id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_actions_scope_consistency'
  ) THEN
    ALTER TABLE public.actions ADD CONSTRAINT chk_actions_scope_consistency CHECK (
      (scope_type = 'specific' AND department_id IS NOT NULL AND site_id IS NOT NULL) OR
      (scope_type = 'department' AND department_id IS NOT NULL AND site_id IS NULL) OR
      (scope_type = 'site' AND department_id IS NULL AND site_id IS NOT NULL) OR
      (scope_type = 'organization' AND department_id IS NULL AND site_id IS NULL)
    );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_actions_scope_type ON public.actions (organization_id, scope_type);

-- ----------------------------------------------------------------------------
-- 2. Scoped Manager Helpers for Department-Wide and Site-Wide Scopes
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_manager_of_department_wide(p_dept_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_org_id UUID;
  v_active_site_count INT;
  v_managed_site_count INT;
BEGIN
  IF p_dept_id IS NULL THEN
    RETURN false;
  END IF;

  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_platform_admin() THEN
    RETURN true;
  END IF;

  v_org_id := public.get_my_organization_id();
  IF v_org_id IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_admin() THEN
    RETURN true;
  END IF;

  IF NOT public.is_manager() THEN
    RETURN false;
  END IF;

  -- Ensure department exists, is active, and belongs to caller's organization
  IF NOT EXISTS (
    SELECT 1 FROM public.departments
    WHERE id = p_dept_id AND organization_id = v_org_id AND is_active = true
  ) THEN
    RETURN false;
  END IF;

  -- Total active sites in this organization
  SELECT COUNT(*) INTO v_active_site_count
  FROM public.sites
  WHERE organization_id = v_org_id AND is_active = true;

  -- If there are no sites configured, manager must have at least one scope in this department
  IF v_active_site_count = 0 THEN
    RETURN EXISTS (
      SELECT 1 FROM public.manager_scopes ms
      WHERE ms.manager_profile_id = v_caller_id
        AND ms.department_id = p_dept_id
    );
  END IF;

  -- Count of distinct active sites for which the manager holds scope in this department
  SELECT COUNT(DISTINCT s.id) INTO v_managed_site_count
  FROM public.sites s
  JOIN public.manager_scopes ms 
    ON ms.site_id = s.id 
   AND ms.department_id = p_dept_id 
   AND ms.manager_profile_id = v_caller_id
  WHERE s.organization_id = v_org_id AND s.is_active = true;

  RETURN v_managed_site_count = v_active_site_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_manager_of_site_wide(p_site_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_org_id UUID;
  v_active_dept_count INT;
  v_managed_dept_count INT;
BEGIN
  IF p_site_id IS NULL THEN
    RETURN false;
  END IF;

  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_platform_admin() THEN
    RETURN true;
  END IF;

  v_org_id := public.get_my_organization_id();
  IF v_org_id IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_admin() THEN
    RETURN true;
  END IF;

  IF NOT public.is_manager() THEN
    RETURN false;
  END IF;

  -- Ensure site exists, is active, and belongs to caller's organization
  IF NOT EXISTS (
    SELECT 1 FROM public.sites
    WHERE id = p_site_id AND organization_id = v_org_id AND is_active = true
  ) THEN
    RETURN false;
  END IF;

  -- Total active departments in this organization
  SELECT COUNT(*) INTO v_active_dept_count
  FROM public.departments
  WHERE organization_id = v_org_id AND is_active = true;

  -- If there are no departments configured, manager must have at least one scope at this site
  IF v_active_dept_count = 0 THEN
    RETURN EXISTS (
      SELECT 1 FROM public.manager_scopes ms
      WHERE ms.manager_profile_id = v_caller_id
        AND ms.site_id = p_site_id
    );
  END IF;

  -- Count of distinct active departments for which the manager holds scope at this site
  SELECT COUNT(DISTINCT d.id) INTO v_managed_dept_count
  FROM public.departments d
  JOIN public.manager_scopes ms 
    ON ms.department_id = d.id 
   AND ms.site_id = p_site_id 
   AND ms.manager_profile_id = v_caller_id
  WHERE d.organization_id = v_org_id AND d.is_active = true;

  RETURN v_managed_dept_count = v_active_dept_count;
END;
$$;

REVOKE ALL ON FUNCTION public.is_manager_of_department_wide(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.is_manager_of_department_wide(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.is_manager_of_site_wide(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.is_manager_of_site_wide(uuid) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. Update validate_action_before_write() Trigger Function
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_action_before_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
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
  v_assignee_role_code VARCHAR(50);
  v_assignee_role_name VARCHAR(100);
  v_assignee_is_primary_admin BOOLEAN;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NOT NULL THEN
    v_is_platform := public.is_platform_admin();
    v_is_company_admin := public.is_admin();
    v_is_mgr := public.is_manager();
    v_caller_org_id := public.get_my_organization_id();
  END IF;

  -- A. Enforce Organization Binding
  IF v_caller_id IS NOT NULL AND NOT v_is_platform THEN
    IF v_caller_org_id IS NULL THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: User is not linked to an active organization.';
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

  -- D. Validate Department (when specified, must exist, belong to org, and be active)
  IF NEW.department_id IS NOT NULL THEN
    SELECT is_active, organization_id INTO v_dept_active, v_dept_org
    FROM public.departments WHERE id = NEW.department_id;
    IF v_dept_org IS NULL OR v_dept_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Department does not belong to this organization.';
    END IF;
    IF v_dept_active IS NOT TRUE THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive department.';
    END IF;
  ELSE
    IF NEW.scope_type NOT IN ('organization', 'site') THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Department is required for % actions.', NEW.scope_type;
    END IF;
  END IF;

  -- E. Validate Site (when specified, must exist, belong to org, and be active)
  IF NEW.site_id IS NOT NULL THEN
    SELECT is_active, organization_id INTO v_site_active, v_site_org
    FROM public.sites WHERE id = NEW.site_id;
    IF v_site_org IS NULL OR v_site_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Site does not belong to this organization.';
    END IF;
    IF v_site_active IS NOT TRUE THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive site.';
    END IF;
  ELSE
    IF NEW.scope_type NOT IN ('organization', 'department') THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Site is required for % actions.', NEW.scope_type;
    END IF;
  END IF;

  -- F. Validate Section (if specified)
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

  -- G. Validate Division (if specified)
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

  -- H. Validate Team (if specified)
  IF NEW.team_id IS NOT NULL THEN
    SELECT is_active, organization_id, department_id
    INTO v_team_active, v_team_org, v_team_dept
    FROM public.teams WHERE id = NEW.team_id;

    IF v_team_org IS NULL OR v_team_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Team does not belong to this organization.';
    END IF;
    IF NEW.department_id IS NOT NULL AND (v_team_dept IS NULL OR v_team_dept != NEW.department_id) THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Team does not belong to the selected department.';
    END IF;
    IF v_team_active IS NOT TRUE THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive team.';
    END IF;
  END IF;

  -- I. Scope Authority Enforcement
  IF v_caller_id IS NOT NULL AND NOT v_is_platform AND NOT v_is_company_admin THEN
    IF NOT v_is_mgr THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Only active Managers and Company Administrators can create or update actions.';
    ELSE
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
        -- Authorized active manager in this organization creating organization-wide action
        IF NOT EXISTS (
          SELECT 1 FROM public.profiles p
          JOIN public.roles r ON p.role_id = r.id
          WHERE p.id = v_caller_id
            AND p.organization_id = NEW.organization_id
            AND p.is_active = true
            AND r.code IN ('manager', 'admin')
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
    JOIN public.roles r ON p.role_id = r.id
    WHERE p.id = NEW.assigned_to;

    IF v_assignee_org IS NULL OR v_assignee_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Assigned user does not belong to this organization.';
    END IF;
    IF v_assignee_active IS NOT TRUE OR v_assignee_status != 'active' THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Assigned user is inactive or not approved.';
    END IF;

    -- Operational Assignee Role Exclusion: Admin-role users cannot be assignees
    IF v_assignee_role_code = 'admin' OR LOWER(v_assignee_role_name) LIKE '%admin%' OR v_assignee_is_primary_admin IS TRUE THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Admin-role users are excluded from operational assignees.';
    END IF;

    -- Caller manager restrictions:
    IF v_is_mgr AND NOT v_is_company_admin AND NOT v_is_platform THEN
      IF NEW.assigned_to != v_caller_id THEN
        IF NEW.scope_type = 'organization' THEN
          -- In organization-wide action: Any active internal user in this organization is authorized!
          NULL;
        ELSIF NEW.scope_type = 'department' THEN
          IF v_assignee_dept != NEW.department_id AND NOT public.is_manager_of_scope(v_assignee_dept, v_assignee_site) THEN
            RAISE EXCEPTION 'ActionFlow Security Violation: Assigned user is outside department scope.';
          END IF;
        ELSIF NEW.scope_type = 'site' THEN
          IF v_assignee_site != NEW.site_id AND NOT public.is_manager_of_scope(v_assignee_dept, v_assignee_site) THEN
            RAISE EXCEPTION 'ActionFlow Security Violation: Assigned user is outside site scope.';
          END IF;
        ELSE
          -- Specific action: existing rule
          IF NOT public.is_manager_of_scope(v_assignee_dept, v_assignee_site)
             AND NOT (v_assignee_dept = NEW.department_id AND (v_assignee_site = NEW.site_id OR v_assignee_site IS NULL)) THEN
            RAISE EXCEPTION 'ActionFlow Security Violation: Assigned user is outside manager permitted scope.';
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
$function$;

-- ----------------------------------------------------------------------------
-- 4. Update validate_action_assignee_before_write() Trigger Function
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_action_assignee_before_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_action_org UUID;
  v_profile_org UUID;
  v_profile_active BOOLEAN;
  v_profile_status VARCHAR(50);
  v_profile_role_code VARCHAR(50);
  v_profile_role_name VARCHAR(100);
  v_profile_is_primary_admin BOOLEAN;
  v_caller_id UUID;
  v_is_platform BOOLEAN;
BEGIN
  v_caller_id := auth.uid();
  v_is_platform := public.is_platform_admin();

  -- 1. Ensure action exists and fetch its organization
  SELECT organization_id INTO v_action_org
  FROM public.actions WHERE id = NEW.action_id;

  IF v_action_org IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Action % does not exist.', NEW.action_id;
  END IF;

  -- 2. Organization match
  IF NEW.organization_id != v_action_org THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Assignee organization does not match action organization.';
  END IF;

  -- 3. Profile existence, organization match, active status, and role check
  SELECT p.organization_id, p.is_active, p.status, r.code, r.name, p.is_primary_admin
  INTO v_profile_org, v_profile_active, v_profile_status, v_profile_role_code, v_profile_role_name, v_profile_is_primary_admin
  FROM public.profiles p
  JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = NEW.profile_id;

  IF v_profile_org IS NULL OR v_profile_org != v_action_org THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Assigned profile does not belong to this organization.';
  END IF;

  IF v_profile_active IS NOT TRUE OR v_profile_status != 'active' THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Assigned user is inactive or not approved.';
  END IF;

  -- Operational Assignee Role Exclusion: Admin-role users cannot be assignees
  IF v_profile_role_code = 'admin' OR LOWER(v_profile_role_name) LIKE '%admin%' OR v_profile_is_primary_admin IS TRUE THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Admin-role users are excluded from operational assignees.';
  END IF;

  -- 4. Caller authorization (if caller is authenticated)
  IF v_caller_id IS NOT NULL AND NOT v_is_platform THEN
    IF TG_OP = 'UPDATE' AND NEW.profile_id = v_caller_id THEN
      -- Assignees are authorized to update their own work completion status
      NULL;
    ELSIF NOT app_private.can_manage_action(NEW.action_id) THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Caller is not authorized to manage assignees for this action.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_action_assignee_before_write ON public.action_assignees;
CREATE TRIGGER trg_validate_action_assignee_before_write
  BEFORE INSERT OR UPDATE ON public.action_assignees
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_action_assignee_before_write();

REVOKE ALL ON FUNCTION public.validate_action_assignee_before_write() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.validate_action_assignee_before_write() TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5. Update RLS Policies on public.actions
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Manager insert actions" ON public.actions;
CREATE POLICY "Manager insert actions" ON public.actions
  FOR INSERT TO authenticated
  WITH CHECK (
    is_manager()
    AND organization_id = get_my_organization_id()
    AND created_by = auth.uid()
    AND (
      (scope_type = 'specific' AND is_manager_of_scope(department_id, site_id))
      OR (scope_type = 'department' AND is_manager_of_department_wide(department_id))
      OR (scope_type = 'site' AND is_manager_of_site_wide(site_id))
      OR (scope_type = 'organization' AND department_id IS NULL AND site_id IS NULL)
    )
  );

DROP POLICY IF EXISTS "Manager select actions" ON public.actions;
CREATE POLICY "Manager select actions" ON public.actions
  FOR SELECT TO authenticated
  USING (
    is_manager()
    AND organization_id = get_my_organization_id()
    AND (
      created_by = auth.uid()
      OR assigned_to = auth.uid()
      OR app_private.is_action_participant(id)
      OR (scope_type = 'specific' AND is_manager_of_scope(department_id, site_id))
      OR (scope_type = 'department' AND (
            is_manager_of_department_wide(department_id)
            OR EXISTS (
              SELECT 1 FROM public.manager_scopes ms 
              WHERE ms.manager_profile_id = auth.uid() AND ms.department_id = actions.department_id
            )
         ))
      OR (scope_type = 'site' AND (
            is_manager_of_site_wide(site_id)
            OR EXISTS (
              SELECT 1 FROM public.manager_scopes ms 
              WHERE ms.manager_profile_id = auth.uid() AND ms.site_id = actions.site_id
            )
         ))
    )
  );

DROP POLICY IF EXISTS "Manager update actions" ON public.actions;
CREATE POLICY "Manager update actions" ON public.actions
  FOR UPDATE TO authenticated
  USING (
    is_manager()
    AND organization_id = get_my_organization_id()
    AND (
      (scope_type = 'organization' AND created_by = auth.uid())
      OR (scope_type = 'specific' AND (created_by = auth.uid() OR is_manager_of_scope(department_id, site_id)))
      OR (scope_type = 'department' AND (created_by = auth.uid() OR is_manager_of_department_wide(department_id)))
      OR (scope_type = 'site' AND (created_by = auth.uid() OR is_manager_of_site_wide(site_id)))
    )
  )
  WITH CHECK (
    is_manager()
    AND organization_id = get_my_organization_id()
    AND (
      (scope_type = 'organization' AND created_by = auth.uid())
      OR (scope_type = 'specific' AND (created_by = auth.uid() OR is_manager_of_scope(department_id, site_id)))
      OR (scope_type = 'department' AND (created_by = auth.uid() OR is_manager_of_department_wide(department_id)))
      OR (scope_type = 'site' AND (created_by = auth.uid() OR is_manager_of_site_wide(site_id)))
    )
  );

DROP POLICY IF EXISTS "Manager delete actions" ON public.actions;
CREATE POLICY "Manager delete actions" ON public.actions
  FOR DELETE TO authenticated
  USING (
    is_manager()
    AND organization_id = get_my_organization_id()
    AND created_by = auth.uid()
    AND (
      scope_type = 'organization'
      OR (scope_type = 'specific' AND is_manager_of_scope(department_id, site_id))
      OR (scope_type = 'department' AND is_manager_of_department_wide(department_id))
      OR (scope_type = 'site' AND is_manager_of_site_wide(site_id))
    )
  );

-- ----------------------------------------------------------------------------
-- 6. Helper: app_private.can_manage_action
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app_private.can_manage_action(p_action_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.actions a
    WHERE a.id = p_action_id
      AND a.organization_id = (SELECT organization_id FROM public.profiles WHERE id = (SELECT auth.uid()) AND is_active = true)
      AND (
        (SELECT public.is_platform_admin())
        OR (
          EXISTS (
            SELECT 1 FROM public.profiles p
            JOIN public.roles r ON p.role_id = r.id
            WHERE p.id = (SELECT auth.uid()) AND r.code = 'admin' AND p.is_active = true
          )
        )
        OR (
          a.scope_type = 'organization'
          AND a.created_by = (SELECT auth.uid())
          AND (SELECT public.is_manager())
        )
        OR (
          a.scope_type = 'specific'
          AND (
            (a.created_by = (SELECT auth.uid()) AND (SELECT public.is_manager()))
            OR (SELECT public.is_manager_of_scope(a.department_id, a.site_id))
          )
        )
        OR (
          a.scope_type = 'department'
          AND (
            (a.created_by = (SELECT auth.uid()) AND (SELECT public.is_manager()))
            OR (SELECT public.is_manager_of_department_wide(a.department_id))
          )
        )
        OR (
          a.scope_type = 'site'
          AND (
            (a.created_by = (SELECT auth.uid()) AND (SELECT public.is_manager()))
            OR (SELECT public.is_manager_of_site_wide(a.site_id))
          )
        )
      )
  );
$function$;

REVOKE ALL ON FUNCTION app_private.can_manage_action(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION app_private.can_manage_action(uuid) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 7. Stored Procedure: public.delete_action_authorized (Soft Delete)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.delete_action_authorized(uuid);
DROP FUNCTION IF EXISTS public.delete_action_authorized(uuid, boolean);

CREATE OR REPLACE FUNCTION public.delete_action_authorized(
  p_action_id uuid,
  p_allow_closed boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_org_id       UUID;
  v_dept_id      UUID;
  v_site_id      UUID;
  v_created_by   UUID;
  v_scope_type   TEXT;
  v_status       TEXT;
  v_caller_org   UUID;
  v_is_admin     BOOLEAN;
  v_is_manager   BOOLEAN;
  v_is_platform  BOOLEAN;
BEGIN
  -- 1. Require authenticated caller
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Authentication required');
  END IF;

  -- 2. Fetch action existence, tenant, and scope fields
  SELECT organization_id, department_id, site_id, status, created_by, COALESCE(scope_type, 'specific')
  INTO v_org_id, v_dept_id, v_site_id, v_status, v_created_by, v_scope_type
  FROM public.actions
  WHERE id = p_action_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action not found');
  END IF;

  -- If already deleted
  IF lower(trim(coalesce(v_status, ''))) = 'deleted' THEN
    RETURN jsonb_build_object('success', true, 'message', 'Action is already deleted');
  END IF;

  -- 3. Resolve caller roles and tenant
  v_is_platform := public.is_platform_admin();
  v_is_admin    := public.is_admin();
  v_is_manager  := public.is_manager();
  v_caller_org  := public.get_my_organization_id();

  -- 4. Cross-Tenant Isolation
  IF NOT v_is_platform AND (v_org_id IS DISTINCT FROM v_caller_org) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Cross-tenant operation blocked');
  END IF;

  -- 5. Role Authority
  IF NOT v_is_platform AND NOT v_is_admin AND NOT v_is_manager THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Manager or Admin role required');
  END IF;

  -- 6. Manager Scope Authorization
  IF v_is_manager AND NOT v_is_admin AND NOT v_is_platform THEN
    IF NOT (
      (v_scope_type = 'organization' AND v_created_by = auth.uid())
      OR (v_scope_type = 'specific' AND (v_created_by = auth.uid() OR public.is_manager_of_scope(v_dept_id, v_site_id)))
      OR (v_scope_type = 'department' AND (v_created_by = auth.uid() OR public.is_manager_of_department_wide(v_dept_id)))
      OR (v_scope_type = 'site' AND (v_created_by = auth.uid() OR public.is_manager_of_site_wide(v_site_id)))
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Manager scope does not cover this action');
    END IF;
  END IF;

  -- 7. Closed Action Protection
  IF NOT p_allow_closed AND lower(trim(coalesce(v_status, ''))) = 'closed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLOSED_ACTION');
  END IF;

  -- 8. Safe Soft Delete
  UPDATE public.actions
  SET
    status = 'Deleted',
    deleted_at = timezone('utc'::text, now()),
    deleted_by = auth.uid(),
    updated_at = timezone('utc'::text, now())
  WHERE id = p_action_id;

  -- 9. Audit Log record (safe attempt)
  BEGIN
    INSERT INTO public.platform_audit_logs (
      organization_id,
      actor_id,
      action,
      entity_type,
      entity_id,
      details
    ) VALUES (
      v_org_id,
      auth.uid(),
      'ACTION_SOFT_DELETED',
      'actions',
      p_action_id::TEXT,
      jsonb_build_object(
        'action_id', p_action_id,
        'previous_status', v_status,
        'deleted_at', timezone('utc'::text, now())
      )
    );
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('success', true);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.delete_action_authorized(uuid, boolean) TO authenticated;

-- ----------------------------------------------------------------------------
-- 8. Stored Procedure: public.delete_actions_bulk_authorized (Soft Delete)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.delete_actions_bulk_authorized(UUID[]);
DROP FUNCTION IF EXISTS public.delete_actions_bulk_authorized(UUID[], BOOLEAN);

CREATE OR REPLACE FUNCTION public.delete_actions_bulk_authorized(
  p_action_ids UUID[],
  p_allow_closed BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id       UUID;
  v_caller_org      UUID;
  v_is_admin        BOOLEAN;
  v_is_manager      BOOLEAN;
  v_is_platform     BOOLEAN;
  v_curr_id         UUID;
  v_org_id          UUID;
  v_dept_id         UUID;
  v_site_id         UUID;
  v_scope_type      TEXT;
  v_status          TEXT;
  v_created_by      UUID;
  v_is_manager_scope BOOLEAN;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'deleted_count', 0,
      'failed_ids', ARRAY[]::TEXT[],
      'error', 'Unauthorized: Authentication required'
    );
  END IF;

  IF p_action_ids IS NULL OR array_length(p_action_ids, 1) = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'deleted_count', 0,
      'failed_ids', ARRAY[]::TEXT[],
      'error', NULL
    );
  END IF;

  v_caller_org  := public.get_my_organization_id();
  v_is_admin    := public.is_admin();
  v_is_manager  := public.is_manager();
  v_is_platform := public.is_platform_admin();

  -- PHASE 1: Pre-validation of all actions
  FOREACH v_curr_id IN ARRAY p_action_ids LOOP
    SELECT organization_id, department_id, site_id, status, created_by, COALESCE(scope_type, 'specific')
      INTO v_org_id, v_dept_id, v_site_id, v_status, v_created_by, v_scope_type
      FROM public.actions
     WHERE id = v_curr_id;

    IF NOT FOUND THEN
      RETURN jsonb_build_object(
        'success', false,
        'deleted_count', 0,
        'failed_ids', ARRAY[v_curr_id::TEXT],
        'error', 'Action not found: ' || v_curr_id::TEXT
      );
    END IF;

    IF v_caller_org IS NULL OR v_org_id IS DISTINCT FROM v_caller_org THEN
      RETURN jsonb_build_object(
        'success', false,
        'deleted_count', 0,
        'failed_ids', ARRAY[v_curr_id::TEXT],
        'error', 'Unauthorized: Tenant isolation violation for action ' || v_curr_id::TEXT
      );
    END IF;

    IF NOT p_allow_closed AND lower(trim(coalesce(v_status, ''))) = 'closed' THEN
      RETURN jsonb_build_object(
        'success', false,
        'deleted_count', 0,
        'failed_ids', ARRAY[v_curr_id::TEXT],
        'error', 'CLOSED_ACTION: ' || v_curr_id::TEXT
      );
    END IF;

    v_is_manager_scope := FALSE;
    IF v_is_manager AND NOT v_is_admin AND NOT v_is_platform THEN
      v_is_manager_scope := (
        (v_scope_type = 'organization' AND v_created_by = v_caller_id)
        OR (v_scope_type = 'specific' AND (v_created_by = v_caller_id OR public.is_manager_of_scope(v_dept_id, v_site_id)))
        OR (v_scope_type = 'department' AND (v_created_by = v_caller_id OR public.is_manager_of_department_wide(v_dept_id)))
        OR (v_scope_type = 'site' AND (v_created_by = v_caller_id OR public.is_manager_of_site_wide(v_site_id)))
      );
    END IF;

    IF NOT (v_is_admin OR v_is_platform OR v_is_manager_scope) THEN
      RETURN jsonb_build_object(
        'success', false,
        'deleted_count', 0,
        'failed_ids', ARRAY[v_curr_id::TEXT],
        'error', 'Unauthorized: Insufficient permissions to delete action ' || v_curr_id::TEXT
      );
    END IF;
  END LOOP;

  -- PHASE 2: Bulk Soft Delete
  UPDATE public.actions
     SET status = 'Deleted',
         deleted_at = timezone('utc'::text, now()),
         deleted_by = v_caller_id,
         updated_at = timezone('utc'::text, now())
   WHERE id = ANY(p_action_ids);

  -- PHASE 3: Audit Log
  FOREACH v_curr_id IN ARRAY p_action_ids LOOP
    BEGIN
      INSERT INTO public.platform_audit_logs (
        organization_id,
        actor_id,
        action,
        entity_type,
        entity_id,
        details
      ) VALUES (
        v_caller_org,
        v_caller_id,
        'ACTION_BULK_SOFT_DELETED',
        'actions',
        v_curr_id::TEXT,
        jsonb_build_object(
          'action_id', v_curr_id,
          'deleted_at', timezone('utc'::text, now())
        )
      );
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'deleted_count', array_length(p_action_ids, 1),
    'failed_ids', ARRAY[]::TEXT[],
    'error', NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_actions_bulk_authorized(UUID[], BOOLEAN) TO authenticated;

-- ----------------------------------------------------------------------------
-- 9. Stored Procedure: public.close_action_verified
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.close_action_verified(p_action_id uuid, p_closure_comment text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_caller_id UUID;
  v_caller_org UUID;
  v_is_platform BOOLEAN := false;
  v_is_admin BOOLEAN := false;
  v_is_mgr BOOLEAN := false;
  v_action public.actions%ROWTYPE;
  v_actor_name VARCHAR(150);
  v_history_entry JSONB;
  v_uncompleted_assignees INT := 0;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Authentication required');
  END IF;

  v_is_platform := public.is_platform_admin();
  v_is_admin := public.is_admin();
  v_is_mgr := public.is_manager();
  v_caller_org := public.get_my_organization_id();

  SELECT * INTO v_action
  FROM public.actions
  WHERE id = p_action_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action not found');
  END IF;

  IF NOT v_is_platform AND (v_action.organization_id != v_caller_org) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Cross-tenant operation blocked');
  END IF;

  IF lower(trim(coalesce(v_action.status, ''))) = 'closed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action is already closed');
  END IF;

  -- Role Authorization: Manager/Admin only
  IF NOT v_is_platform AND NOT v_is_admin THEN
    IF NOT v_is_mgr OR NOT (
      (v_action.scope_type = 'organization' AND v_action.created_by = v_caller_id)
      OR (v_action.scope_type = 'specific' AND (v_action.created_by = v_caller_id OR public.is_manager_of_scope(v_action.department_id, v_action.site_id)))
      OR (v_action.scope_type = 'department' AND (v_action.created_by = v_caller_id OR public.is_manager_of_department_wide(v_action.department_id)))
      OR (v_action.scope_type = 'site' AND (v_action.created_by = v_caller_id OR public.is_manager_of_site_wide(v_action.site_id)))
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Manager authority required to approve and close actions');
    END IF;
  END IF;

  -- Overall Progress must be 100%
  IF v_action.percent_complete < 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action cannot be closed before reaching 100% completion');
  END IF;

  -- Required Assignees Gate
  SELECT COUNT(*) INTO v_uncompleted_assignees
  FROM public.action_assignees
  WHERE action_id = p_action_id
    AND is_required = true
    AND work_completed = false;

  IF v_uncompleted_assignees > 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'All required assignees must complete their assigned work before the Action can be formally closed (' || v_uncompleted_assignees || ' remaining).'
    );
  END IF;

  SELECT full_name INTO v_actor_name
  FROM public.profiles WHERE id = v_caller_id;

  v_history_entry := jsonb_build_object(
    'event', 'action_closed',
    'timestamp', now(),
    'closed_at', now(),
    'closed_by', v_caller_id,
    'closed_by_name', COALESCE(v_actor_name, 'Manager'),
    'comment', COALESCE(p_closure_comment, ''),
    'display', to_char(now(), 'DD Mon YYYY HH24:MI') || ' - Action Formally Closed by ' || COALESCE(v_actor_name, 'Manager') || '. Comment: ' || COALESCE(p_closure_comment, 'Verified')
  );

  UPDATE public.actions
  SET
    status = 'Closed',
    close_date = CURRENT_DATE,
    closed_at = now(),
    closed_by = v_caller_id,
    closure_comment = COALESCE(p_closure_comment, ''),
    history = COALESCE(history, '[]'::jsonb) || jsonb_build_array(v_history_entry),
    updated_at = now()
  WHERE id = p_action_id;

  RETURN jsonb_build_object('success', true, 'closed_at', now(), 'closed_by_name', v_actor_name);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.close_action_verified(uuid, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 10. Stored Procedure: public.approve_and_close_action
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_and_close_action(p_action_id uuid, p_closure_comment text DEFAULT ''::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_caller_id UUID;
  v_caller_org UUID;
  v_is_platform BOOLEAN := false;
  v_is_admin BOOLEAN := false;
  v_is_mgr BOOLEAN := false;
  v_action public.actions%ROWTYPE;
  v_actor_name VARCHAR(150);
  v_history_entry JSONB;
  v_uncompleted_assignees INT := 0;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Authentication required.';
  END IF;

  v_is_platform := public.is_platform_admin();
  v_is_admin := public.is_admin();
  v_is_mgr := public.is_manager();
  v_caller_org := public.get_my_organization_id();

  SELECT * INTO v_action
  FROM public.actions
  WHERE id = p_action_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Action not found.';
  END IF;

  IF NOT v_is_platform AND (v_action.organization_id != v_caller_org) THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Cross-tenant operation blocked.';
  END IF;

  IF lower(trim(coalesce(v_action.status, ''))) = 'closed' THEN
    RAISE EXCEPTION 'Action is already closed.';
  END IF;

  -- Role Authorization: Manager/Admin only
  IF NOT v_is_platform AND NOT v_is_admin THEN
    IF NOT v_is_mgr OR NOT (
      (v_action.scope_type = 'organization' AND v_action.created_by = v_caller_id)
      OR (v_action.scope_type = 'specific' AND (v_action.created_by = v_caller_id OR public.is_manager_of_scope(v_action.department_id, v_action.site_id)))
      OR (v_action.scope_type = 'department' AND (v_action.created_by = v_caller_id OR public.is_manager_of_department_wide(v_action.department_id)))
      OR (v_action.scope_type = 'site' AND (v_action.created_by = v_caller_id OR public.is_manager_of_site_wide(v_action.site_id)))
    ) THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Manager authority required to approve and close actions.';
    END IF;
  END IF;

  -- Overall Progress must be 100%
  IF v_action.percent_complete < 100 THEN
    RAISE EXCEPTION 'Action cannot be closed before reaching 100%% completion.';
  END IF;

  -- Required Assignees Gate
  SELECT COUNT(*) INTO v_uncompleted_assignees
  FROM public.action_assignees
  WHERE action_id = p_action_id
    AND is_required = true
    AND work_completed = false;

  IF v_uncompleted_assignees > 0 THEN
    RAISE EXCEPTION 'All required assignees must complete their assigned work before the Action can be formally closed (% remaining).', v_uncompleted_assignees;
  END IF;

  SELECT full_name INTO v_actor_name
  FROM public.profiles WHERE id = v_caller_id;

  v_history_entry := jsonb_build_object(
    'event', 'action_approved_and_closed',
    'timestamp', now(),
    'closed_at', now(),
    'closed_by', v_caller_id,
    'closed_by_name', COALESCE(v_actor_name, 'Manager'),
    'comment', COALESCE(p_closure_comment, ''),
    'display', to_char(now(), 'DD Mon YYYY HH24:MI') || ' - Action Formally Approved & Closed by ' || COALESCE(v_actor_name, 'Manager') || '. Comment: ' || COALESCE(p_closure_comment, 'Approved')
  );

  UPDATE public.actions
  SET
    status = 'Closed',
    close_date = CURRENT_DATE,
    closed_at = now(),
    closed_by = v_caller_id,
    closure_comment = COALESCE(p_closure_comment, ''),
    history = COALESCE(history, '[]'::jsonb) || jsonb_build_array(v_history_entry),
    updated_at = now()
  WHERE id = p_action_id;

  INSERT INTO public.action_progress_updates (
    action_id,
    organization_id,
    updated_by,
    update_date,
    progress,
    status,
    comments,
    attachments,
    role_in_action,
    contribution_value,
    created_at
  ) VALUES (
    p_action_id,
    v_action.organization_id,
    v_caller_id,
    CURRENT_DATE,
    100,
    'Closed',
    'Action approved and closed. ' || COALESCE(p_closure_comment, ''),
    '[]'::jsonb,
    'manager',
    0,
    now()
  );

  RETURN jsonb_build_object('success', true, 'closed_at', now(), 'closed_by_name', v_actor_name);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.approve_and_close_action(uuid, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 11. Stored Procedure: public.reopen_action
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reopen_action(p_action_uuid uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_caller_id UUID;
  v_caller_org UUID;
  v_is_platform BOOLEAN := false;
  v_is_admin BOOLEAN := false;
  v_is_mgr BOOLEAN := false;
  v_action public.actions%ROWTYPE;
  v_actor_name VARCHAR(150);
  v_history_entry JSONB;
  v_subtasks JSONB;
  v_task JSONB;
  v_total_tasks INT := 0;
  v_completed_tasks INT := 0;
  v_calculated_percent INT;
  v_result JSONB;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Authentication required.';
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'ActionFlow Error: A mandatory reason is required to reopen an action.';
  END IF;

  v_is_platform := public.is_platform_admin();
  v_is_admin := public.is_admin();
  v_is_mgr := public.is_manager();
  v_caller_org := public.get_my_organization_id();

  SELECT * INTO v_action
  FROM public.actions
  WHERE id = p_action_uuid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ActionFlow Error: Action not found.';
  END IF;

  IF NOT v_is_platform AND (v_action.organization_id != v_caller_org) THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Cross-tenant operation blocked.';
  END IF;

  IF lower(trim(coalesce(v_action.status, ''))) != 'closed' THEN
    RAISE EXCEPTION 'ActionFlow Error: Action is not currently closed and cannot be reopened.';
  END IF;

  -- Role Authorization
  IF NOT v_is_platform AND NOT v_is_admin THEN
    IF NOT v_is_mgr OR NOT (
      (v_action.scope_type = 'organization' AND v_action.created_by = v_caller_id)
      OR (v_action.scope_type = 'specific' AND (v_action.created_by = v_caller_id OR public.is_manager_of_scope(v_action.department_id, v_action.site_id)))
      OR (v_action.scope_type = 'department' AND (v_action.created_by = v_caller_id OR public.is_manager_of_department_wide(v_action.department_id)))
      OR (v_action.scope_type = 'site' AND (v_action.created_by = v_caller_id OR public.is_manager_of_site_wide(v_action.site_id)))
    ) THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Manager authority required to reopen actions.';
    END IF;
  END IF;

  -- Recalculate percent_complete
  v_subtasks := COALESCE(v_action.subtasks, '[]'::jsonb);
  v_total_tasks := jsonb_array_length(v_subtasks);
  IF v_total_tasks > 0 THEN
    FOR i IN 0..v_total_tasks-1 LOOP
      v_task := v_subtasks->i;
      IF (v_task->>'is_completed')::boolean IS TRUE THEN
        v_completed_tasks := v_completed_tasks + 1;
      END IF;
    END LOOP;
    v_calculated_percent := ROUND((v_completed_tasks::numeric / v_total_tasks::numeric) * 100);
  ELSE
    v_calculated_percent := 0;
  END IF;

  SELECT full_name INTO v_actor_name
  FROM public.profiles WHERE id = v_caller_id;

  v_history_entry := jsonb_build_object(
    'action', 'Action Reopened: ' || trim(p_reason),
    'actor_id', v_caller_id,
    'actor_name', COALESCE(v_actor_name, 'Manager'),
    'reason', trim(p_reason),
    'previous_status', 'Closed',
    'timestamp', now()
  );

  UPDATE public.actions
  SET
    status = 'In Progress',
    percent_complete = v_calculated_percent,
    close_date = NULL,
    closed_at = NULL,
    closed_by = NULL,
    closure_comment = '',
    history = COALESCE(history, '[]'::jsonb) || jsonb_build_array(v_history_entry),
    updated_at = now()
  WHERE id = p_action_uuid;

  INSERT INTO public.action_progress_updates (
    action_id,
    organization_id,
    updated_by,
    update_date,
    progress,
    status,
    comments,
    attachments,
    role_in_action,
    contribution_value,
    created_at
  ) VALUES (
    p_action_uuid,
    v_action.organization_id,
    v_caller_id,
    CURRENT_DATE,
    v_calculated_percent,
    'In Progress',
    'Action Reopened: ' || trim(p_reason),
    '[]'::jsonb,
    'manager',
    0,
    now()
  );

  SELECT to_jsonb(a.*) INTO v_result
  FROM public.actions a
  WHERE a.id = p_action_uuid;

  RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.reopen_action(uuid, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 12. Stored Procedure: public.request_more_information_on_action
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_more_information_on_action(p_action_id uuid, p_comments text, p_target_status text DEFAULT 'In Progress'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_caller_id UUID;
  v_caller_profile RECORD;
  v_action RECORD;
  v_is_platform BOOLEAN := false;
  v_is_company_admin BOOLEAN := false;
  v_is_mgr BOOLEAN := false;
  v_is_scoped BOOLEAN := false;
  v_history_entry JSONB;
  v_new_status TEXT;
  v_result JSONB;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to request more information.';
  END IF;

  IF p_comments IS NULL OR trim(p_comments) = '' THEN
    RAISE EXCEPTION 'A valid explanation or comment is required when requesting more information.';
  END IF;

  SELECT id, organization_id, designation, full_name, is_active
  INTO v_caller_profile
  FROM public.profiles
  WHERE id = v_caller_id;

  IF v_caller_profile.id IS NULL OR v_caller_profile.is_active IS NOT TRUE THEN
    RAISE EXCEPTION 'Caller profile not found or inactive.';
  END IF;

  v_is_platform := public.is_platform_admin();
  v_is_company_admin := public.is_admin();
  v_is_mgr := public.is_manager();

  IF NOT v_is_platform AND NOT v_is_company_admin AND NOT v_is_mgr THEN
    RAISE EXCEPTION 'Unauthorized: Only Managers and Admins can request more information on actions.';
  END IF;

  SELECT a.id, a.organization_id, a.department_id, a.site_id, a.percent_complete, a.status, a.created_by, COALESCE(a.scope_type, 'specific') as scope_type
  INTO v_action
  FROM public.actions a
  WHERE a.id = p_action_id;

  IF v_action.id IS NULL THEN
    RAISE EXCEPTION 'Action not found.';
  END IF;

  IF NOT v_is_platform AND v_action.organization_id != v_caller_profile.organization_id THEN
    RAISE EXCEPTION 'Security violation: Cross-tenant access blocked.';
  END IF;

  IF v_is_mgr AND NOT v_is_company_admin AND NOT v_is_platform THEN
    v_is_scoped := (
      (v_action.scope_type = 'organization' AND v_action.created_by = v_caller_id)
      OR (v_action.scope_type = 'specific' AND (v_action.created_by = v_caller_id OR public.is_manager_of_scope(v_action.department_id, v_action.site_id)))
      OR (v_action.scope_type = 'department' AND (v_action.created_by = v_caller_id OR public.is_manager_of_department_wide(v_action.department_id)))
      OR (v_action.scope_type = 'site' AND (v_action.created_by = v_caller_id OR public.is_manager_of_site_wide(v_action.site_id)))
    );

    IF NOT v_is_scoped THEN
      RAISE EXCEPTION 'Unauthorized: Manager is not assigned supervisory scope for this action.';
    END IF;
  END IF;

  v_new_status := COALESCE(NULLIF(trim(p_target_status), ''), 'In Progress');
  IF v_new_status = 'Closed' THEN
    v_new_status := 'In Progress';
  END IF;

  v_history_entry := jsonb_build_object(
    'event', 'Information Requested by Manager',
    'requested_by', v_caller_id,
    'requested_by_name', COALESCE(v_caller_profile.full_name, 'Manager'),
    'comment', trim(p_comments),
    'new_status', v_new_status,
    'timestamp', now()
  );

  UPDATE public.actions
  SET
    status = v_new_status,
    history = COALESCE(history, '[]'::jsonb) || jsonb_build_array(v_history_entry),
    updated_at = now()
  WHERE id = p_action_id;

  INSERT INTO public.action_progress_updates (
    action_id,
    organization_id,
    updated_by,
    update_date,
    progress,
    status,
    comments,
    attachments,
    role_in_action,
    contribution_value,
    created_at
  ) VALUES (
    p_action_id,
    v_action.organization_id,
    v_caller_id,
    CURRENT_DATE,
    v_action.percent_complete,
    v_new_status,
    'Manager requested more information: ' || trim(p_comments),
    '[]'::jsonb,
    'manager',
    0,
    now()
  );

  SELECT to_jsonb(a.*) INTO v_result
  FROM public.actions a
  WHERE a.id = p_action_id;

  RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.request_more_information_on_action(uuid, text, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 13. Stored Procedure: public.get_external_action_by_token
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_external_action_by_token(p_token_hash character varying)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_token public.external_action_tokens%ROWTYPE;
  v_action public.actions%ROWTYPE;
  v_recipient public.external_action_recipients%ROWTYPE;
  v_dept_name VARCHAR(255);
  v_site_name VARCHAR(255);
  v_org_name VARCHAR(255);
  v_all_subtasks JSONB;
  v_contractor_tasks JSONB := '[]'::jsonb;
  v_task JSONB;
BEGIN
  IF p_token_hash IS NULL OR trim(p_token_hash) = '' THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Access token is missing or empty.');
  END IF;

  -- 1. Find token
  SELECT * INTO v_token
  FROM public.external_action_tokens
  WHERE token_hash = p_token_hash;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Invalid access link. Token does not exist.');
  END IF;

  -- 2. Check revoked status
  IF v_token.is_revoked THEN
    RETURN jsonb_build_object(
      'valid', false,
      'error', 'This access link has been revoked by the manager. Please request a new link.'
    );
  END IF;

  -- 3. Check expiration
  IF v_token.expires_at < now() THEN
    RETURN jsonb_build_object(
      'valid', false,
      'error', 'This access link has expired. Please contact the safety manager to request a new link.'
    );
  END IF;

  -- 4. Fetch associated action
  SELECT * INTO v_action
  FROM public.actions
  WHERE id = v_token.action_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'The requested action record could not be found.');
  END IF;

  -- 5. Fetch external recipient
  SELECT * INTO v_recipient
  FROM public.external_action_recipients
  WHERE id = v_token.recipient_id;

  -- 6. Resolve department, site, and organization names gracefully for scoped and org-wide actions
  IF v_action.department_id IS NULL THEN
    v_dept_name := 'All Departments';
  ELSE
    SELECT name INTO v_dept_name
    FROM public.departments
    WHERE id = v_action.department_id;
  END IF;

  IF v_action.site_id IS NULL THEN
    v_site_name := 'All Sites / Locations';
  ELSE
    SELECT name INTO v_site_name
    FROM public.sites
    WHERE id = v_action.site_id;
  END IF;

  SELECT name INTO v_org_name
  FROM public.organizations
  WHERE id = v_action.organization_id;

  -- 7. Filter subtasks: only return tasks assigned to this external contractor
  v_all_subtasks := COALESCE(v_action.subtasks, '[]'::jsonb);
  IF jsonb_array_length(v_all_subtasks) > 0 THEN
    FOR i IN 0..jsonb_array_length(v_all_subtasks)-1 LOOP
      v_task := v_all_subtasks->i;
      IF (v_task->>'assignee_type' = 'external' OR v_task->>'assigneeType' = 'external')
         AND (
           v_task->>'external_recipient_id' = v_recipient.id::text
           OR v_task->>'recipientId' = v_recipient.id::text
           OR lower(trim(coalesce(v_task->>'assigned_staff_email', ''))) = lower(trim(v_recipient.email))
           OR lower(trim(coalesce(v_task->>'assigned_to', ''))) = lower(trim(v_recipient.email))
         ) THEN
        v_contractor_tasks := v_contractor_tasks || jsonb_build_array(v_task);
      END IF;
    END LOOP;
  END IF;

  -- 8. Increment access count & update last_accessed_at
  UPDATE public.external_action_tokens
  SET
    access_count = access_count + 1,
    last_accessed_at = now()
  WHERE id = v_token.id;

  RETURN jsonb_build_object(
    'valid', true,
    'action', jsonb_build_object(
      'id', v_action.id,
      'action_number', v_action.action_number,
      'title', v_action.title,
      'description', COALESCE(v_action.description, v_action.action_required, ''),
      'action_required', COALESCE(v_action.action_required, ''),
      'category', COALESCE(v_action.category, 'General'),
      'priority', COALESCE(v_action.priority, 'Medium'),
      'status', v_action.status,
      'percent_complete', COALESCE(v_action.percent_complete, 0),
      'date_raised', to_char(COALESCE(v_action.date_raised, v_action.created_date, CURRENT_DATE), 'YYYY-MM-DD'),
      'start_date', to_char(COALESCE(v_action.start_date, CURRENT_DATE), 'YYYY-MM-DD'),
      'target_date', to_char(COALESCE(v_action.target_date, v_action.due_date, CURRENT_DATE), 'YYYY-MM-DD'),
      'due_date', to_char(COALESCE(v_action.due_date, v_action.target_date, CURRENT_DATE), 'YYYY-MM-DD'),
      'next_follow_up_date', CASE WHEN v_action.next_follow_up_date IS NOT NULL THEN to_char(v_action.next_follow_up_date, 'YYYY-MM-DD') ELSE '' END,
      'department', COALESCE(v_dept_name, 'All Departments'),
      'site', COALESCE(v_site_name, 'All Sites / Locations'),
      'organization_name', COALESCE(v_org_name, 'ActionFlow'),
      'is_closed', (v_action.status = 'Closed'),
      'recent_history', COALESCE(v_action.history, '[]'::jsonb),
      'subtasks', v_contractor_tasks
    ),
    'recipient', jsonb_build_object(
      'id', v_recipient.id,
      'name', COALESCE(v_recipient.full_name, ''),
      'email', COALESCE(v_recipient.email, ''),
      'company_name', COALESCE(v_recipient.company_name, ''),
      'phone', COALESCE(v_recipient.phone, '')
    ),
    'token', jsonb_build_object(
      'expires_at', v_token.expires_at,
      'access_count', v_token.access_count + 1
    )
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_external_action_by_token(character varying) TO anon, authenticated, service_role;

