-- ============================================================================
-- Migration: 20261027000001_action_email_reminder_scheduler.sql
-- Description:
--   1. Enables pg_cron and pg_net extensions for autonomous scheduler execution.
--   2. Provides get_actionflow_scheduler_secret() to retrieve credentials securely
--      at runtime from Supabase Vault (vault.decrypted_secrets) or database settings.
--   3. Provides invoke_scheduled_action_reminders() procedure to securely call
--      the send-email Edge Function WITHOUT embedding secrets in cron metadata.
--   4. Implements register_action_reminder_cron_job() with safe 15-minute cadence
--      (*/15 * * * *) and duplicate registration prevention.
--   5. Hardened SECURITY DEFINER permissions: revokes all from PUBLIC, granting
--      access exclusively to service_role.
--
-- STATUS: LOCAL PREPARATION (NOT YET APPLIED TO REMOTE SUPABASE)
-- ============================================================================

-- 1. Ensure required PostgreSQL extensions are enabled
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ----------------------------------------------------------------------------
-- 2. Secure Secret Resolver Function
-- ----------------------------------------------------------------------------
-- Retrieves the scheduler secret dynamically at execution time.
-- Exclusive Source:
--   Supabase Vault (vault.decrypted_secrets where name = 'actionflow_scheduler_secret')
--
-- Security Invariants:
-- 1. Insecure database parameter fallback is permanently removed
--    to prevent ordinary connected database users from reading secrets.
-- 2. Missing or inaccessible Vault secrets fail closed immediately.
-- 3. The secret is NEVER stored in cron.job.command, cron.job_run_details,
--    function signatures, application logs, or client-accessible RPC responses.
CREATE OR REPLACE FUNCTION public.get_actionflow_scheduler_secret()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault, extensions, pg_temp
AS $$
DECLARE
  v_secret TEXT;
BEGIN
  -- Strict Production Vault Access
  IF EXISTS (
    SELECT 1 FROM information_schema.views 
    WHERE table_schema = 'vault' AND table_name = 'decrypted_secrets'
  ) THEN
    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'actionflow_scheduler_secret'
    LIMIT 1;
  ELSE
    RAISE EXCEPTION 'ActionFlow Scheduler Security Error: Supabase Vault extension is not installed or accessible.';
  END IF;

  -- Fail closed: Secret must exist and meet minimum length (16+ chars)
  IF v_secret IS NULL OR length(trim(v_secret)) < 16 THEN
    RAISE EXCEPTION 'ActionFlow Scheduler Security Error: Scheduler secret not found or insufficient in Supabase Vault (expected secret named "actionflow_scheduler_secret", minimum 16 characters).';
  END IF;

  RETURN trim(v_secret);
END;
$$;

COMMENT ON FUNCTION public.get_actionflow_scheduler_secret()
IS 'Internal secure accessor that dynamically resolves the scheduler secret from Supabase Vault or database configuration. Access is restricted to service_role.';

-- Strict Least Privilege Access:
REVOKE ALL ON FUNCTION public.get_actionflow_scheduler_secret() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_actionflow_scheduler_secret() TO service_role;


-- ----------------------------------------------------------------------------
-- 3. Secure Server-to-Server Invoker Function
-- ----------------------------------------------------------------------------
-- Invoked autonomously by pg_cron or an authorized service role to trigger reminder batches.
-- Does NOT take the secret as an argument: retrieves it dynamically from Vault.
CREATE OR REPLACE FUNCTION public.invoke_scheduled_action_reminders(
  p_edge_function_url TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_request_id BIGINT;
  v_url TEXT;
  v_secret TEXT;
BEGIN
  -- Resolve edge function URL from parameter
  v_url := NULLIF(trim(p_edge_function_url), '');

  IF v_url IS NULL OR length(v_url) = 0 THEN
    RAISE EXCEPTION 'ActionFlow Scheduler Security Error: Edge Function URL must be provided.';
  END IF;

  -- Dynamically resolve secret from Supabase Vault in memory
  v_secret := public.get_actionflow_scheduler_secret();

  -- Asynchronously post HTTP request to the send-email Edge Function via pg_net
  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-scheduler-secret', v_secret
    ),
    body := jsonb_build_object(
      'action', 'process_due_reminders'
    ),
    timeout_milliseconds := 30000
  ) INTO v_request_id;

  RETURN v_request_id;
