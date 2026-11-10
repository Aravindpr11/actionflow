-- ============================================================================
-- Migration: 20260926000001_action_email_reminder_delivery_security.sql
-- Description:
--   1. Enhances create_or_get_external_action_token to support explicit
--      external_recipient_id and service_role callers.
--   2. Provides atomic reminder claim function with schedule & tenant validation.
--   3. Strictly enforces organization tenant boundary and least privilege.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Enhanced Stored Procedure: create_or_get_external_action_token
-- ----------------------------------------------------------------------------
-- Drop obsolete 3-argument signature from earlier migration to avoid function name ambiguity
DROP FUNCTION IF EXISTS public.create_or_get_external_action_token(UUID, VARCHAR, INT);

CREATE OR REPLACE FUNCTION public.create_or_get_external_action_token(
  p_action_id UUID,
  p_token_hash VARCHAR(64),
  p_expires_in_days INT DEFAULT 7,
  p_external_recipient_id UUID DEFAULT NULL
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
  v_is_service_role BOOLEAN := false;
  v_action public.actions%ROWTYPE;
  v_recipient public.external_action_recipients%ROWTYPE;
  v_target_recipient_id UUID;
  v_expires_at TIMESTAMPTZ;
BEGIN
  v_caller_id := auth.uid();
  v_is_service_role := (current_user = 'service_role' OR auth.role() = 'service_role');

  IF v_caller_id IS NULL AND NOT v_is_service_role THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Authentication required.';
  END IF;

  -- 1. Fetch action
  SELECT * INTO v_action
  FROM public.actions
  WHERE id = p_action_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ActionFlow Error: Action not found.';
  END IF;

  -- 2. Tenant isolation check (for authenticated non-service users)
  IF v_caller_id IS NOT NULL THEN
    v_is_platform := public.is_platform_admin();
    v_is_admin := public.is_admin();
    v_is_mgr := public.is_manager();
    v_caller_org := public.get_my_organization_id();

    IF NOT v_is_platform AND (v_action.organization_id != v_caller_org) THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Access to action from another organization is forbidden.';
    END IF;

    -- Manager authority and scope check
    IF NOT v_is_platform AND NOT v_is_admin THEN
      IF NOT v_is_mgr OR NOT public.is_manager_of_scope(v_action.department_id, v_action.site_id) THEN
        RAISE EXCEPTION 'ActionFlow Security Violation: Manager authority over this department and site scope is required.';
      END IF;
    END IF;
  END IF;

  -- 3. Determine target external recipient
  v_target_recipient_id := COALESCE(p_external_recipient_id, v_action.external_recipient_id);
  IF v_target_recipient_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Action does not have an assigned or specified external recipient.';
  END IF;

  -- Verify external recipient belongs to the same organization and is active
  SELECT * INTO v_recipient
  FROM public.external_action_recipients
  WHERE id = v_target_recipient_id;

  IF NOT FOUND OR v_recipient.organization_id != v_action.organization_id THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: External recipient does not belong to this organization.';
  END IF;

  IF v_recipient.is_active IS NOT TRUE THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: External recipient is inactive.';
  END IF;

  -- 4. Calculate expiration
  v_expires_at := now() + (COALESCE(p_expires_in_days, 7) || ' days')::interval;

  -- 5. Insert or refresh token record
  INSERT INTO public.external_action_tokens (
    token_hash,
    action_id,
    organization_id,
    external_recipient_id,
    created_by,
    expires_at,
    is_revoked,
    created_at,
    updated_at
  ) VALUES (
    trim(p_token_hash),
    v_action.id,
    v_action.organization_id,
    v_recipient.id,
    COALESCE(v_caller_id, v_action.created_by),
    v_expires_at,
    FALSE,
    now(),
    now()
  )
  ON CONFLICT (token_hash) DO UPDATE
  SET expires_at = v_expires_at,
      is_revoked = FALSE,
      updated_at = now();

  RETURN jsonb_build_object(
    'success', true,
    'token_hash', trim(p_token_hash),
    'expires_at', v_expires_at,
    'action_id', v_action.id,
    'external_recipient_id', v_recipient.id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_or_get_external_action_token(UUID, VARCHAR, INT, UUID) TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 2. Stored Procedure: claim_action_email_reminder (Atomic Worker Claim)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_action_email_reminder(
  p_reminder_id UUID,
  p_action_id UUID,
  p_organization_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_reminder public.action_email_reminders%ROWTYPE;
  v_action public.actions%ROWTYPE;
BEGIN
  -- 1. Verify action is not closed and has reminders enabled
  SELECT * INTO v_action
  FROM public.actions
  WHERE id = p_action_id AND organization_id = p_organization_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action record not found');
  END IF;

  IF v_action.status = 'Closed' OR v_action.email_reminder_enabled IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action is closed or email reminders disabled');
  END IF;

  -- 2. Atomically claim reminder job if pending and due
  UPDATE public.action_email_reminders
  SET status = 'processing',
      updated_at = now()
  WHERE id = p_reminder_id
    AND action_id = p_action_id
    AND organization_id = p_organization_id
    AND status = 'pending'
    AND scheduled_at <= now()
  RETURNING * INTO v_reminder;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Reminder job is not pending, not due, or already claimed');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'reminder', row_to_json(v_reminder)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_action_email_reminder TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. Reload schema cache for PostgREST
-- ----------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';
