-- ============================================================================
-- Migration: 20261017000001_action_subtasks_security.sql
-- Description: Task-level access control, JSONB filtering, and assignee deletion grant safety.
-- 
-- Analysis of JSONB Access Control Limitation:
-- In PostgreSQL, Row-Level Security (RLS) policies apply at the table row level,
-- not to individual elements within a JSONB array column.
-- When actions.subtasks stores tasks assigned to different users (internal and external),
-- a direct `SELECT subtasks FROM actions` returns the full array to any user permitted
-- to read the parent action row.
--
-- To guarantee task-level confidentiality and authorization on the database tier:
-- 1. `get_action_subtasks(p_action_id UUID)` filters JSONB subtasks for authenticated users:
--    - Managers, Admins, and Action Creators receive all tasks.
--    - Staff users receive only tasks where assigned_staff_id matches their profile ID
--      or email.
-- 2. `get_external_action_by_token(p_token_hash VARCHAR)` is updated to include `subtasks`
--    filtered strictly to the external recipient linked to that token.
-- 3. `submit_subtask_toggle` enforces that only the assigned user (or a manager) can
--    mark a task completed or reopened.
-- 4. Re-affirms `GRANT DELETE ON public.action_assignees TO authenticated;` to prevent
--    the "permission denied for table action_assignees" error in any newly provisioned DB.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Re-affirm DELETE grant on action_assignees for authenticated role
-- ----------------------------------------------------------------------------
GRANT DELETE ON public.action_assignees TO authenticated;
GRANT DELETE ON public.action_contributors TO authenticated;

