-- ============================================================================
-- ActionFlow Action Closure & Permanent Retention Workflow
-- Migration: 20260922000002_action_closure_and_retention_workflow.sql
-- ============================================================================
-- 1. Adds closed_by UUID and closure_comment TEXT to public.actions.
-- 2. Creates SECURITY DEFINER RPC public.approve_and_close_action.
-- 3. Creates SECURITY DEFINER RPC public.request_more_information_on_action.
-- 4. Ensures strict tenant isolation, manager scope authorization, 100% check,
--    and permanent audit history retention.
-- ============================================================================

-- 1. Schema Extensions on public.actions
ALTER TABLE public.actions
  ADD COLUMN IF NOT EXISTS closed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS closure_comment TEXT NOT NULL DEFAULT '';

-- Update status check constraint if present to ensure Closed & Pending Review / Ready for Review
DO $$
BEGIN
  ALTER TABLE public.actions DROP CONSTRAINT IF EXISTS actions_status_check;
  ALTER TABLE public.actions ADD CONSTRAINT actions_status_check
    CHECK (status IN ('Open', 'In Progress', 'Pending Review', 'Ready for Review', 'Overdue', 'Closed', 'Rejected'));
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_actions_closed_by ON public.actions(closed_by);
CREATE INDEX IF NOT EXISTS idx_actions_closed_at ON public.actions(closed_at DESC);