END;
$$;

COMMENT ON FUNCTION public.invoke_scheduled_action_reminders(TEXT)
IS 'Internal stored procedure called by pg_cron to dispatch due reminder batch execution via send-email Edge Function. Retrieves secret dynamically from Vault.';

REVOKE ALL ON FUNCTION public.invoke_scheduled_action_reminders(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invoke_scheduled_action_reminders(TEXT) TO service_role;


-- ----------------------------------------------------------------------------
-- 4. Idempotent Cron Registration & Unregistration Functions
-- ----------------------------------------------------------------------------
-- Safely registers or updates the 15-minute cron job WITHOUT passing secrets to cron.schedule.
CREATE OR REPLACE FUNCTION public.register_action_reminder_cron_job(
  p_edge_function_url TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_job_id BIGINT;
  v_job_name CONSTANT TEXT := 'actionflow-due-reminders-15min';
BEGIN
  IF p_edge_function_url IS NULL OR length(trim(p_edge_function_url)) = 0 THEN
    RAISE EXCEPTION 'ActionFlow Scheduler Security Error: Edge Function URL must be provided for cron registration.';
  END IF;

  -- Unschedule existing job if already registered to prevent duplicate runs
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = v_job_name) THEN
    PERFORM cron.unschedule(v_job_name);
  END IF;

  -- Register 15-minute schedule (cadence: */15 * * * *)
  -- ZERO SECRETS in command text: command invokes public.invoke_scheduled_action_reminders(url)
  SELECT cron.schedule(
    v_job_name,
    '*/15 * * * *',
    format(
      'SELECT public.invoke_scheduled_action_reminders(%L);',
      trim(p_edge_function_url)
    )
  ) INTO v_job_id;

  RETURN v_job_id;
END;
$$;

COMMENT ON FUNCTION public.register_action_reminder_cron_job(TEXT)
IS 'Idempotently registers or updates the 15-minute reminder cron job in pg_cron. Does not store secrets in cron metadata.';

REVOKE ALL ON FUNCTION public.register_action_reminder_cron_job(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_action_reminder_cron_job(TEXT) TO service_role;

-- Unregister helper function to cleanly disable the schedule when needed
CREATE OR REPLACE FUNCTION public.unregister_action_reminder_cron_job()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_job_name CONSTANT TEXT := 'actionflow-due-reminders-15min';
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = v_job_name) THEN
    PERFORM cron.unschedule(v_job_name);
    RETURN TRUE;
  END IF;
  RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION public.unregister_action_reminder_cron_job()
IS 'Cleanly unschedules the actionflow-due-reminders-15min cron job if registered.';

REVOKE ALL ON FUNCTION public.unregister_action_reminder_cron_job() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.unregister_action_reminder_cron_job() TO service_role;

-- ============================================================================
-- 5. Controlled Deployment Reference (DO NOT RUN UNTIL AUTHORIZED)
-- ============================================================================
-- Step A: Configure the scheduler secret in Supabase Vault (Exclusive Production Source):
--   SELECT vault.create_secret('<ACTIONFLOW_SCHEDULER_SECRET>', 'actionflow_scheduler_secret', 'ActionFlow Cron Secret');
--
-- Step B: Register the 15-minute cron job (NO SECRET PASSED):
--   SELECT public.register_action_reminder_cron_job(
--     'https://<PROJECT_REF>.supabase.co/functions/v1/send-email'
--   );
--
-- SCHEDULE CHARACTERISTICS:
-- - Cadence: '*/15 * * * *' (Every 15 minutes at minutes 0, 15, 30, 45)
-- - Timestamp alignment: UTC (database timezone)
-- - Reminders trigger on the first 15-minute boundary after scheduled_at <= now()
-- - Delivery is guaranteed after scheduled_at, never before.
--
-- MONITORING & AUDITING:
-- Inspect registered cron jobs (contains NO secrets):
--   SELECT jobid, schedule, command, nodename, nodeport, database, username, active 
--   FROM cron.job WHERE jobname = 'actionflow-due-reminders-15min';
-- Inspect execution history:
--   SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 20;
-- Inspect HTTP delivery responses:
--   SELECT * FROM net._http_response ORDER BY id DESC LIMIT 20;
-- ============================================================================
