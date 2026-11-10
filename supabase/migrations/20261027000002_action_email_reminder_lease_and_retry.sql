-- ============================================================================
-- Migration: 20261027000002_action_email_reminder_lease_and_retry.sql
-- Description:
--   1. Adds claim lease tracking (claimed_at, claimed_by) to prevent reminders
--      from remaining permanently stuck in 'processing' after worker crashes.
--   2. Adds bounded retry tracking (attempt_count, max_attempts, next_retry_at,
--      last_attempt_at, is_retryable, idempotency_key).
--   3. Upgrades claim_action_email_reminder() with safe stale lease recovery:
--      reclaims jobs only when claim is demonstrably stale (> lease threshold),
--      guaranteeing mutual exclusion, respecting action closures, and enforcing
--      max attempts and scheduled_at <= now().
--
-- STATUS: LOCAL PREPARATION (NOT YET APPLIED TO REMOTE SUPABASE)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Schema Extensions for action_email_reminders
-- ----------------------------------------------------------------------------
ALTER TABLE public.action_email_reminders
  ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS claimed_by TEXT,
  ADD COLUMN IF NOT EXISTS attempt_count INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS max_attempts INT NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS next_retry_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_attempt_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS is_retryable BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

-- ----------------------------------------------------------------------------
-- 2. Performance & Queue Indexes
-- ----------------------------------------------------------------------------
-- Fast lookup index for active and eligible reminder queue items
CREATE INDEX IF NOT EXISTS idx_action_reminders_lease_queue
  ON public.action_email_reminders(status, scheduled_at, next_retry_at)
  WHERE status IN ('pending', 'processing');

CREATE INDEX IF NOT EXISTS idx_action_reminders_claimed_at
  ON public.action_email_reminders(claimed_at)
  WHERE status = 'processing';

-- ----------------------------------------------------------------------------
-- 3. Stored Procedure: claim_action_email_reminder (Safe Recovery & Bounded Claim)
-- ----------------------------------------------------------------------------
-- Drop obsolete 3-argument signature from migration 20260926000001 to prevent
-- PostgreSQL function overloading ambiguity when invoked with default arguments.
DROP FUNCTION IF EXISTS public.claim_action_email_reminder(UUID, UUID, UUID);

CREATE OR REPLACE FUNCTION public.claim_action_email_reminder(
  p_reminder_id UUID,
  p_action_id UUID,
  p_organization_id UUID,
  p_worker_id TEXT DEFAULT NULL,
  p_lease_seconds INT DEFAULT 600 -- Default 10 minutes lease timeout
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_reminder public.action_email_reminders%ROWTYPE;
  v_action public.actions%ROWTYPE;
  v_now TIMESTAMPTZ := now();
  v_stale_threshold TIMESTAMPTZ := v_now - (p_lease_seconds || ' seconds')::INTERVAL;
BEGIN
  -- 1. Verify parent action exists, is open, and has reminders enabled
  SELECT * INTO v_action
  FROM public.actions
  WHERE id = p_action_id AND organization_id = p_organization_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action record not found');
  END IF;

  -- If action is closed or reminders are disabled, cancel the reminder immediately
  IF v_action.status = 'Closed' 
     OR v_action.is_closed IS TRUE 
     OR v_action.percent_complete = 100 
     OR v_action.email_reminder_enabled IS NOT TRUE THEN
    UPDATE public.action_email_reminders
    SET status = 'cancelled',
        updated_at = v_now
    WHERE id = p_reminder_id
      AND organization_id = p_organization_id
      AND status IN ('pending', 'processing');

    RETURN jsonb_build_object(
      'success', false,
      'error', 'Action is closed or email reminders disabled; reminder has been cancelled'
    );
  END IF;

  -- 2. Atomically claim reminder job:
  --    Eligible conditions:
  --    - Belongs to action_id and organization_id
  --    - status NOT IN ('sent', 'cancelled')
  --    - scheduled_at <= now() (INVARIANT: Future reminders CANNOT be claimed)
  --    - attempt_count < max_attempts (INVARIANT: Bounded retry limit)
  --    AND either:
  --      A) status = 'pending' AND (next_retry_at IS NULL OR next_retry_at <= now())
  --      OR
  --      B) status = 'processing' AND COALESCE(claimed_at, updated_at) <= v_stale_threshold
  UPDATE public.action_email_reminders
  SET status = 'processing',
      claimed_at = v_now,
      claimed_by = COALESCE(p_worker_id, 'worker-' || gen_random_uuid()::text),
      attempt_count = attempt_count + 1,
      last_attempt_at = v_now,
      updated_at = v_now
  WHERE id = p_reminder_id
    AND action_id = p_action_id
    AND organization_id = p_organization_id
    AND status NOT IN ('sent', 'cancelled')
    AND scheduled_at <= v_now
    AND attempt_count < max_attempts
    AND (
      (status = 'pending' AND (next_retry_at IS NULL OR next_retry_at <= v_now))
      OR
      (status = 'processing' AND COALESCE(claimed_at, updated_at) <= v_stale_threshold)
    )
  RETURNING * INTO v_reminder;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Reminder job is not eligible for claim (already claimed, active lease held, not due, retry delayed, max attempts reached, or completed)'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'reminder', row_to_json(v_reminder),
    'is_recovery', (v_reminder.attempt_count > 1),
    'attempt', v_reminder.attempt_count,
    'claimed_by', v_reminder.claimed_by
  );
END;
$$;

COMMENT ON FUNCTION public.claim_action_email_reminder(UUID, UUID, UUID, TEXT, INT)
IS 'Atomically claims a pending reminder or recovers a stale processing claim (> lease timeout). Enforces bounded retries, scheduled_at, and closed-action cancellation.';

REVOKE ALL ON FUNCTION public.claim_action_email_reminder(UUID, UUID, UUID, TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_action_email_reminder(UUID, UUID, UUID, TEXT, INT) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

