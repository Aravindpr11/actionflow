-- ============================================================================
-- Migration: 20260922000001_create_action_progress_updates.sql
-- Description:
--   1. Create public.action_progress_updates table for granular work progress tracking.
--   2. Strict RLS: Manager/user can insert progress updates ONLY for actions assigned to them.
--   3. Create public.submit_action_progress_update stored procedure for atomic
--      progress reporting without auto-closing actions.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Table: public.action_progress_updates
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.action_progress_updates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  action_id UUID NOT NULL REFERENCES public.actions(id) ON DELETE CASCADE,
  updated_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  update_date DATE NOT NULL,
  progress INTEGER NOT NULL CHECK (progress >= 0 AND progress <= 100),
  status VARCHAR(50) NOT NULL,
  comments TEXT NOT NULL,
  attachments JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- 2. Indexes for Performance and Auditing
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_progress_updates_action ON public.action_progress_updates(action_id, update_date DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_progress_updates_org ON public.action_progress_updates(organization_id);
CREATE INDEX IF NOT EXISTS idx_progress_updates_updated_by ON public.action_progress_updates(updated_by);

-- ----------------------------------------------------------------------------
-- 3. Row Level Security (RLS)
-- ----------------------------------------------------------------------------
ALTER TABLE public.action_progress_updates ENABLE ROW LEVEL SECURITY;

-- A. SELECT: Authorized users within organization who can view the action
DROP POLICY IF EXISTS "Select action progress updates" ON public.action_progress_updates;
CREATE POLICY "Select action progress updates"
  ON public.action_progress_updates FOR SELECT TO authenticated
  USING (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND EXISTS (
        SELECT 1 FROM public.actions a
        WHERE a.id = action_id
        AND a.organization_id = public.get_my_organization_id()
      )
    )
  );

-- B. INSERT: User can submit update ONLY if assigned to the action
DROP POLICY IF EXISTS "Insert action progress updates" ON public.action_progress_updates;
CREATE POLICY "Insert action progress updates"
  ON public.action_progress_updates FOR INSERT TO authenticated
  WITH CHECK (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND updated_by = auth.uid()
      AND EXISTS (
        SELECT 1 FROM public.actions a
        WHERE a.id = action_id
        AND a.organization_id = public.get_my_organization_id()
        AND a.assigned_to = auth.uid()
      )
    )
  );

-- ----------------------------------------------------------------------------
-- 4. Stored Procedure: Atomic Progress Update Submission
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_action_progress_update(
  p_action_id UUID,
  p_update_date DATE,
  p_progress INT,
  p_status VARCHAR(50),
  p_comments TEXT,
  p_attachments JSONB DEFAULT '[]'::jsonb
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
  v_action public.actions%ROWTYPE;
  v_update_id UUID;
  v_history_entry JSONB;
  v_actor_name VARCHAR(150);
  v_date_str TEXT;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Authentication required.';
  END IF;

  v_is_platform := public.is_platform_admin();
  v_is_admin := public.is_admin();
  v_caller_org := public.get_my_organization_id();

  -- 1. Fetch action and lock row
  SELECT * INTO v_action
  FROM public.actions
  WHERE id = p_action_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ActionFlow Error: Action not found.';
  END IF;

  -- 2. Tenant isolation check
  IF NOT v_is_platform AND (v_action.organization_id != v_caller_org) THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Cross-organization update forbidden.';
  END IF;

  -- 3. Authorization check: Must be assigned to the action (or admin)
  IF NOT v_is_platform AND NOT v_is_admin THEN
    IF v_action.assigned_to IS NULL OR v_action.assigned_to != v_caller_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: You can only update actions assigned to you.';
    END IF;
  END IF;

  -- 4. Validate progress range
  IF p_progress < 0 OR p_progress > 100 THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Progress must be between 0 and 100.';
  END IF;

  -- 5. Validate comments
  IF trim(p_comments) = '' THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Work update comments are required.';
  END IF;

  -- 6. Insert into action_progress_updates
  INSERT INTO public.action_progress_updates (
    organization_id,
    action_id,
    updated_by,
    update_date,
    progress,
    status,
    comments,
    attachments,
    created_at
  ) VALUES (
    v_action.organization_id,
    v_action.id,
    v_caller_id,
    p_update_date,
    p_progress,
    p_status,
    p_comments,
    COALESCE(p_attachments, '[]'::jsonb),
    now()
  ) RETURNING id INTO v_update_id;

  -- 7. Fetch actor name for history
  SELECT full_name INTO v_actor_name
  FROM public.profiles WHERE id = v_caller_id;
  IF v_actor_name IS NULL OR v_actor_name = '' THEN
    v_actor_name := 'Assignee';
  END IF;

  -- 8. Prepare history entry
  v_date_str := to_char(p_update_date, 'DD Mon YYYY');
  v_history_entry := jsonb_build_object(
    'id', v_update_id,
    'timestamp', now(),
    'update_date', p_update_date,
    'actor_id', v_caller_id,
    'actor_name', v_actor_name,
    'progress', p_progress,
    'status', p_status,
    'comment', p_comments,
    'action', format('%s%% — %s — %s', p_progress, v_date_str, p_comments)
  );

  -- 9. Update public.actions:
  -- IMPORTANT: 100% progress must NOT automatically close the action!
  -- Status is updated to what was reported, but never forced to 'Closed'.
  UPDATE public.actions
  SET
    percent_complete = p_progress,
    status = CASE
      WHEN p_status = 'Closed' AND v_action.status != 'Closed' THEN v_action.status
      ELSE p_status
    END,
    history = COALESCE(history, '[]'::jsonb) || jsonb_build_array(v_history_entry),
    last_follow_up_date = CURRENT_DATE,
    updated_at = now()
  WHERE id = v_action.id;

  RETURN jsonb_build_object(
    'success', true,
    'update_id', v_update_id,
    'action_id', v_action.id,
    'progress', p_progress,
    'status', p_status
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. Grants
-- ----------------------------------------------------------------------------
GRANT SELECT, INSERT ON public.action_progress_updates TO authenticated;
GRANT ALL ON public.action_progress_updates TO service_role;
GRANT EXECUTE ON FUNCTION public.submit_action_progress_update TO authenticated;

