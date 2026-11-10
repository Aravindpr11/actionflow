-- Forward-Only Migration: Action Contributor Hardening & Staff Action Closure Guard
-- Migration ID: 20261107000001
-- Description:
-- 1. Updates public.add_action_contributor() with strict UUID/text casting, organization_id binding,
--    tenant isolation, duplicate check, and owner preservation.
-- 2. Hardens public.validate_action_before_write() with:
--    a. TG_OP = 'INSERT' vs 'UPDATE' differentiation for staff progress updates.
--    b. Explicit server-side guard preventing ordinary Staff from directly changing status to 'Closed',
--       closed_at, or closed_by.
--    c. Preservation of Manager/Admin closure workflows, scope checks, and verified closure RPCs.

-- ============================================================================
-- 1. Hardened add_action_contributor Function
-- ============================================================================

CREATE OR REPLACE FUNCTION public.add_action_contributor(
  p_action_id UUID,
  p_contributor_profile_id UUID,
  p_notes TEXT DEFAULT ''::TEXT,
  p_added_by UUID DEFAULT NULL::UUID,
  p_added_by_name TEXT DEFAULT ''::TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_org UUID;
  v_action public.actions%ROWTYPE;
  v_target_profile public.profiles%ROWTYPE;
  v_target_role_code VARCHAR(50);
  v_caller_is_admin BOOLEAN := false;
  v_caller_is_mgr BOOLEAN := false;
  v_contributor_id UUID;
  v_actor_name VARCHAR(150);
  v_history_entry JSONB;
BEGIN
  -- Resolve delegator / caller ID
  v_caller_id := COALESCE(p_added_by, auth.uid());
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Authentication required');
  END IF;

  v_caller_org := public.get_my_organization_id();
  v_caller_is_admin := public.is_admin() OR public.is_platform_admin();
  v_caller_is_mgr := public.is_manager();

  SELECT * INTO v_action
  FROM public.actions
  WHERE id = p_action_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action not found');
  END IF;

  -- Verify tenant isolation
  IF v_caller_org IS NOT NULL AND v_action.organization_id != v_caller_org AND NOT public.is_platform_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Cross-tenant operation blocked');
  END IF;

  IF lower(trim(coalesce(v_action.status, ''))) = 'closed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cannot add contributor to closed action');
  END IF;

  -- Caller authority check
  IF NOT (v_caller_is_admin OR v_action.assigned_to = v_caller_id OR v_action.created_by = v_caller_id OR app_private.is_action_participant(p_action_id)) THEN
    IF NOT (v_caller_is_mgr AND public.is_manager_of_scope(v_action.department_id, v_action.site_id)) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Insufficient authority to delegate or forward this action');
    END IF;
  END IF;

  -- Retrieve and validate target profile
  SELECT p.*, r.code INTO v_target_profile
  FROM public.profiles p
  JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = p_contributor_profile_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Target contributor profile not found');
  END IF;

  SELECT r.code INTO v_target_role_code
  FROM public.profiles p
  JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = p_contributor_profile_id;

  -- Tenant check on target
  IF v_caller_org IS NOT NULL AND v_target_profile.organization_id != v_caller_org AND NOT public.is_platform_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Cannot add cross-company contributor');
  END IF;

  -- Target must be active
  IF v_target_profile.is_active IS NOT TRUE OR v_target_profile.status != 'active' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Target user is inactive or pending approval');
  END IF;

  -- Primary owner preservation: Cannot add owner as contributor
  IF v_action.assigned_to = p_contributor_profile_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'User is already the primary owner of this action');
  END IF;

  -- Duplicate check: Cannot add existing contributor
  IF EXISTS (
    SELECT 1 FROM public.action_contributors
    WHERE action_id = p_action_id AND profile_id = p_contributor_profile_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'This user is already a contributor on this action');
  END IF;

  -- Insert contributor record with organization binding
  INSERT INTO public.action_contributors (
    organization_id,
    action_id,
    profile_id,
    added_by,
    notes
  ) VALUES (
    v_action.organization_id,
    p_action_id,
    p_contributor_profile_id,
    v_caller_id,
    p_notes
  )
  RETURNING id INTO v_contributor_id;

  -- Resolve delegator name
  IF p_added_by_name IS NOT NULL AND trim(p_added_by_name) != '' THEN
    v_actor_name := trim(p_added_by_name);
  ELSE
    SELECT full_name INTO v_actor_name
    FROM public.profiles
    WHERE id = v_caller_id;
    IF v_actor_name IS NULL OR trim(v_actor_name) = '' THEN
      v_actor_name := CASE WHEN v_caller_is_mgr THEN 'Manager' ELSE 'Staff' END;
    END IF;
  END IF;

  -- Record audit history
  v_history_entry := jsonb_build_object(
    'date', to_char(now(), 'DD Mon YYYY'),
    'user', v_actor_name,
    'action', 'Contributor Added',
    'notes', format('Forwarded action to %s (%s)%s',
                    v_target_profile.full_name,
                    v_target_role_code,
                    CASE WHEN p_notes != '' THEN ': ' || p_notes ELSE '' END)
  );

  UPDATE public.actions
  SET
    history = COALESCE(history, '[]'::jsonb) || jsonb_build_array(v_history_entry),
    updated_at = now()
  WHERE id = p_action_id;

  RETURN jsonb_build_object(
    'success', true,
    'contributor_id', v_contributor_id,
    'profile_id', p_contributor_profile_id,
    'profile_name', v_target_profile.full_name,
    'role', v_target_role_code
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_action_contributor(UUID, UUID, TEXT, UUID, TEXT) TO authenticated;

-- ============================================================================
-- 2. Hardened validate_action_before_write Trigger Function
-- ============================================================================

CREATE OR REPLACE FUNCTION public.validate_action_before_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
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
      -- Ordinary Staff caller restrictions
      IF TG_OP = 'INSERT' THEN
        RAISE EXCEPTION 'ActionFlow Security Violation: Only active Managers and Company Administrators can create actions.';
      END IF;
      IF TG_OP = 'UPDATE' THEN
        -- Staff can only update actions assigned to them or where they participate
        IF OLD.assigned_to != v_caller_id AND NOT app_private.is_action_participant(OLD.id) THEN
          RAISE EXCEPTION 'ActionFlow Security Violation: Staff can only update actions assigned to them or where they participate.';
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
          -- In organization-wide actions, managers can assign active internal users within the organization
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
$$;
