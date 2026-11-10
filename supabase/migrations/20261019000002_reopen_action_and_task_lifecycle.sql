-- ============================================================================
-- Migration: 20261019000002_reopen_action_and_task_lifecycle.sql
-- Description:
--   1. Implements public.reopen_action(UUID, TEXT) and public.reopen_action(TEXT, TEXT)
--      which transitions an action back to 'In Progress', resets closure metadata,
--      records the mandatory reason, actor, and timestamp in history and progress updates,
--      and verifies manager/admin authorization.
--   2. Enhances public.submit_subtask_toggle to accept optional p_reopen_reason TEXT.
--      When a task is reopened:
--        - Resets task status to 'Open' and records reopen_reason.
--        - Automatically reverts an action from 'Pending Review', 'Ready for Review',
--          'Completed', or 'Closed' back to 'In Progress' (since pending work exists).
--        - Recalculates overall action progress: round((completed / total) * 100).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Stored Function: public.reopen_action(UUID, TEXT)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.reopen_action(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.reopen_action(
  p_action_uuid UUID,
  p_reason TEXT
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
    RAISE EXCEPTION 'ActionFlow Security Violation: Cross-organization action modification is prohibited.';
  END IF;

  -- Role Authorization: Manager, Admin, or Creator only (Staff cannot reopen formal lifecycle state)
  IF NOT v_is_platform AND NOT v_is_admin THEN
    IF NOT (v_is_mgr AND public.is_manager_of_scope(v_action.department_id, v_action.site_id))
       AND (v_action.created_by != v_caller_id)
    THEN
      RAISE EXCEPTION 'Unauthorized: Manager, Admin, or Creator authority required to reopen this action.';
    END IF;
  END IF;

  SELECT full_name INTO v_actor_name
  FROM public.profiles WHERE id = v_caller_id;

  -- Recalculate percent if tasks exist
  v_subtasks := COALESCE(v_action.subtasks, '[]'::jsonb);
  FOR v_task IN SELECT * FROM jsonb_array_elements(v_subtasks)
  LOOP
    v_total_tasks := v_total_tasks + 1;
    IF (v_task->>'status') = 'Completed' THEN
      v_completed_tasks := v_completed_tasks + 1;
    END IF;
  END LOOP;

  IF v_total_tasks > 0 THEN
    v_calculated_percent := round((v_completed_tasks::numeric / v_total_tasks::numeric) * 100);
  ELSE
    v_calculated_percent := v_action.percent_complete;
  END IF;

  v_history_entry := jsonb_build_object(
    'event', 'Action Reopened',
    'timestamp', now(),
    'reopened_by', v_caller_id,
    'reopened_by_name', COALESCE(v_actor_name, 'Manager'),
    'reason', trim(p_reason),
    'previous_status', v_action.status,
    'status', 'In Progress',
    'display', to_char(now(), 'DD Mon YYYY HH24:MI') || ' - Action Reopened by ' || COALESCE(v_actor_name, 'Manager') || '. Reason: ' || trim(p_reason)
  );

  UPDATE public.actions
  SET
    status = 'In Progress',
    percent_complete = v_calculated_percent,
    closed_at = NULL,
    close_date = NULL,
    closed_by = NULL,
    verified_by = NULL,
    closure_comment = '',
    history = COALESCE(history, '[]'::jsonb) || v_history_entry,
    updated_at = now()
  WHERE id = p_action_uuid;

  -- Insert audit progress update record
  INSERT INTO public.action_progress_updates (
    action_id,
    organization_id,
    updated_by,
    updated_by_name,
    update_date,
    progress,
    status,
    comments,
    attachments,
    created_at
  ) VALUES (
    p_action_uuid,
    v_action.organization_id,
    v_caller_id,
    COALESCE(v_actor_name, 'Manager'),
    CURRENT_DATE,
    v_calculated_percent,
    'In Progress',
    'Action Reopened: ' || trim(p_reason),
    '[]'::jsonb,
    now()
  );

  SELECT to_jsonb(a.*) INTO v_result
  FROM public.actions a
  WHERE a.id = p_action_uuid;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.reopen_action(UUID, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.reopen_action(UUID, TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- 2. Stored Function Overload: public.reopen_action(TEXT, TEXT)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.reopen_action(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.reopen_action(
  p_action_id TEXT,
  p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_uuid UUID;
  v_caller_org UUID;
  v_is_platform BOOLEAN := false;
BEGIN
  v_caller_org := public.get_my_organization_id();
  v_is_platform := public.is_platform_admin();

  IF p_action_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    v_uuid := p_action_id::uuid;
  ELSE
    SELECT id INTO v_uuid
    FROM public.actions
    WHERE action_number = trim(p_action_id)
      AND (organization_id = v_caller_org OR v_is_platform)
    LIMIT 1;
  END IF;

  IF v_uuid IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Error: Action not found.';
  END IF;

  RETURN public.reopen_action(v_uuid, p_reason);
END;
$$;

REVOKE ALL ON FUNCTION public.reopen_action(TEXT, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.reopen_action(TEXT, TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. Enhance submit_subtask_toggle to support optional p_reopen_reason and status reset
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.submit_subtask_toggle(UUID, TEXT, BOOLEAN, TEXT);

CREATE OR REPLACE FUNCTION public.submit_subtask_toggle(
  p_action_uuid UUID,
  p_task_id TEXT,
  p_completed BOOLEAN,
  p_reopen_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_action public.actions%ROWTYPE;
  v_caller_id UUID;
  v_caller_name TEXT;
  v_caller_email TEXT;
  v_caller_active BOOLEAN;
  v_caller_status TEXT;
  v_is_manager BOOLEAN := FALSE;
  v_subtasks JSONB;
  v_updated_tasks JSONB := '[]'::jsonb;
  v_task JSONB;
  v_task_found BOOLEAN := FALSE;
  v_authorized BOOLEAN := FALSE;
  v_total_count INT := 0;
  v_completed_count INT := 0;
  v_new_percent INT := 0;
  v_now_str TEXT;
  v_next_status TEXT;
  v_history_entry JSONB;
  v_next_history JSONB;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Authentication required.');
  END IF;

  SELECT * INTO v_action
  FROM public.actions
  WHERE id = p_action_uuid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action not found.');
  END IF;

  IF v_action.organization_id != public.get_my_organization_id() AND NOT public.is_platform_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cross-organization access denied.');
  END IF;

  SELECT full_name, email, is_active, status 
  INTO v_caller_name, v_caller_email, v_caller_active, v_caller_status
  FROM public.profiles
  WHERE id = v_caller_id;

  IF NOT FOUND 
     OR COALESCE(v_caller_active, true) IS FALSE 
     OR (v_caller_status IS NOT NULL AND lower(trim(v_caller_status)) NOT IN ('active', 'enabled'))
  THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Account is inactive or suspended.');
  END IF;

  IF public.is_admin() 
     OR public.is_platform_admin() 
     OR (public.is_manager() AND public.is_manager_of_scope(v_action.department_id, v_action.site_id))
     OR (v_action.created_by = v_caller_id)
  THEN
    v_is_manager := TRUE;
  END IF;

  v_subtasks := COALESCE(v_action.subtasks, '[]'::jsonb);
  v_now_str := to_char(now(), 'DD Mon YYYY');

  FOR v_task IN SELECT * FROM jsonb_array_elements(v_subtasks)
  LOOP
    IF v_task->>'id' = p_task_id THEN
      v_task_found := TRUE;
      IF v_is_manager
         OR (v_task->>'assigned_staff_id' IS NOT NULL AND v_task->>'assigned_staff_id' = v_caller_id::text)
         OR (v_task->>'assigned_staff_email' IS NOT NULL AND lower(trim(v_task->>'assigned_staff_email')) = lower(trim(COALESCE(v_caller_email, ''))))
         OR (COALESCE(v_task->>'assigned_staff_id', '') = '' AND COALESCE(v_task->>'assigned_staff_email', '') = '' AND (
               v_action.assigned_to = v_caller_id 
               OR EXISTS (SELECT 1 FROM public.action_assignees aa WHERE aa.action_id = p_action_uuid AND aa.profile_id = v_caller_id)
            ))
      THEN
        v_authorized := TRUE;
        IF p_completed THEN
          v_task := jsonb_set(v_task, '{status}', '"Completed"'::jsonb);
          v_task := jsonb_set(v_task, '{completed_at}', to_jsonb(v_now_str));
          v_task := jsonb_set(v_task, '{completed_by}', to_jsonb(COALESCE(v_caller_name, 'Staff Member')));
          v_task := jsonb_set(v_task, '{reopen_reason}', '""'::jsonb);
        ELSE
          v_task := jsonb_set(v_task, '{status}', '"Open"'::jsonb);
          v_task := jsonb_set(v_task, '{completed_at}', '""'::jsonb);
          v_task := jsonb_set(v_task, '{completed_by}', '""'::jsonb);
          IF p_reopen_reason IS NOT NULL AND trim(p_reopen_reason) != '' THEN
            v_task := jsonb_set(v_task, '{reopen_reason}', to_jsonb(trim(p_reopen_reason)));
          END IF;
        END IF;
      END IF;
    END IF;

    v_total_count := v_total_count + 1;
    IF (v_task->>'status') = 'Completed' THEN
      v_completed_count := v_completed_count + 1;
    END IF;

    v_updated_tasks := v_updated_tasks || jsonb_build_array(v_task);
  END LOOP;

  IF NOT v_task_found THEN
    RETURN jsonb_build_object('success', false, 'error', 'Task not found.');
  END IF;

  IF NOT v_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: You are not authorized to complete or reopen this task.');
  END IF;

  IF v_total_count > 0 THEN
    v_new_percent := round((v_completed_count::numeric / v_total_count::numeric) * 100);
  ELSE
    v_new_percent := v_action.percent_complete;
  END IF;

  v_next_status := v_action.status;
  v_next_history := COALESCE(v_action.history, '[]'::jsonb);

  -- If reopening an incomplete task and action was in review or closed, transition action status back to In Progress
  IF NOT p_completed AND v_action.status IN ('Pending Review', 'Ready for Review', 'Completed', 'Closed') THEN
    v_next_status := 'In Progress';
    v_history_entry := jsonb_build_object(
      'event', 'Task Reopened',
      'task_id', p_task_id,
      'timestamp', now(),
      'reopened_by', v_caller_id,
      'reopened_by_name', COALESCE(v_caller_name, 'Manager'),
      'reason', COALESCE(trim(p_reopen_reason), 'Task returned for rework'),
      'status', 'In Progress',
      'display', v_now_str || ' - Task reopened by ' || COALESCE(v_caller_name, 'Manager') || COALESCE(': ' || trim(p_reopen_reason), '')
    );
    v_next_history := v_next_history || v_history_entry;
  END IF;

  UPDATE public.actions
  SET subtasks = v_updated_tasks,
      percent_complete = v_new_percent,
      status = v_next_status,
      history = v_next_history,
      closed_at = CASE WHEN v_next_status = 'In Progress' THEN NULL ELSE closed_at END,
      close_date = CASE WHEN v_next_status = 'In Progress' THEN NULL ELSE close_date END,
      closed_by = CASE WHEN v_next_status = 'In Progress' THEN NULL ELSE closed_by END,
      updated_at = now()
  WHERE id = p_action_uuid;

  RETURN jsonb_build_object(
    'success', true,
    'percent_complete', v_new_percent,
    'completed_tasks', v_completed_count,
    'total_tasks', v_total_count,
    'action_status', v_next_status
  );
END;
$$;

REVOKE ALL ON FUNCTION public.submit_subtask_toggle(UUID, TEXT, BOOLEAN, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.submit_subtask_toggle(UUID, TEXT, BOOLEAN, TEXT) TO authenticated;
