-- ============================================================================
-- Migration: 20260923000001_add_start_date_to_actions.sql
-- Description:
--   1. Add start_date DATE column to public.actions.
--   2. Add performance index on start_date.
--   3. Backfill existing actions with date_raised if start_date is NULL.
--   4. Update validation trigger to sync/preserve start_date.
--   5. Reload schema cache for PostgREST.
-- ============================================================================

-- 1. Add start_date column if not exists
ALTER TABLE public.actions ADD COLUMN IF NOT EXISTS start_date DATE;

-- 2. Create index on start_date
CREATE INDEX IF NOT EXISTS idx_actions_start_date ON public.actions(start_date);

-- 3. Populate existing rows where start_date is NULL
UPDATE public.actions
SET start_date = date_raised
WHERE start_date IS NULL AND date_raised IS NOT NULL;

-- 4. Update the trigger to handle start_date
CREATE OR REPLACE FUNCTION public.fn_validate_action_before_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
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

  -- Date synchronizations
  NEW.created_date := COALESCE(NEW.created_date, NEW.date_raised, CURRENT_DATE);
  NEW.date_raised := COALESCE(NEW.date_raised, NEW.created_date, CURRENT_DATE);
  NEW.start_date := COALESCE(NEW.start_date, NEW.date_raised, CURRENT_DATE);
  NEW.due_date := COALESCE(NEW.due_date, NEW.target_date);
  NEW.target_date := COALESCE(NEW.target_date, NEW.due_date);

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

  -- E. Manager Scope Enforcement
  IF v_is_mgr AND NOT v_is_company_admin AND NOT v_is_platform THEN
    IF NOT public.is_manager_of_scope(NEW.department_id, NEW.site_id) THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: You do not have manager authority over this department and site scope.';
    END IF;
  END IF;

  -- F. Assignee Validation (if assigned_to is specified)
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

  -- G. Auto-maintain history log
  IF TG_OP = 'INSERT' THEN
    IF NEW.history IS NULL OR jsonb_array_length(NEW.history) = 0 THEN
      NEW.history := jsonb_build_array(
        jsonb_build_object(
          'timestamp', now(),
          'action', 'Action created',
          'actor_id', v_caller_id,
          'status', NEW.status
        )
      );
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.updated_at := now();
    IF NEW.status IS DISTINCT FROM OLD.status OR NEW.percent_complete IS DISTINCT FROM OLD.percent_complete THEN
      NEW.history := COALESCE(OLD.history, '[]'::jsonb) || jsonb_build_object(
        'timestamp', now(),
        'action', format('Status changed to %s (%s%%)', NEW.status, NEW.percent_complete),
        'actor_id', v_caller_id,
        'old_status', OLD.status,
        'new_status', NEW.status,
        'old_percent', OLD.percent_complete,
        'new_percent', NEW.percent_complete
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- 5. Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';

