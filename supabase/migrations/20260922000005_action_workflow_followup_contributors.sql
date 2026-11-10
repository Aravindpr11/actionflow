-- ============================================================================
-- Migration: 20260922000005_action_workflow_followup_contributors.sql
-- Description:
--   1. Create public.action_follow_ups table for multiple checkpoint dates.
--   2. Create public.action_assignees table for multiple required assignees.
--   3. Create public.action_contributors table for forwarded contributors (no ownership transfer).
--   4. Enhance public.action_progress_updates with role_in_action & contribution_value.
--   5. Create stored procedures for adding follow-ups, contributors, and closing with required assignee verification.
--   6. Enforce strict tenant isolation, manager scopes, and role permissions.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Table: public.action_follow_ups
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.action_follow_ups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  action_id UUID NOT NULL REFERENCES public.actions(id) ON DELETE CASCADE,
  follow_up_date DATE NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  status VARCHAR(50) NOT NULL DEFAULT 'Scheduled' CHECK (status IN ('Scheduled', 'Completed', 'Rescheduled', 'Missed')),
  actual_progress INT,
  created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_action_follow_ups_action ON public.action_follow_ups(action_id, follow_up_date ASC);
CREATE INDEX IF NOT EXISTS idx_action_follow_ups_org ON public.action_follow_ups(organization_id);

ALTER TABLE public.action_follow_ups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select action follow ups" ON public.action_follow_ups;
CREATE POLICY "Select action follow ups"
  ON public.action_follow_ups FOR SELECT TO authenticated
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

DROP POLICY IF EXISTS "Insert action follow ups" ON public.action_follow_ups;
CREATE POLICY "Insert action follow ups"
  ON public.action_follow_ups FOR INSERT TO authenticated
  WITH CHECK (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND (
        public.is_admin()
        OR public.is_manager()
        OR created_by = auth.uid()
      )
    )
  );

-- ----------------------------------------------------------------------------
-- 2. Table: public.action_assignees
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.action_assignees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  action_id UUID NOT NULL REFERENCES public.actions(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  assignment_role VARCHAR(50) NOT NULL DEFAULT 'assignee' CHECK (assignment_role IN ('owner', 'assignee')),
  is_required BOOLEAN NOT NULL DEFAULT true,
  work_completed BOOLEAN NOT NULL DEFAULT false,
  completed_at TIMESTAMPTZ,
  assigned_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_action_assignee UNIQUE (action_id, profile_id)
);

CREATE INDEX IF NOT EXISTS idx_action_assignees_action ON public.action_assignees(action_id);
CREATE INDEX IF NOT EXISTS idx_action_assignees_profile ON public.action_assignees(profile_id);
CREATE INDEX IF NOT EXISTS idx_action_assignees_org ON public.action_assignees(organization_id);

ALTER TABLE public.action_assignees ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select action assignees" ON public.action_assignees;
CREATE POLICY "Select action assignees"
  ON public.action_assignees FOR SELECT TO authenticated
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

DROP POLICY IF EXISTS "Manage action assignees" ON public.action_assignees;
CREATE POLICY "Manage action assignees"
  ON public.action_assignees FOR ALL TO authenticated
  USING (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND (
        public.is_admin()
        OR public.is_manager()
        OR profile_id = auth.uid()
      )
    )
  );

-- ----------------------------------------------------------------------------
-- 3. Table: public.action_contributors
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.action_contributors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  action_id UUID NOT NULL REFERENCES public.actions(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  added_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  notes TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_action_contributor UNIQUE (action_id, profile_id)
);

CREATE INDEX IF NOT EXISTS idx_action_contributors_action ON public.action_contributors(action_id);
CREATE INDEX IF NOT EXISTS idx_action_contributors_profile ON public.action_contributors(profile_id);
CREATE INDEX IF NOT EXISTS idx_action_contributors_org ON public.action_contributors(organization_id);

ALTER TABLE public.action_contributors ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select action contributors" ON public.action_contributors;
CREATE POLICY "Select action contributors"
  ON public.action_contributors FOR SELECT TO authenticated
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

