-- ============================================================================
-- Migration: 20261019000001_action_subtasks_security_hardening.sql
-- Description: Forward hardening for action subtasks security and identifier flexibility:
--   1. Replaces get_action_subtasks(UUID) with strict identity scoping (no display-name bypass).
--   2. Replaces submit_subtask_toggle(UUID, TEXT, BOOLEAN) with strict identity scoping.
--   3. Provides get_action_subtasks(TEXT) overload resolving UUID and action_number with
--      strict tenant boundary enforcement and delegation to the UUID implementation.
--   4. Provides submit_subtask_toggle(TEXT, TEXT, BOOLEAN) overload resolving UUID and
--      action_number with strict tenant boundary enforcement and delegation.
--   5. Provides get_actions_subtasks_batch(UUID[]) and get_actions_subtasks_batch(TEXT[])
--      overloads resolving batch subtasks with full identifier and tenant safety.
--   6. Disambiguates parameter names (p_action_uuid vs p_action_id) so PostgREST
--      uniquely routes JSON string parameters without candidate function conflict.
-- ============================================================================

-- Drop dependent view before dropping functions
DROP VIEW IF EXISTS public.actions_secure CASCADE;

-- Drop historical conflicting function signatures before redefining
DROP FUNCTION IF EXISTS public.get_action_subtasks(UUID);
DROP FUNCTION IF EXISTS public.submit_subtask_toggle(UUID, TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS public.get_actions_subtasks_batch(UUID[]);
DROP FUNCTION IF EXISTS public.get_actions_subtasks_batch(TEXT[]);

-- ----------------------------------------------------------------------------
-- 1. Hardened get_action_subtasks(UUID)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_action_subtasks(
  p_action_uuid UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
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
  v_filtered JSONB := '[]'::jsonb;
  v_task JSONB;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  -- 1. Fetch action record
  SELECT * INTO v_action
  FROM public.actions
  WHERE id = p_action_uuid;

  IF NOT FOUND THEN
    RETURN '[]'::jsonb;
  END IF;

  -- 2. Verify caller has read access to the organization
  IF v_action.organization_id != public.get_my_organization_id() AND NOT public.is_platform_admin() THEN
    RETURN '[]'::jsonb;
  END IF;

  -- 3. Verify caller profile exists and is active
  SELECT full_name, email, is_active, status 
  INTO v_caller_name, v_caller_email, v_caller_active, v_caller_status
  FROM public.profiles
  WHERE id = v_caller_id;

  IF NOT FOUND 
     OR COALESCE(v_caller_active, true) IS FALSE 
     OR (v_caller_status IS NOT NULL AND lower(trim(v_caller_status)) NOT IN ('active', 'enabled'))
  THEN
    RETURN '[]'::jsonb;
  END IF;

  -- 4. Check if caller is manager/admin/creator for this action
  IF public.is_admin() 
     OR public.is_platform_admin() 
     OR (public.is_manager() AND public.is_manager_of_scope(v_action.department_id, v_action.site_id))
     OR (v_action.created_by = v_caller_id)
  THEN
    v_is_manager := TRUE;
  END IF;

  v_subtasks := COALESCE(v_action.subtasks, '[]'::jsonb);

  -- Managers see all subtasks
  IF v_is_manager THEN
    RETURN v_subtasks;
  END IF;

  -- Staff members only see internal tasks strictly assigned to them via ID or Email
  -- (Display-name match alone is deliberately excluded to prevent name-spoofing)
  FOR v_task IN SELECT * FROM jsonb_array_elements(v_subtasks)
  LOOP
    -- External tasks belong strictly to external contractors, never visible to internal staff
    IF (v_task->>'assignee_type' = 'external' OR v_task->>'assigneeType' = 'external') THEN
      CONTINUE;
    END IF;

    IF (v_task->>'assigned_staff_id' IS NOT NULL AND v_task->>'assigned_staff_id' = v_caller_id::text)
       OR (v_task->>'assigned_staff_email' IS NOT NULL AND lower(trim(v_task->>'assigned_staff_email')) = lower(trim(COALESCE(v_caller_email, ''))))
       OR (COALESCE(v_task->>'assigned_staff_id', '') = '' AND COALESCE(v_task->>'assigned_staff_email', '') = '' AND (
             v_action.assigned_to = v_caller_id 
             OR EXISTS (SELECT 1 FROM public.action_assignees aa WHERE aa.action_id = p_action_uuid AND aa.profile_id = v_caller_id)
          ))
    THEN
      v_filtered := v_filtered || jsonb_build_array(v_task);
    END IF;
  END LOOP;

  RETURN v_filtered;
END;
$$;

REVOKE ALL ON FUNCTION public.get_action_subtasks(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_action_subtasks(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- 2. Hardened submit_subtask_toggle(UUID, TEXT, BOOLEAN)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_subtask_toggle(
  p_action_uuid UUID,
  p_task_id TEXT,
  p_completed BOOLEAN
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
      -- Verify strict task assignment authorization (no display-name bypass)
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
        ELSE
          v_task := jsonb_set(v_task, '{status}', '"Open"'::jsonb);
          v_task := jsonb_set(v_task, '{completed_at}', '""'::jsonb);
          v_task := jsonb_set(v_task, '{completed_by}', '""'::jsonb);
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

  UPDATE public.actions
  SET subtasks = v_updated_tasks,
      percent_complete = v_new_percent,
      updated_at = now()
  WHERE id = p_action_uuid;

  RETURN jsonb_build_object(
    'success', true,
    'percent_complete', v_new_percent,
    'completed_tasks', v_completed_count,
    'total_tasks', v_total_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.submit_subtask_toggle(UUID, TEXT, BOOLEAN) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.submit_subtask_toggle(UUID, TEXT, BOOLEAN) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. Stored Function Overload: get_action_subtasks(TEXT)
-- Accepts either UUID string or action_number string. Resolves strictly within tenant.
-- Parameter name is p_action_id, uniquely matched by PostgREST RPC.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_action_subtasks(
  p_action_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_action_uuid UUID;
  v_caller_id UUID;
  v_caller_org_id UUID;
  v_is_plat_admin BOOLEAN;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  IF p_action_id IS NULL OR trim(p_action_id) = '' THEN
    RETURN '[]'::jsonb;
  END IF;

  v_caller_org_id := public.get_my_organization_id();
  v_is_plat_admin := public.is_platform_admin();

  -- Test if input is already a valid UUID
  BEGIN
    v_action_uuid := p_action_id::uuid;
  EXCEPTION WHEN others THEN
    v_action_uuid := NULL;
  END;

  IF v_action_uuid IS NOT NULL THEN
    -- Verify organization boundary
    IF NOT v_is_plat_admin THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.actions 
        WHERE id = v_action_uuid AND organization_id = v_caller_org_id
      ) THEN
        RETURN '[]'::jsonb;
      END IF;
    END IF;
    RETURN public.get_action_subtasks(v_action_uuid);
  END IF;

  -- Otherwise resolve by action_number within the caller's organization
  SELECT id INTO v_action_uuid
  FROM public.actions
  WHERE action_number = trim(p_action_id)
    AND (v_is_plat_admin OR organization_id = v_caller_org_id)
  LIMIT 1;

  IF v_action_uuid IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  RETURN public.get_action_subtasks(v_action_uuid);
END;
$$;

REVOKE ALL ON FUNCTION public.get_action_subtasks(TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_action_subtasks(TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. Stored Procedure Overload: submit_subtask_toggle(TEXT, TEXT, BOOLEAN)
-- Accepts either UUID string or action_number string. Resolves strictly within tenant.
-- Parameter name is p_action_id, uniquely matched by PostgREST RPC.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_subtask_toggle(
  p_action_id TEXT,
  p_task_id TEXT,
  p_completed BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_action_uuid UUID;
  v_caller_id UUID;
  v_caller_org_id UUID;
  v_is_plat_admin BOOLEAN;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Authentication required.');
  END IF;

  IF p_action_id IS NULL OR trim(p_action_id) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action identifier is missing.');
  END IF;

  v_caller_org_id := public.get_my_organization_id();
  v_is_plat_admin := public.is_platform_admin();

  -- Test if input is already a valid UUID
  BEGIN
    v_action_uuid := p_action_id::uuid;
  EXCEPTION WHEN others THEN
    v_action_uuid := NULL;
  END;

  IF v_action_uuid IS NOT NULL THEN
    IF NOT v_is_plat_admin THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.actions 
        WHERE id = v_action_uuid AND organization_id = v_caller_org_id
      ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Cross-organization access denied.');
      END IF;
    END IF;
    RETURN public.submit_subtask_toggle(v_action_uuid, p_task_id, p_completed);
  END IF;

  -- Otherwise resolve by action_number within caller's organization
  SELECT id INTO v_action_uuid
  FROM public.actions
  WHERE action_number = trim(p_action_id)
    AND (v_is_plat_admin OR organization_id = v_caller_org_id)
  LIMIT 1;

  IF v_action_uuid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action not found.');
  END IF;

  RETURN public.submit_subtask_toggle(v_action_uuid, p_task_id, p_completed);
END;
$$;

REVOKE ALL ON FUNCTION public.submit_subtask_toggle(TEXT, TEXT, BOOLEAN) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.submit_subtask_toggle(TEXT, TEXT, BOOLEAN) TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. Stored Function: get_actions_subtasks_batch(UUID[])
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_actions_subtasks_batch(
  p_action_uuids UUID[]
)
RETURNS TABLE (
  action_id UUID,
  subtasks JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF p_action_uuids IS NULL OR array_length(p_action_uuids, 1) = 0 THEN
    RETURN;
  END IF;

  FOREACH v_id IN ARRAY p_action_uuids
  LOOP
    action_id := v_id;
    subtasks := public.get_action_subtasks(v_id);
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.get_actions_subtasks_batch(UUID[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_actions_subtasks_batch(UUID[]) TO authenticated;

-- ----------------------------------------------------------------------------
-- 6. Stored Function Overload: get_actions_subtasks_batch(TEXT[])
-- Accepts TEXT array containing UUID strings or action numbers.
-- Parameter name is p_action_ids, uniquely matched by PostgREST RPC.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_actions_subtasks_batch(
  p_action_ids TEXT[]
)
RETURNS TABLE (
  action_id TEXT,
  subtasks JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_item TEXT;
BEGIN
  IF p_action_ids IS NULL OR array_length(p_action_ids, 1) = 0 THEN
    RETURN;
  END IF;

  FOREACH v_item IN ARRAY p_action_ids
  LOOP
    action_id := v_item;
    subtasks := public.get_action_subtasks(v_item);
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.get_actions_subtasks_batch(TEXT[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_actions_subtasks_batch(TEXT[]) TO authenticated;

-- ----------------------------------------------------------------------------
-- 7. Stored Procedure: submit_external_subtask_toggle
-- Allows external contractors to securely complete or reopen their assigned task
-- via their unguessable access token.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_external_subtask_toggle(
  p_token_hash VARCHAR(64),
  p_task_id TEXT,
  p_completed BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_token public.external_action_tokens%ROWTYPE;
  v_action public.actions%ROWTYPE;
  v_recipient public.external_action_recipients%ROWTYPE;
  v_subtasks JSONB;
  v_updated_tasks JSONB := '[]'::jsonb;
  v_task JSONB;
  v_task_found BOOLEAN := FALSE;
  v_authorized BOOLEAN := FALSE;
  v_total_count INT := 0;
  v_completed_count INT := 0;
  v_new_percent INT := 0;
  v_now_str TEXT;
BEGIN
  IF p_token_hash IS NULL OR trim(p_token_hash) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Access token is missing.');
  END IF;

  IF p_task_id IS NULL OR trim(p_task_id) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Task identifier is missing.');
  END IF;

  -- 1. Validate token
  SELECT * INTO v_token
  FROM public.external_action_tokens
  WHERE token_hash = trim(p_token_hash);

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid access token.');
  END IF;

  IF v_token.is_revoked IS TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Access token has been revoked.');
  END IF;

  IF v_token.expires_at < now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Access token has expired.');
  END IF;

  -- 2. Fetch action and lock
  SELECT * INTO v_action
  FROM public.actions
  WHERE id = v_token.action_id AND organization_id = v_token.organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action record not found.');
  END IF;

  IF v_action.status = 'Closed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action is already closed.');
  END IF;

  -- 3. Fetch recipient
  SELECT * INTO v_recipient
  FROM public.external_action_recipients
  WHERE id = v_token.external_recipient_id;

  IF NOT FOUND OR v_recipient.is_active IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Recipient account is inactive.');
  END IF;

  v_subtasks := COALESCE(v_action.subtasks, '[]'::jsonb);
  v_now_str := to_char(now(), 'DD Mon YYYY');

  FOR v_task IN SELECT * FROM jsonb_array_elements(v_subtasks)
  LOOP
    IF v_task->>'id' = p_task_id THEN
      v_task_found := TRUE;
      -- Verify task assignment belongs to this external contractor
      IF (v_task->>'assignee_type' = 'external' OR v_task->>'assigneeType' = 'external')
         AND (
           (v_task->>'assigned_staff_id' IS NOT NULL AND v_task->>'assigned_staff_id' = v_recipient.id::text)
           OR (v_task->>'assigned_staff_email' IS NOT NULL AND lower(trim(v_task->>'assigned_staff_email')) = lower(trim(v_recipient.email)))
           OR (COALESCE(v_task->>'assigned_staff_id', '') = '' AND COALESCE(v_task->>'assigned_staff_email', '') = '' AND v_action.external_recipient_id = v_recipient.id)
         )
      THEN
        v_authorized := TRUE;
        IF p_completed THEN
          v_task := jsonb_set(v_task, '{status}', '"Completed"'::jsonb);
          v_task := jsonb_set(v_task, '{completed_at}', to_jsonb(v_now_str));
          v_task := jsonb_set(v_task, '{completed_by}', to_jsonb(COALESCE(v_recipient.full_name, 'External Contractor')));
        ELSE
          v_task := jsonb_set(v_task, '{status}', '"Open"'::jsonb);
          v_task := jsonb_set(v_task, '{completed_at}', '""'::jsonb);
          v_task := jsonb_set(v_task, '{completed_by}', '""'::jsonb);
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
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: You are not authorized to update this task.');
  END IF;

  IF v_total_count > 0 THEN
    v_new_percent := round((v_completed_count::numeric / v_total_count::numeric) * 100);
  ELSE
    v_new_percent := v_action.percent_complete;
  END IF;

  UPDATE public.actions
  SET subtasks = v_updated_tasks,
      percent_complete = v_new_percent,
      updated_at = now()
  WHERE id = v_action.id;

  RETURN jsonb_build_object(
    'success', true,
    'percent_complete', v_new_percent,
    'completed_tasks', v_completed_count,
    'total_tasks', v_total_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.submit_external_subtask_toggle(VARCHAR, TEXT, BOOLEAN) FROM public;
GRANT EXECUTE ON FUNCTION public.submit_external_subtask_toggle(VARCHAR, TEXT, BOOLEAN) TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Recreate Secure View: actions_secure
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.actions_secure AS
SELECT
  a.id,
  a.organization_id,
  a.action_number,
  a.title,
  a.description,
  a.action_required,
  a.category,
  a.source,
  a.priority,
  a.status,
  a.percent_complete,
  a.date_raised,
  a.start_date,
  a.target_date,
  a.due_date,
  a.last_follow_up_date,
  a.next_follow_up_date,
  a.close_date,
  a.closed_at,
  a.closed_by,
  a.verified_by,
  a.department_id,
  a.site_id,
  a.team_id,
  a.section_id,
  a.division_id,
  a.created_by,
  a.assigned_to,
  a.recipient_type,
  a.external_recipient_id,
  a.worker_message_subject,
  a.worker_message,
  a.manager_message,
  a.email_reminder_enabled,
  a.attachments,
  a.history,
  a.created_at,
  a.updated_at,
  public.get_action_subtasks(a.id) AS subtasks
FROM public.actions a;

ALTER VIEW public.actions_secure OWNER TO postgres;
GRANT SELECT ON public.actions_secure TO authenticated;

