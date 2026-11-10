-- ============================================================================
-- Migration: Enhance add_action_contributor Actor Tracking
-- File: 20261102000002_enhance_add_action_contributor_actor_tracking.sql
-- Description:
--   1. Enhances public.add_action_contributor to support optional explicit
--      delegator parameters (p_added_by, p_added_by_name) while retaining 100%
--      backward compatibility with existing 3-argument callers (p_action_id,
--      p_contributor_profile_id, p_notes).
--   2. Ensures accurate lifecycle history logs and contributor attribution
--      across staff forwarding and manager delegations.
-- ============================================================================

BEGIN;

-- Drop legacy 3-parameter signature to prevent function overload ambiguity
-- (the new 5-parameter version provides default values for parameters 4 and 5)
DROP FUNCTION IF EXISTS public.add_action_contributor(UUID, UUID, TEXT);

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

  -- Resolve delegator display name
  IF p_added_by_name IS NOT NULL AND trim(p_added_by_name) != '' THEN
    v_actor_name := trim(p_added_by_name);
  ELSE
    SELECT full_name INTO v_actor_name
    FROM public.profiles WHERE id = v_caller_id;
  END IF;

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
    'display', to_char(now(), 'DD Mon YYYY HH24:MI') || ' - Contributor Added: ' || v_target_profile.full_name || ' by ' || COALESCE(v_actor_name, 'User') || ' (Owner: ' || COALESCE(v_action.assigned_to::text, 'Unassigned') || ')'
  );

  UPDATE public.actions
  SET
    history = COALESCE(history, '[]'::jsonb) || jsonb_build_array(v_history_entry),
    updated_at = now()
  WHERE id = p_action_id;

  RETURN jsonb_build_object(
    'success', true,
    'contributor_id', v_contributor_id,
    'contributor_name', v_target_profile.full_name,
    'added_by', v_caller_id,
    'added_by_name', COALESCE(v_actor_name, 'User')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_action_contributor(UUID, UUID, TEXT, UUID, TEXT) TO authenticated, service_role;

COMMIT;