-- ----------------------------------------------------------------------------
-- 2. Stored Function: get_action_subtasks (Task-level Authorization Filter)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_action_subtasks(
  p_action_id UUID
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
  WHERE id = p_action_id;

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

  IF NOT FOUND OR v_caller_active IS NOT TRUE OR v_caller_status != 'active' THEN
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

  -- Staff members only see internal tasks assigned to them
  FOR v_task IN SELECT * FROM jsonb_array_elements(v_subtasks)
  LOOP
    -- External tasks belong strictly to external contractors, never visible to internal staff
    IF (v_task->>'assignee_type' = 'external' OR v_task->>'assigneeType' = 'external') THEN
      CONTINUE;
    END IF;

    IF (v_task->>'assigned_staff_id' IS NOT NULL AND v_task->>'assigned_staff_id' = v_caller_id::text)
       OR (v_task->>'assigned_staff_email' IS NOT NULL AND lower(trim(v_task->>'assigned_staff_email')) = lower(trim(COALESCE(v_caller_email, ''))))
       OR (v_task->>'assigned_staff' IS NOT NULL AND v_caller_name IS NOT NULL AND lower(trim(v_task->>'assigned_staff')) = lower(trim(v_caller_name)))
       OR (COALESCE(v_task->>'assigned_staff_id', '') = '' AND (
             v_action.assigned_to = v_caller_id 
             OR (v_caller_name IS NOT NULL AND lower(trim(COALESCE(v_task->>'assigned_staff', ''))) IN ('', 'staff', 'assigned staff') AND (
                   v_action.assigned_to = v_caller_id
                   OR EXISTS (SELECT 1 FROM public.action_assignees aa WHERE aa.action_id = p_action_id AND aa.profile_id = v_caller_id)
                ))
          ))
       OR (COALESCE(v_task->>'assigned_staff_id', '') = '' AND EXISTS (
             SELECT 1 FROM public.action_assignees aa WHERE aa.action_id = p_action_id AND aa.profile_id = v_caller_id
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
-- 3. Stored Procedure: submit_subtask_toggle (Enforces Task-level Authorization)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_subtask_toggle(
  p_action_id UUID,
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
  WHERE id = p_action_id;

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

  IF NOT FOUND OR v_caller_active IS NOT TRUE OR v_caller_status != 'active' THEN
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
      -- Verify task assignment authorization
      IF v_is_manager
         OR (v_task->>'assigned_staff_id' IS NOT NULL AND v_task->>'assigned_staff_id' = v_caller_id::text)
         OR (v_task->>'assigned_staff_email' IS NOT NULL AND lower(trim(v_task->>'assigned_staff_email')) = lower(trim(COALESCE(v_caller_email, ''))))
         OR (v_task->>'assigned_staff' IS NOT NULL AND v_caller_name IS NOT NULL AND lower(trim(v_task->>'assigned_staff')) = lower(trim(v_caller_name)))
         OR (COALESCE(v_task->>'assigned_staff_id', '') = '' AND (
               v_action.assigned_to = v_caller_id 
               OR (v_caller_name IS NOT NULL AND lower(trim(COALESCE(v_task->>'assigned_staff', ''))) IN ('', 'staff', 'assigned staff') AND (
                     v_action.assigned_to = v_caller_id
                     OR EXISTS (SELECT 1 FROM public.action_assignees aa WHERE aa.action_id = p_action_id AND aa.profile_id = v_caller_id)
                  ))
            ))
         OR (COALESCE(v_task->>'assigned_staff_id', '') = '' AND EXISTS (
               SELECT 1 FROM public.action_assignees aa WHERE aa.action_id = p_action_id AND aa.profile_id = v_caller_id
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
  WHERE id = p_action_id;

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
-- 4. Update get_external_action_by_token to securely deliver contractor's tasks
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_external_action_by_token(
  p_token_hash VARCHAR(64)
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

  -- 3. Check expiry
  IF v_token.expires_at < now() THEN
    RETURN jsonb_build_object(
      'valid', false,
      'error', 'This access link has expired. Please contact the manager for an updated link.'
    );
  END IF;

  -- 4. Fetch action
  SELECT * INTO v_action
  FROM public.actions
  WHERE id = v_token.action_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Associated action record no longer exists.');
  END IF;

  -- 5. Fetch recipient details
  SELECT * INTO v_recipient
  FROM public.external_action_recipients
  WHERE id = v_token.external_recipient_id;

  IF NOT FOUND OR v_recipient.is_active IS NOT TRUE THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Recipient account is inactive or disabled.');
  END IF;

  -- 6. Resolve department, site, and organization names
  SELECT name INTO v_dept_name
  FROM public.departments
  WHERE id = v_action.department_id;

  SELECT name INTO v_site_name
  FROM public.sites
  WHERE id = v_action.site_id;

  SELECT name INTO v_org_name
  FROM public.organizations
  WHERE id = v_token.organization_id;

  -- 7. Filter subtasks: ONLY include tasks assigned to this external contractor
  v_all_subtasks := COALESCE(v_action.subtasks, '[]'::jsonb);
  FOR v_task IN SELECT * FROM jsonb_array_elements(v_all_subtasks)
  LOOP
    IF (v_task->>'assignee_type' = 'external' OR v_task->>'assigneeType' = 'external')
       AND (
         (v_task->>'assigned_staff_id' IS NOT NULL AND v_task->>'assigned_staff_id' = v_recipient.id::text)
         OR (v_task->>'assigned_staff_email' IS NOT NULL AND lower(v_task->>'assigned_staff_email') = lower(v_recipient.email))
       )
    THEN
      v_contractor_tasks := v_contractor_tasks || jsonb_build_array(v_task);
    END IF;
  END LOOP;

  -- 8. Update access telemetry
  UPDATE public.external_action_tokens
  SET access_count = access_count + 1,
      last_accessed_at = now()
  WHERE token_hash = v_token.token_hash;

  -- 9. Return formatted payload (never exposing manager-only secrets or other users' tasks)
  RETURN jsonb_build_object(
    'valid', true,
    'action', jsonb_build_object(
      'id', v_action.id,
      'action_number', COALESCE(v_action.action_number, v_action.id::text),
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
      'department', COALESCE(v_dept_name, ''),
      'site', COALESCE(v_site_name, ''),
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
$$;

REVOKE ALL ON FUNCTION public.get_external_action_by_token(VARCHAR) FROM public;
GRANT EXECUTE ON FUNCTION public.get_external_action_by_token(VARCHAR) TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5. Trigger: Guard against direct subtasks column manipulation by staff
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_action_subtasks_direct_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
BEGIN
  -- If subtasks column was not modified, allow update
  IF OLD.subtasks IS NOT DISTINCT FROM NEW.subtasks THEN
    RETURN NEW;
  END IF;

  -- Trusted internal execution: when invoked within a trusted SECURITY DEFINER function owned by postgres/superuser (such as submit_subtask_toggle)
  IF CURRENT_USER IN ('postgres', 'supabase_admin') THEN
    RETURN NEW;
  END IF;

  v_caller_id := auth.uid();
  -- Internal database operations / migrations / service_role without user context
  IF v_caller_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Platform admins and company admins can directly modify subtasks (e.g. Add/Edit action forms)
  IF public.is_admin() OR public.is_platform_admin() THEN
    RETURN NEW;
  END IF;

  -- Action creators can modify their own action's subtasks
  IF OLD.created_by = v_caller_id THEN
    RETURN NEW;
  END IF;

  -- Scoped managers can modify subtasks for actions in their department & site
  IF public.is_manager() AND public.is_manager_of_scope(OLD.department_id, OLD.site_id) THEN
    RETURN NEW;
  END IF;

  -- All other callers (staff members, assignees) are forbidden from direct JSONB subtasks updates
  RAISE EXCEPTION 'ActionFlow Security Violation: Direct modification of action subtasks is prohibited for staff members. Task completion must be performed via submit_subtask_toggle.'
    USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_action_subtasks_update ON public.actions;
CREATE TRIGGER trg_guard_action_subtasks_update
  BEFORE UPDATE OF subtasks ON public.actions
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_action_subtasks_direct_update();

-- ----------------------------------------------------------------------------
-- 6. Enforce Column-Level Confidentiality on Raw JSONB subtasks Column
-- ----------------------------------------------------------------------------
-- Ordinary authenticated users must not read raw subtasks directly from actions table.
-- Revoking table-level SELECT and granting permitted columns prevents unauthorized
-- exposure of other people's tasks via direct PostgREST requests (e.g. ?select=subtasks).
REVOKE SELECT ON public.actions FROM authenticated, anon, public;
GRANT SELECT (
  id, organization_id, action_number, title, description, action_required,
  category, source, priority, status, percent_complete, date_raised, start_date,
  target_date, due_date, last_follow_up_date, next_follow_up_date, close_date,
  closed_at, closed_by, verified_by, department_id, site_id, team_id, section_id,
  division_id, created_by, assigned_to, recipient_type, external_recipient_id,
  worker_message_subject, worker_message, manager_message, email_reminder_enabled,
  attachments, history, created_at, updated_at
) ON public.actions TO authenticated;

-- ----------------------------------------------------------------------------
-- 7. Stored Function: get_actions_subtasks_batch (Database-Enforced Batch Subtasks Retrieval)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_actions_subtasks_batch(
  p_action_ids UUID[]
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
  IF p_action_ids IS NULL OR array_length(p_action_ids, 1) = 0 THEN
    RETURN;
  END IF;

  FOREACH v_id IN ARRAY p_action_ids
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
-- 8. Secure View: actions_secure (Database-Enforced Scoped Actions View)
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