DROP POLICY IF EXISTS "Manage action contributors" ON public.action_contributors;
CREATE POLICY "Manage action contributors"
  ON public.action_contributors FOR ALL TO authenticated
  USING (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND (
        public.is_admin()
        OR public.is_manager()
        OR added_by = auth.uid()
        OR profile_id = auth.uid()
      )
    )
  );

-- ----------------------------------------------------------------------------
-- 4. Alter public.action_progress_updates
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'action_progress_updates'
      AND column_name = 'role_in_action'
  ) THEN
    ALTER TABLE public.action_progress_updates
      ADD COLUMN role_in_action VARCHAR(50) NOT NULL DEFAULT 'assignee';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'action_progress_updates'
      AND column_name = 'contribution_value'
  ) THEN
    ALTER TABLE public.action_progress_updates
      ADD COLUMN contribution_value INTEGER NOT NULL DEFAULT 0;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 5. Stored Procedure: add_action_follow_up
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.add_action_follow_up(
  p_action_id UUID,
  p_follow_up_date DATE,
  p_notes TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_org UUID;
  v_action public.actions%ROWTYPE;
  v_follow_up_id UUID;
  v_actor_name VARCHAR(150);
  v_history_entry JSONB;
  v_next_date DATE;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Authentication required');
  END IF;

  v_caller_org := public.get_my_organization_id();

  SELECT * INTO v_action
  FROM public.actions
  WHERE id = p_action_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action not found');
  END IF;

  IF v_action.organization_id != v_caller_org AND NOT public.is_platform_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Cross-tenant operation blocked');
  END IF;

  IF lower(trim(coalesce(v_action.status, ''))) = 'closed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Closed actions cannot be modified');
  END IF;

  -- Insert follow-up record
  INSERT INTO public.action_follow_ups (
    organization_id,
    action_id,
    follow_up_date,
    notes,
    status,
    created_by,
    created_at
  ) VALUES (
    v_action.organization_id,
    v_action.id,
    p_follow_up_date,
    COALESCE(p_notes, ''),
    'Scheduled',
    v_caller_id,
    now()
  ) RETURNING id INTO v_follow_up_id;

  -- Determine earliest upcoming follow-up date
  SELECT MIN(follow_up_date) INTO v_next_date
  FROM public.action_follow_ups
  WHERE action_id = p_action_id
    AND follow_up_date >= CURRENT_DATE;

  IF v_next_date IS NULL THEN
    v_next_date := p_follow_up_date;
  END IF;

  -- Fetch actor name for audit log
  SELECT full_name INTO v_actor_name
  FROM public.profiles WHERE id = v_caller_id;

  -- Log lifecycle milestone in history
  v_history_entry := jsonb_build_object(
    'event', 'follow_up_scheduled',
    'id', v_follow_up_id,
    'timestamp', now(),
    'date', p_follow_up_date,
    'actor_id', v_caller_id,
    'actor_name', COALESCE(v_actor_name, 'User'),
    'notes', COALESCE(p_notes, ''),
    'display', to_char(now(), 'DD Mon YYYY HH24:MI') || ' - Follow-Up scheduled for ' || to_char(p_follow_up_date, 'DD Mon YYYY') || ' by ' || COALESCE(v_actor_name, 'User')
  );

  UPDATE public.actions
  SET
    next_follow_up_date = v_next_date,
    history = COALESCE(history, '[]'::jsonb) || jsonb_build_array(v_history_entry),
    updated_at = now()
  WHERE id = p_action_id;

  RETURN jsonb_build_object('success', true, 'follow_up_id', v_follow_up_id, 'next_follow_up_date', v_next_date);
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. Stored Procedure: add_action_contributor
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.add_action_contributor(
  p_action_id UUID,
  p_contributor_profile_id UUID,
  p_notes TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
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
  v_caller_id := auth.uid();
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

  IF v_action.organization_id != v_caller_org AND NOT public.is_platform_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Cross-tenant operation blocked');
  END IF;

  IF lower(trim(coalesce(v_action.status, ''))) = 'closed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Closed actions cannot be modified');
  END IF;

  -- Fetch target contributor profile & role
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
  IF v_target_profile.organization_id != v_caller_org AND NOT public.is_platform_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Cannot add cross-company contributor');
  END IF;

  -- Target must be active
  IF v_target_profile.is_active IS NOT TRUE OR v_target_profile.status != 'active' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Target user is inactive or pending approval');
  END IF;

  -- Role Permission Rules:
  -- Staff callers can ONLY add Staff contributors (Staff -> Manager is strictly forbidden)
  IF NOT v_caller_is_admin AND NOT v_caller_is_mgr THEN
    IF v_target_role_code != 'staff' THEN
      RETURN jsonb_build_object('success', false, 'error', 'Permission denied: Staff can only add other Staff as contributors');
    END IF;
  END IF;

  -- Cannot add someone who is already the primary owner
  IF v_action.assigned_to = p_contributor_profile_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'User is already the Owner of this action');
  END IF;

  -- Insert contributor (ignore duplicate)
  INSERT INTO public.action_contributors (
    organization_id,
    action_id,
    profile_id,
    added_by,
    notes,
    created_at
  ) VALUES (
    v_action.organization_id,
    v_action.id,
    p_contributor_profile_id,
    v_caller_id,
    COALESCE(p_notes, ''),
    now()
  )
  ON CONFLICT (action_id, profile_id) DO NOTHING
  RETURNING id INTO v_contributor_id;

  SELECT full_name INTO v_actor_name
  FROM public.profiles WHERE id = v_caller_id;

  -- Log lifecycle milestone (Forwarded / Contributor Added)
  -- Crucial: Owner remains untouched!
  v_history_entry := jsonb_build_object(
    'event', 'contributor_added',
    'timestamp', now(),
    'actor_id', v_caller_id,
    'actor_name', COALESCE(v_actor_name, 'User'),
    'contributor_id', p_contributor_profile_id,
    'contributor_name', v_target_profile.full_name,
    'notes', COALESCE(p_notes, ''),
    'display', to_char(now(), 'DD Mon YYYY HH24:MI') || ' - Contributor Added: ' || v_target_profile.full_name || ' by ' || COALESCE(v_actor_name, 'User') || ' (Owner: ' || COALESCE(v_action.assigned_to, 'Unassigned') || ')'
  );

  UPDATE public.actions
  SET
    history = COALESCE(history, '[]'::jsonb) || jsonb_build_array(v_history_entry),
    updated_at = now()
  WHERE id = p_action_id;

  RETURN jsonb_build_object('success', true, 'contributor_id', v_contributor_id, 'contributor_name', v_target_profile.full_name);
