-- ============================================================================
-- Migration: Support Edit Progress Updates and Bidirectional Forwarding
-- File: 20261103000001_support_edit_progress_updates_and_bidirectional_forwarding.sql
-- Description:
--   1. Adds UPDATE RLS policy on public.action_progress_updates to permit authors,
--      assignees, creators, and managers to edit existing progress updates.
--   2. Introduces public.update_action_progress_update RPC for updating an existing
--      update in-place without creating duplicate entries or losing historical audit.
--   3. Updates public.add_action_contributor to support full bidirectional action
--      forwarding (Manager -> Staff, Manager -> Manager, Staff -> Manager, Staff -> Staff).
--   NOTE: DRAFT MIGRATION ONLY - DO NOT DEPLOY WITHOUT EXPLICIT USER APPROVAL.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. RLS Policies on public.action_progress_updates
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Update action progress updates" ON public.action_progress_updates;
CREATE POLICY "Update action progress updates"
  ON public.action_progress_updates FOR UPDATE TO authenticated
  USING (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND (
        updated_by = auth.uid()
        OR public.is_admin()
        OR public.is_manager()
        OR EXISTS (
          SELECT 1 FROM public.actions a
          WHERE a.id = action_id
          AND a.organization_id = public.get_my_organization_id()
          AND (a.assigned_to = auth.uid() OR a.created_by = auth.uid())
        )
      )
    )
  )
  WITH CHECK (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND (
        updated_by = auth.uid()
        OR public.is_admin()
        OR public.is_manager()
        OR EXISTS (
          SELECT 1 FROM public.actions a
          WHERE a.id = action_id
          AND a.organization_id = public.get_my_organization_id()
          AND (a.assigned_to = auth.uid() OR a.created_by = auth.uid())
        )
      )
    )
  );

DROP POLICY IF EXISTS "Insert action progress updates" ON public.action_progress_updates;
CREATE POLICY "Insert action progress updates"
  ON public.action_progress_updates FOR INSERT TO authenticated
  WITH CHECK (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND updated_by = auth.uid()
      AND (
        public.is_admin()
        OR public.is_manager()
        OR EXISTS (
          SELECT 1 FROM public.actions a
          WHERE a.id = action_id
          AND a.organization_id = public.get_my_organization_id()
          AND (
            a.assigned_to = auth.uid()
            OR a.created_by = auth.uid()
            OR EXISTS (
              SELECT 1 FROM public.action_assignees aa
              WHERE aa.action_id = a.id AND aa.profile_id = auth.uid()
            )
            OR EXISTS (
              SELECT 1 FROM public.action_contributors ac
              WHERE ac.action_id = a.id AND ac.profile_id = auth.uid()
            )
          )
        )
      )
    )
  );

-- ----------------------------------------------------------------------------
-- 2. Stored Procedure: update_action_progress_update
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_action_progress_update(
  p_update_id UUID,
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
  v_update public.action_progress_updates%ROWTYPE;
  v_action public.actions%ROWTYPE;
  v_actor_name VARCHAR(150);
  v_history_entry JSONB;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Authentication required');
  END IF;

  v_is_platform := public.is_platform_admin();
  v_is_admin := public.is_admin();
  v_is_mgr := public.is_manager();
  v_caller_org := public.get_my_organization_id();

  SELECT * INTO v_update
  FROM public.action_progress_updates
  WHERE id = p_update_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Progress update record not found');
  END IF;

  SELECT * INTO v_action
  FROM public.actions
  WHERE id = v_update.action_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Parent action not found');
  END IF;

  IF NOT v_is_platform AND (v_action.organization_id != v_caller_org) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Cross-tenant operation blocked');
  END IF;

  IF lower(trim(coalesce(v_action.status, ''))) = 'closed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Closed actions cannot be updated');
  END IF;

  -- Permission: Author, Assignee, Creator, Admin, or Manager
  IF v_update.updated_by != v_caller_id
     AND v_action.assigned_to != v_caller_id
     AND v_action.created_by != v_caller_id
     AND NOT v_is_admin
     AND NOT v_is_platform
     AND NOT v_is_mgr THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Only author, assignee, or manager may edit this update');
  END IF;

  -- Validate progress range
  IF p_progress < 0 OR p_progress > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Progress must be between 0 and 100');
  END IF;

  IF trim(p_comments) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Comments are required');
  END IF;

  -- Update the progress update record
  UPDATE public.action_progress_updates
  SET
    update_date = p_update_date,
    progress = p_progress,
    status = p_status,
    comments = p_comments,
    contribution_value = p_contribution_value,
    attachments = p_attachments
  WHERE id = p_update_id;

  -- Resolve actor name for audit
  SELECT full_name INTO v_actor_name
  FROM public.profiles
  WHERE id = v_caller_id;
  IF v_actor_name IS NULL OR trim(v_actor_name) = '' THEN
    v_actor_name := 'User';
  END IF;

  -- Record audit history entry
  v_history_entry := jsonb_build_object(
    'date', to_char(now(), 'DD Mon YYYY HH24:MI'),
    'user', v_actor_name,
    'action', 'Progress Update Edited',
    'notes', format('Edited update to %s%% (%s)', p_progress, p_status)
  );

  UPDATE public.actions
  SET
    percent_complete = p_progress,
    status = p_status,
    history = COALESCE(history, '[]'::jsonb) || jsonb_build_array(v_history_entry),
    updated_at = now()
  WHERE id = v_action.id;

  RETURN jsonb_build_object(
    'success', true,
    'update_id', p_update_id,
    'action_id', v_action.id,
    'progress', p_progress,
    'status', p_status
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_action_progress_update(UUID, DATE, INT, VARCHAR, TEXT, INT, JSONB) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. Stored Procedure: add_action_contributor (Bidirectional Forwarding)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.add_action_contributor(UUID, UUID, TEXT);
DROP FUNCTION IF EXISTS public.add_action_contributor(UUID, UUID, TEXT, UUID, TEXT);

CREATE OR REPLACE FUNCTION public.add_action_contributor(
  p_action_id UUID,
  p_contributor_profile_id UUID,
  p_notes TEXT DEFAULT '',
  p_added_by UUID DEFAULT NULL,
  p_added_by_name TEXT DEFAULT ''
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
  IF v_caller_org IS NOT NULL AND v_target_profile.organization_id != v_caller_org AND NOT public.is_platform_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Cannot add cross-company contributor');
  END IF;

  -- Target must be active
  IF v_target_profile.is_active IS NOT TRUE OR v_target_profile.status != 'active' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Target user is inactive or pending approval');
  END IF;

  -- BIDIRECTIONAL FORWARDING ENABLED:
  -- Staff, Managers, and Admins can forward actions to any active colleague
  -- (Manager -> Staff, Manager -> Manager, Staff -> Manager, Staff -> Staff).
  -- Note: Contributing does NOT grant permission to close the entire action (only Managers close).

  -- Cannot add current owner as contributor
  IF v_action.assigned_to = p_contributor_profile_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'User is already the primary owner of this action');
  END IF;

  -- Check if already a contributor
  IF EXISTS (
    SELECT 1 FROM public.action_contributors
    WHERE action_id = p_action_id AND profile_id = p_contributor_profile_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'User is already a contributor on this action');
  END IF;

  -- Insert contributor record
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

COMMIT;

