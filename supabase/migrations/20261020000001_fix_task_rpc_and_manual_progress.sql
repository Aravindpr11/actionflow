-- ============================================================================
-- Migration: 20261020000001_fix_task_rpc_and_manual_progress.sql
-- Description:
--   1. Fixes PostgREST PGRST202 failure by providing canonical parameter names:
--      - submit_subtask_toggle(p_action_id UUID, p_task_id TEXT, p_completed BOOLEAN, p_reopen_reason TEXT)
--      - submit_subtask_toggle(p_action_uuid UUID, p_task_id TEXT, p_completed BOOLEAN, p_reopen_reason TEXT)
--      - submit_subtask_toggle(p_action_id TEXT, p_task_id TEXT, p_completed BOOLEAN, p_reopen_reason TEXT)
--   2. Enforces Step 25 Progress Rule:
--      - Tasks are an operational checklist; completing/reopening a task DOES NOT
--        overwrite manually reported action percent_complete.
--      - Task completion updates task status and checklist counts while strictly
--        preserving v_action.percent_complete and v_action.status.
--   3. Reloads PostgREST schema cache via NOTIFY pgrst, 'reload schema'.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Drop existing conflicting signatures
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.submit_subtask_toggle(UUID, TEXT, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS public.submit_subtask_toggle(UUID, TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS public.submit_subtask_toggle(TEXT, TEXT, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS public.submit_subtask_toggle(TEXT, TEXT, BOOLEAN);

-- ----------------------------------------------------------------------------
-- 2. Canonical submit_subtask_toggle(UUID, TEXT, BOOLEAN, TEXT)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_subtask_toggle(
  p_action_id UUID,
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
  v_task_assignee_id TEXT;
  v_task_assignee_email TEXT;
  v_task_is_external BOOLEAN;
  v_now_iso TEXT;
  v_now_str TEXT;
BEGIN
  -- 1. Verify caller authentication
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Authentication required.');
  END IF;

  -- 2. Lookup caller profile & active status
  SELECT
    full_name,
    email,
    is_active,
    status
  INTO
    v_caller_name,
    v_caller_email,
    v_caller_active,
    v_caller_status
  FROM public.user_profiles
  WHERE id = v_caller_id;

  IF v_caller_active IS FALSE OR v_caller_status = 'inactive' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Inactive account.');
  END IF;

  -- 3. Lookup target action
  SELECT * INTO v_action
  FROM public.actions
  WHERE id = p_action_id;

  IF v_action.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action not found.');
  END IF;

  -- 4. Check tenant boundary
  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles ur
    WHERE ur.user_id = v_caller_id
      AND ur.role = 'platform_owner'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.user_organizations uo
      WHERE uo.user_id = v_caller_id
        AND uo.organization_id = v_action.organization_id
        AND uo.is_active = TRUE
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Cross-organization access forbidden.');
    END IF;
  END IF;

  -- 5. Determine if caller is manager or action owner
  IF EXISTS (
    SELECT 1 FROM public.user_roles ur
    WHERE ur.user_id = v_caller_id
      AND ur.organization_id = v_action.organization_id
      AND ur.role IN ('company_admin', 'manager', 'platform_owner')
  ) OR v_action.assigned_by_id = v_caller_id
    OR v_action.assigned_to_id = v_caller_id THEN
    v_is_manager := TRUE;
  END IF;

  -- 6. Parse subtasks JSONB
  v_subtasks := COALESCE(v_action.subtasks, '[]'::jsonb);
  IF jsonb_typeof(v_subtasks) <> 'array' THEN
    v_subtasks := '[]'::jsonb;
  END IF;

  v_now_iso := to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  v_now_str := to_char(NOW(), 'DD Mon YYYY');

  FOR v_task IN SELECT * FROM jsonb_array_elements(v_subtasks)
  LOOP
    IF (v_task->>'id') = p_task_id THEN
      v_task_found := TRUE;
      v_task_assignee_id := COALESCE(v_task->>'assigned_staff_id', '');
      v_task_assignee_email := COALESCE(v_task->>'assigned_staff_email', '');
      v_task_is_external := COALESCE((v_task->>'is_external')::boolean, FALSE);

      -- Check authorization
      IF v_is_manager THEN
        v_authorized := TRUE;
      ELSIF v_task_assignee_id <> '' AND v_task_assignee_id = v_caller_id::text THEN
        v_authorized := TRUE;
      ELSIF v_task_assignee_email <> '' AND lower(v_task_assignee_email) = lower(v_caller_email) THEN
        v_authorized := TRUE;
      ELSIF v_task_assignee_id = '' AND v_task_assignee_email = '' AND v_action.assigned_to_id = v_caller_id THEN
        v_authorized := TRUE;
      END IF;

      IF NOT v_authorized THEN
        RETURN jsonb_build_object('success', false, 'error', 'Not authorized to update this task.');
      END IF;

      -- Update task completion and reopen reason
      IF p_completed THEN
        v_task := jsonb_set(v_task, '{status}', '"Completed"'::jsonb);
        v_task := jsonb_set(v_task, '{completed_at}', to_jsonb(v_now_str));
        v_task := jsonb_set(v_task, '{completed_by}', to_jsonb(COALESCE(v_caller_name, 'Staff')));
        v_task := jsonb_set(v_task, '{reopen_reason}', '""'::jsonb);
      ELSE
        v_task := jsonb_set(v_task, '{status}', '"Open"'::jsonb);
        v_task := jsonb_set(v_task, '{completed_at}', '""'::jsonb);
        v_task := jsonb_set(v_task, '{completed_by}', '""'::jsonb);
        IF p_reopen_reason IS NOT NULL AND length(trim(p_reopen_reason)) > 0 THEN
          v_task := jsonb_set(v_task, '{reopen_reason}', to_jsonb(trim(p_reopen_reason)));
        END IF;
      END IF;
    END IF;

    -- Count totals
    v_total_count := v_total_count + 1;
    IF (v_task->>'status') ILIKE 'completed' THEN
      v_completed_count := v_completed_count + 1;
    END IF;

    v_updated_tasks := v_updated_tasks || jsonb_build_array(v_task);
  END LOOP;

  IF NOT v_task_found THEN
    RETURN jsonb_build_object('success', false, 'error', 'Task not found.');
  END IF;

  -- 7. Persist updated subtasks to actions table
  -- STEP 25 BUSINESS RULE: Tasks are a supporting checklist.
  -- Completing or reopening a task DOES NOT overwrite overall percent_complete or overall status!
  UPDATE public.actions
  SET
    subtasks = v_updated_tasks,
    updated_at = NOW()
  WHERE id = v_action.id;

  RETURN jsonb_build_object(
    'success', true,
    'action_id', v_action.id,
    'percent_complete', v_action.percent_complete,
    'completed_tasks', v_completed_count,
    'total_tasks', v_total_count,
    'task_id', p_task_id,
    'task_completed', p_completed,
    'status', v_action.status
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. Compatibility Overload: p_action_uuid UUID (Identical signature to p_action_id; omitted in Postgres)
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- 4. Compatibility Overload: p_action_id TEXT (supports action_number)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_subtask_toggle(
  p_action_id TEXT,
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
  v_uuid UUID;
BEGIN
  IF p_action_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    v_uuid := p_action_id::UUID;
  ELSE
    SELECT id INTO v_uuid
    FROM public.actions
    WHERE action_number = trim(p_action_id)
    LIMIT 1;
  END IF;

  IF v_uuid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action not found.');
  END IF;

  RETURN public.submit_subtask_toggle(
    p_action_id => v_uuid,
    p_task_id => p_task_id,
    p_completed => p_completed,
    p_reopen_reason => p_reopen_reason
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. Permissions
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.submit_subtask_toggle(UUID, TEXT, BOOLEAN, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.submit_subtask_toggle(UUID, TEXT, BOOLEAN, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.submit_subtask_toggle(TEXT, TEXT, BOOLEAN, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.submit_subtask_toggle(TEXT, TEXT, BOOLEAN, TEXT) TO authenticated;

-- Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';