END;
$$;

-- ----------------------------------------------------------------------------
-- 7. Stored Procedure: submit_action_progress_update_v2
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_action_progress_update_v2(
  p_action_id UUID,
  p_update_date DATE,
  p_progress INT,
  p_status VARCHAR(50),
  p_comments TEXT,
  p_contribution_value INT DEFAULT 0,
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
  v_is_mgr BOOLEAN := false;
  v_action public.actions%ROWTYPE;
  v_update_id UUID;
  v_history_entry JSONB;
  v_actor_name VARCHAR(150);
  v_role_in_action VARCHAR(50);
  v_new_status VARCHAR(50);
  v_effective_contribution INT;
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
    RETURN jsonb_build_object('success', false, 'error', 'Closed actions cannot be updated');
  END IF;

  -- Determine role in action & verify participation permission
  IF v_action.assigned_to = v_caller_id THEN
    v_role_in_action := 'owner';
  ELSIF EXISTS (SELECT 1 FROM public.action_assignees WHERE action_id = p_action_id AND profile_id = v_caller_id) THEN
    v_role_in_action := 'assignee';
  ELSIF EXISTS (SELECT 1 FROM public.action_contributors WHERE action_id = p_action_id AND profile_id = v_caller_id) THEN
    v_role_in_action := 'contributor';
  ELSIF v_is_admin OR v_is_platform OR (v_is_mgr AND public.is_manager_of_scope(v_action.department_id, v_action.site_id)) THEN
    v_role_in_action := 'manager';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: You are not an owner, assignee, or contributor for this action');
  END IF;

  -- Validate progress range
  IF p_progress < 0 OR p_progress > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Progress must be between 0 and 100');
  END IF;

  IF trim(p_comments) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Comments are required');
  END IF;

  v_effective_contribution := COALESCE(p_contribution_value, 0);
  IF v_effective_contribution <= 0 THEN
    v_effective_contribution := p_progress - v_action.percent_complete;
    IF v_effective_contribution < 0 THEN
      v_effective_contribution := 0;
    END IF;
  END IF;

  -- Status determination:
  -- 100% NEVER auto-closes the action!
  -- It transitions to 'Ready for Review' if not already closed
  IF p_progress >= 100 THEN
    v_new_status := 'Ready for Review';
  ELSE
    v_new_status := CASE WHEN p_status IN ('Open', 'In Progress') THEN p_status ELSE 'In Progress' END;
  END IF;

  -- If caller is a required assignee and their progress/contribution reached 100%, mark work_completed
  IF v_role_in_action IN ('assignee', 'owner') THEN
    UPDATE public.action_assignees
    SET
      work_completed = (p_progress >= 100),
      completed_at = CASE WHEN p_progress >= 100 THEN now() ELSE completed_at END
    WHERE action_id = p_action_id
      AND profile_id = v_caller_id;
  END IF;

  -- Insert into action_progress_updates
  INSERT INTO public.action_progress_updates (
    organization_id,
    action_id,
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
    v_action.organization_id,
    v_action.id,
    v_caller_id,
    p_update_date,
    p_progress,
    v_new_status,
    p_comments,
    COALESCE(p_attachments, '[]'::jsonb),
    v_role_in_action,
    v_effective_contribution,
    now()
  ) RETURNING id INTO v_update_id;

  SELECT full_name INTO v_actor_name
  FROM public.profiles WHERE id = v_caller_id;

  v_history_entry := jsonb_build_object(
    'event', 'progress_update',
    'id', v_update_id,
    'timestamp', now(),
    'update_date', p_update_date,
    'actor_id', v_caller_id,
    'actor_name', COALESCE(v_actor_name, 'Participant'),
    'role', v_role_in_action,
    'progress', p_progress,
    'contribution', v_effective_contribution,
    'status', v_new_status,
    'comment', p_comments,
    'display', to_char(now(), 'DD Mon YYYY HH24:MI') || ' - ' || COALESCE(v_actor_name, 'Participant') || ' (' || initcap(v_role_in_action) || ') logged progress ' || p_progress || '%: ' || p_comments
  );

  UPDATE public.actions
  SET
    percent_complete = p_progress,
    status = v_new_status,
    history = COALESCE(history, '[]'::jsonb) || jsonb_build_array(v_history_entry),
    updated_at = now()
  WHERE id = p_action_id;

  RETURN jsonb_build_object(
    'success', true,
    'update_id', v_update_id,
    'progress', p_progress,
    'status', v_new_status,
    'role_in_action', v_role_in_action,
    'contribution_value', v_effective_contribution
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. Enhanced Stored Procedure: close_action_verified
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.close_action_verified(
  p_action_id UUID,
  p_closure_comment TEXT
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
    IF NOT v_is_mgr OR NOT public.is_manager_of_scope(v_action.department_id, v_action.site_id) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Manager authority required to approve and close actions');
    END IF;
  END IF;

  -- Overall Progress must be 100%
  IF v_action.percent_complete < 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action cannot be closed before reaching 100% completion');
  END IF;

  -- Required Assignees Gate:
  -- All required assignees must have completed their assigned work
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
$$;

-- ----------------------------------------------------------------------------
-- 9. Grants on tables and functions
-- ----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON public.action_follow_ups TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.action_assignees TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.action_contributors TO authenticated;

GRANT EXECUTE ON FUNCTION public.add_action_follow_up(UUID, DATE, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_action_contributor(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_action_progress_update_v2(UUID, DATE, INT, VARCHAR, TEXT, INT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.close_action_verified(UUID, TEXT) TO authenticated;