-- ----------------------------------------------------------------------------
-- 2. Stored Procedure: public.approve_and_close_action
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_and_close_action(
  p_action_id UUID,
  p_closure_comment TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_profile RECORD;
  v_action RECORD;
  v_is_platform BOOLEAN := false;
  v_is_company_admin BOOLEAN := false;
  v_is_mgr BOOLEAN := false;
  v_is_scoped BOOLEAN := false;
  v_history_entry JSONB;
  v_result JSONB;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to approve and close actions.';
  END IF;

  -- Fetch caller profile
  SELECT id, organization_id, role, full_name, is_active
  INTO v_caller_profile
  FROM public.profiles
  WHERE id = v_caller_id;

  IF NOT FOUND OR v_caller_profile.is_active IS NOT TRUE THEN
    RAISE EXCEPTION 'Active user profile not found for authenticated caller.';
  END IF;

  -- Check roles
  v_is_platform := public.is_platform_admin();
  v_is_company_admin := (v_caller_profile.role = 'company_admin' OR v_caller_profile.role = 'admin');
  v_is_mgr := (v_caller_profile.role = 'manager');

  -- Staff members CANNOT approve and close actions
  IF NOT v_is_platform AND NOT v_is_company_admin AND NOT v_is_mgr THEN
    RAISE EXCEPTION 'Unauthorized: Only Managers and Admins can approve and close actions.';
  END IF;

  -- Fetch target action
  SELECT *
  INTO v_action
  FROM public.actions
  WHERE id = p_action_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Action with id % not found.', p_action_id;
  END IF;

  -- Multi-tenant enforcement
  IF NOT v_is_platform AND v_action.organization_id <> v_caller_profile.organization_id THEN
    RAISE EXCEPTION 'Cross-organization action closure is prohibited.';
  END IF;

  -- Manager scope authorization check
  IF v_is_mgr AND NOT v_is_company_admin AND NOT v_is_platform THEN
    SELECT EXISTS (
      SELECT 1 FROM public.manager_scopes ms
      WHERE ms.user_id = v_caller_id
        AND ms.department_id = v_action.department_id
        AND ms.site_id = v_action.site_id
    ) INTO v_is_scoped;

    -- If not scoped directly via manager_scopes, check profile matching department/site
    IF NOT v_is_scoped THEN
      RAISE EXCEPTION 'Unauthorized: Manager is not assigned supervisory scope for department % and site %.',
        v_action.department_id, v_action.site_id;
    END IF;
  END IF;

  -- Progress check: Action cannot be closed directly from 0% or without reaching 100%
  IF v_action.percent_complete < 100 THEN
    RAISE EXCEPTION 'Action cannot be closed: operational progress must reach 100%% before closure review.';
  END IF;

  -- Build history event
  v_history_entry := jsonb_build_object(
    'event', 'Action Approved & Closed',
    'closed_by', v_caller_id,
    'closed_by_name', COALESCE(v_caller_profile.full_name, 'Manager'),
    'closure_comment', COALESCE(p_closure_comment, ''),
    'closed_at', now(),
    'progress', 100,
    'status', 'Closed'
  );

  -- Perform update on actions (PERMANENTLY RETAINED, NEVER DELETED)
  UPDATE public.actions
  SET
    status = 'Closed',
    percent_complete = 100,
    closed_at = now(),
    close_date = CURRENT_DATE,
    closed_by = v_caller_id,
    verified_by = v_caller_id,
    closure_comment = COALESCE(p_closure_comment, ''),
    history = COALESCE(history, '[]'::jsonb) || v_history_entry,
    updated_at = now()
  WHERE id = p_action_id;

  -- Record in action_progress_updates audit table
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
    p_action_id,
    v_action.organization_id,
    v_caller_id,
    COALESCE(v_caller_profile.full_name, 'Manager'),
    CURRENT_DATE,
    100,
    'Closed',
    'Action approved and closed. ' || COALESCE(p_closure_comment, ''),
    '[]'::jsonb,
    now()
  );

  -- Select full updated record
  SELECT to_jsonb(a.*) INTO v_result
  FROM public.actions a
  WHERE a.id = p_action_id;

  RETURN v_result;
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. Stored Procedure: public.request_more_information_on_action
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_more_information_on_action(
  p_action_id UUID,
  p_comments TEXT,
  p_target_status TEXT DEFAULT 'In Progress'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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

  SELECT id, organization_id, role, full_name, is_active
  INTO v_caller_profile
  FROM public.profiles
  WHERE id = v_caller_id;

  IF NOT FOUND OR v_caller_profile.is_active IS NOT TRUE THEN
    RAISE EXCEPTION 'Active user profile not found for authenticated caller.';
  END IF;

  v_is_platform := public.is_platform_admin();
  v_is_company_admin := (v_caller_profile.role = 'company_admin' OR v_caller_profile.role = 'admin');
  v_is_mgr := (v_caller_profile.role = 'manager');

  IF NOT v_is_platform AND NOT v_is_company_admin AND NOT v_is_mgr THEN
    RAISE EXCEPTION 'Unauthorized: Only Managers and Admins can request more information on actions.';
  END IF;

  SELECT *
  INTO v_action
  FROM public.actions
  WHERE id = p_action_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Action with id % not found.', p_action_id;
  END IF;

  IF NOT v_is_platform AND v_action.organization_id <> v_caller_profile.organization_id THEN
    RAISE EXCEPTION 'Cross-organization action access is prohibited.';
  END IF;

  IF v_is_mgr AND NOT v_is_company_admin AND NOT v_is_platform THEN
    SELECT EXISTS (
      SELECT 1 FROM public.manager_scopes ms
      WHERE ms.user_id = v_caller_id
        AND ms.department_id = v_action.department_id
        AND ms.site_id = v_action.site_id
    ) INTO v_is_scoped;

    IF NOT v_is_scoped THEN
      RAISE EXCEPTION 'Unauthorized: Manager is not assigned supervisory scope for department % and site %.',
        v_action.department_id, v_action.site_id;
    END IF;
  END IF;

  -- Ensure target status is an active status (NOT Closed)
  v_new_status := COALESCE(NULLIF(trim(p_target_status), ''), 'In Progress');
  IF v_new_status = 'Closed' THEN
    v_new_status := 'In Progress';
  END IF;

  v_history_entry := jsonb_build_object(
    'event', 'Information Requested by Manager',
    'requested_by', v_caller_id,
    'requested_by_name', COALESCE(v_caller_profile.full_name, 'Manager'),
    'comments', trim(p_comments),
    'timestamp', now(),
    'previous_status', v_action.status,
    'new_status', v_new_status
  );

  UPDATE public.actions
  SET
    status = v_new_status,
    manager_message = trim(p_comments),
    history = COALESCE(history, '[]'::jsonb) || v_history_entry,
    updated_at = now()
  WHERE id = p_action_id;

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
    p_action_id,
    v_action.organization_id,
    v_caller_id,
    COALESCE(v_caller_profile.full_name, 'Manager'),
    CURRENT_DATE,
    v_action.percent_complete,
    v_new_status,
    'Manager requested more information: ' || trim(p_comments),
    '[]'::jsonb,
    now()
  );

  SELECT to_jsonb(a.*) INTO v_result
  FROM public.actions a
  WHERE a.id = p_action_id;

  RETURN v_result;
END;
$$;

-- Grant execution to authenticated users
GRANT EXECUTE ON FUNCTION public.approve_and_close_action(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_more_information_on_action(UUID, TEXT, TEXT) TO authenticated;

