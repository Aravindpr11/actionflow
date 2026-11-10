-- ============================================================================
-- Migration: 20260922000006_update_approve_and_close_with_assignee_check.sql
-- Description:
--   Updates approve_and_close_action to:
--   1. Use public.is_manager_of_scope() for reliable manager scope validation.
--   2. Check that all required assignees in action_assignees have completed work.
--   3. Record closure audit in history and progress updates.
-- ============================================================================

DROP FUNCTION IF EXISTS public.approve_and_close_action(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.approve_and_close_action(
  p_action_id UUID,
  p_closure_comment TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
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
    RAISE EXCEPTION 'ActionFlow Error: Action not found.';
  END IF;

  IF NOT v_is_platform AND (v_action.organization_id != v_caller_org) THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Cross-organization action closure is prohibited.';
  END IF;

  IF lower(trim(coalesce(v_action.status, ''))) = 'closed' THEN
    RAISE EXCEPTION 'Action is already closed.';
  END IF;

  -- Role Authorization: Manager/Admin only
  IF NOT v_is_platform AND NOT v_is_admin THEN
    IF NOT v_is_mgr OR NOT public.is_manager_of_scope(v_action.department_id, v_action.site_id) THEN
      RAISE EXCEPTION 'Unauthorized: Manager authority required to approve and close actions.';
    END IF;
  END IF;

  -- Overall Progress must be 100%
  IF v_action.percent_complete < 100 THEN
    RAISE EXCEPTION 'Action cannot be closed: operational progress must reach 100%% before closure review.';
  END IF;

  -- Required Assignees Gate:
  -- All required assignees must have completed their assigned work
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
    'event', 'Action Approved & Closed',
    'timestamp', now(),
    'closed_at', now(),
    'closed_by', v_caller_id,
    'closed_by_name', COALESCE(v_actor_name, 'Manager'),
    'closure_comment', COALESCE(p_closure_comment, ''),
    'display', to_char(now(), 'DD Mon YYYY HH24:MI') || ' - Action Formally Closed by ' || COALESCE(v_actor_name, 'Manager') || '. Comment: ' || COALESCE(p_closure_comment, 'Verified')
  );

  UPDATE public.actions
  SET
    status = 'Closed',
    close_date = CURRENT_DATE,
    closed_at = now(),
    closed_by = v_caller_id,
    verified_by = v_caller_id,
    closure_comment = COALESCE(p_closure_comment, ''),
    history = COALESCE(history, '[]'::jsonb) || jsonb_build_array(v_history_entry),
    updated_at = now()
  WHERE id = p_action_id;

  -- Audit record in action_progress_updates
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
$$;

GRANT EXECUTE ON FUNCTION public.approve_and_close_action(UUID, TEXT) TO authenticated;

