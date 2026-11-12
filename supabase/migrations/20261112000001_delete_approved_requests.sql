-- ============================================================================
-- Migration: 20261112000001_delete_approved_requests.sql
-- Description:
--   1. Secure Server-Side Deletion for Approved Requests:
--      - public.delete_approved_request(p_request_id UUID)
--      - Enforces strict role-based authorization:
--        * Requester (Staff or Manager who created the request): Permitted
--        * Scoped Manager (public.is_manager_of_scope): Permitted for requests in scope
--        * Company Admin / Platform Admin: Permitted (governance)
--        * Out-of-scope Managers, Unrelated Staff, Anonymous: STRICTLY FORBIDDEN
--      - Enforces Status Restriction:
--        * STRICTLY Approved requests only.
--        * Pending, Under Review, In Review, Rejected, Completed: REJECTED with error.
--      - Atomicity & Concurrency Safety:
--        * Row-level locking (SELECT ... FOR UPDATE) to eliminate race conditions.
--        * Cascading transactional deletion of child records:
--          request_forwards, request_attachments, request_approvers, request_history.
--      - Request-Specific In-App Notification Cleanup:
--        * Removes notifications matching the exact request display ID and UUID idempotency key.
--        * Preserves all unrelated action and request notifications.
--      - Asynchronous Storage Deletion Queue Architecture:
--        * Creates public.storage_deletion_queue to manage physical object deletion safely.
--        * Inserts ONLY files exclusively referenced by the target request into the queue.
--        * NEVER directly deletes from storage.objects via SQL (eliminates orphaned S3 objects).
--        * NEVER touches shared files or files linked to other records.
--        * Omits internal storage file paths from client-facing RPC return payloads.
--      - Autonomous Server-Side Scheduler (pg_cron & pg_net):
--        * public.get_storage_queue_worker_secret() resolves secret dynamically from Vault.
--        * public.invoke_scheduled_storage_deletion_worker() calls Edge Function asynchronously.
--        * public.register_storage_deletion_cron_job() schedules periodic worker execution
--          without storing secrets in cron job metadata.
--      - Security Hardened:
--        * SECURITY DEFINER with search_path = '' and fully qualified object names.
--        * REVOKE from public, anon; GRANT EXECUTE to authenticated, service_role.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Ensure required extensions exist for autonomous scheduling
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ----------------------------------------------------------------------------
-- 2. Storage Deletion Queue Table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.storage_deletion_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL,
  bucket_id TEXT NOT NULL DEFAULT 'documents',
  file_path TEXT NOT NULL,
  request_id UUID,
  request_display_id TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  attempts INT NOT NULL DEFAULT 0,
  max_attempts INT NOT NULL DEFAULT 5,
  last_error TEXT,
  next_retry_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ,
  created_by UUID
);

COMMENT ON TABLE public.storage_deletion_queue
IS 'Asynchronous queue for safely deleting exclusive physical storage files via the official Supabase Storage API without metadata orphaning.';

-- Indexes for performant queue batch claiming and request tracking
CREATE INDEX IF NOT EXISTS idx_storage_deletion_queue_status_retry
ON public.storage_deletion_queue (status, next_retry_at)
WHERE status IN ('pending', 'failed');

CREATE INDEX IF NOT EXISTS idx_storage_deletion_queue_request
ON public.storage_deletion_queue (request_id);

-- Enable Row Level Security on the queue table
ALTER TABLE public.storage_deletion_queue ENABLE ROW LEVEL SECURITY;

-- Drop prior policies if recreating
DROP POLICY IF EXISTS "storage_deletion_queue_read_org" ON public.storage_deletion_queue;

-- Allow authenticated users to inspect queue status for their organization
CREATE POLICY "storage_deletion_queue_read_org"
ON public.storage_deletion_queue
FOR SELECT
TO authenticated
USING (
  public.is_platform_admin()
  OR (
    organization_id = (SELECT organization_id FROM public.profiles WHERE id = auth.uid())
  )
);

-- Grant appropriate permissions (read-only for authenticated; service_role manages queue)
GRANT SELECT ON public.storage_deletion_queue TO authenticated;
GRANT ALL ON public.storage_deletion_queue TO service_role;

-- ----------------------------------------------------------------------------
-- 3. Queue Batch Claiming Helper (FOR UPDATE SKIP LOCKED)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_storage_deletion_batch(p_batch_size INT DEFAULT 50)
RETURNS TABLE (
  id UUID,
  bucket_id TEXT,
  file_path TEXT,
  attempts INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Strict positive whitelist caller verification (Defense in depth)
  IF NOT (
    (COALESCE(auth.role(), '') = 'service_role')
    OR (auth.role() IS NULL AND session_user IN ('postgres', 'supabase_admin'))
  ) THEN
    RAISE EXCEPTION 'ActionFlow Storage Queue Security Error: Permission denied. Function restricted to service_role.'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH to_claim AS (
    SELECT q.id
    FROM public.storage_deletion_queue q
    WHERE q.status IN ('pending', 'failed')
      AND q.attempts < q.max_attempts
      AND q.next_retry_at <= now()
    ORDER BY q.created_at ASC
    LIMIT p_batch_size
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.storage_deletion_queue u
  SET status = 'processing',
      attempts = u.attempts + 1,
      updated_at = now()
  FROM to_claim tc
  WHERE u.id = tc.id
  RETURNING u.id, u.bucket_id, u.file_path, u.attempts;
END;
$$;

COMMENT ON FUNCTION public.claim_storage_deletion_batch(INT)
IS 'Atomically leases a batch of pending storage deletion jobs using SKIP LOCKED to eliminate duplicate concurrent worker executions.';

REVOKE ALL ON FUNCTION public.claim_storage_deletion_batch(INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_storage_deletion_batch(INT) TO service_role;

-- ----------------------------------------------------------------------------
-- 4. Queue Item Status & Exponential Backoff Completion Helper
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_storage_deletion_item(
  p_id UUID,
  p_success BOOLEAN,
  p_error_message TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_attempts INT;
  v_max_attempts INT;
  v_backoff_seconds INT;
BEGIN
  -- Strict positive whitelist caller verification (Defense in depth)
  IF NOT (
    (COALESCE(auth.role(), '') = 'service_role')
    OR (auth.role() IS NULL AND session_user IN ('postgres', 'supabase_admin'))
  ) THEN
    RAISE EXCEPTION 'ActionFlow Storage Queue Security Error: Permission denied. Function restricted to service_role.'
      USING ERRCODE = '42501';
  END IF;

  IF p_success THEN
    UPDATE public.storage_deletion_queue
    SET status = 'completed',
        processed_at = now(),
        updated_at = now(),
        last_error = NULL
    WHERE id = p_id;
  ELSE
    SELECT attempts, max_attempts
    INTO v_attempts, v_max_attempts
    FROM public.storage_deletion_queue
    WHERE id = p_id;

    -- Exponential backoff: 30s, 60s, 120s, 240s, 480s, capped at 3600s
    v_backoff_seconds := LEAST(30 * (2 ^ GREATEST(COALESCE(v_attempts, 1) - 1, 0)), 3600);

    UPDATE public.storage_deletion_queue
    SET status = CASE WHEN COALESCE(v_attempts, 1) >= COALESCE(v_max_attempts, 5) THEN 'failed' ELSE 'pending' END,
        last_error = p_error_message,
        next_retry_at = now() + (v_backoff_seconds || ' seconds')::interval,
        updated_at = now()
    WHERE id = p_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.complete_storage_deletion_item(UUID, BOOLEAN, TEXT)
IS 'Records success or failure for a storage deletion queue item with calculated exponential backoff.';

REVOKE ALL ON FUNCTION public.complete_storage_deletion_item(UUID, BOOLEAN, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_storage_deletion_item(UUID, BOOLEAN, TEXT) TO service_role;

-- ----------------------------------------------------------------------------
-- 5. Autonomous Scheduler Functions (pg_cron & pg_net)
-- ----------------------------------------------------------------------------

-- Secure Secret Resolver
CREATE OR REPLACE FUNCTION public.get_storage_queue_worker_secret()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault, extensions, pg_temp
AS $$
DECLARE
  v_secret TEXT;
BEGIN
  -- 1. Try Supabase Vault if available
  IF EXISTS (
    SELECT 1 FROM information_schema.views 
    WHERE table_schema = 'vault' AND table_name = 'decrypted_secrets'
  ) THEN
    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'storage_queue_worker_secret'
    LIMIT 1;
  END IF;

  -- 2. Fallback to database setting (for test environments without Vault)
  IF v_secret IS NULL OR length(trim(v_secret)) = 0 THEN
    BEGIN
      v_secret := current_setting('app.settings.storage_queue_worker_secret', true);
    EXCEPTION WHEN OTHERS THEN
      v_secret := NULL;
    END;
  END IF;

  -- 3. Fail closed if not configured or too short (minimum 16 chars)
  IF v_secret IS NULL OR length(trim(v_secret)) < 16 THEN
    RAISE EXCEPTION 'ActionFlow Storage Queue Security Error: Worker secret not found or insufficient (expected secret named "storage_queue_worker_secret" in Vault or app.settings.storage_queue_worker_secret, minimum 16 characters).';
  END IF;

  RETURN trim(v_secret);
END;
$$;

COMMENT ON FUNCTION public.get_storage_queue_worker_secret()
IS 'Internal secure accessor resolving the storage worker secret from Supabase Vault or database configuration. Access restricted to service_role.';

REVOKE ALL ON FUNCTION public.get_storage_queue_worker_secret() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_storage_queue_worker_secret() TO service_role;

-- Autonomous Invoker via pg_net
CREATE OR REPLACE FUNCTION public.invoke_scheduled_storage_deletion_worker(
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
  v_url := NULLIF(trim(p_edge_function_url), '');
  IF v_url IS NULL OR length(v_url) = 0 THEN
    RAISE EXCEPTION 'ActionFlow Storage Queue Security Error: Edge Function URL must be provided.';
  END IF;

  v_secret := public.get_storage_queue_worker_secret();

  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-worker-secret', v_secret
    ),
    body := jsonb_build_object(
      'batch_size', 50
    ),
    timeout_milliseconds := 30000
  ) INTO v_request_id;

  RETURN v_request_id;
END;
$$;

COMMENT ON FUNCTION public.invoke_scheduled_storage_deletion_worker(TEXT)
IS 'Internal stored procedure called by pg_cron to dispatch due storage deletion batch execution via process-storage-deletion-queue Edge Function.';

REVOKE ALL ON FUNCTION public.invoke_scheduled_storage_deletion_worker(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.invoke_scheduled_storage_deletion_worker(TEXT) TO service_role;

-- Idempotent Cron Registration Function
CREATE OR REPLACE FUNCTION public.register_storage_deletion_cron_job(
  p_edge_function_url TEXT,
  p_schedule TEXT DEFAULT '*/10 * * * *'
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_job_id BIGINT;
  v_job_name CONSTANT TEXT := 'actionflow-storage-deletion-queue-10min';
BEGIN
  IF p_edge_function_url IS NULL OR length(trim(p_edge_function_url)) = 0 THEN
    RAISE EXCEPTION 'ActionFlow Storage Queue Security Error: Edge Function URL must be provided for cron registration.';
  END IF;

  -- Unschedule existing job if already registered to prevent duplicate schedules
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = v_job_name) THEN
    PERFORM cron.unschedule(v_job_name);
  END IF;

  -- Register periodic schedule (cadence default: */10 * * * *)
  -- ZERO SECRETS in command text: command invokes public.invoke_scheduled_storage_deletion_worker(url)
  SELECT cron.schedule(
    v_job_name,
    p_schedule,
    format(
      'SELECT public.invoke_scheduled_storage_deletion_worker(%L);',
      trim(p_edge_function_url)
    )
  ) INTO v_job_id;

  RETURN v_job_id;
END;
$$;

COMMENT ON FUNCTION public.register_storage_deletion_cron_job(TEXT, TEXT)
IS 'Idempotently registers or updates the periodic storage deletion queue cron job in pg_cron. Does not store secrets in cron metadata.';

REVOKE ALL ON FUNCTION public.register_storage_deletion_cron_job(TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_storage_deletion_cron_job(TEXT, TEXT) TO service_role;

-- Unregister Cron Job Function
CREATE OR REPLACE FUNCTION public.unregister_storage_deletion_cron_job()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_job_name CONSTANT TEXT := 'actionflow-storage-deletion-queue-10min';
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = v_job_name) THEN
    PERFORM cron.unschedule(v_job_name);
    RETURN TRUE;
  END IF;
  RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION public.unregister_storage_deletion_cron_job()
IS 'Removes the periodic storage deletion queue cron job from pg_cron.';

REVOKE ALL ON FUNCTION public.unregister_storage_deletion_cron_job() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_storage_deletion_cron_job() TO service_role;

-- ----------------------------------------------------------------------------
-- 6. Main Deletion RPC: public.delete_approved_request(UUID)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_approved_request(p_request_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := (SELECT auth.uid());
  v_profile RECORD;
  v_req RECORD;
  v_exclusive_files TEXT[];
  v_queued_files_count INT := 0;
  v_deleted_notifications_count INT := 0;
BEGIN
  -- 1. Authentication check
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: User is not authenticated';
  END IF;

  -- 2. Fetch user profile & active role status from trusted database relations
  SELECT p.id, p.organization_id, p.department_id, p.is_active,
         (r.code IN ('admin', 'company_admin', 'super_admin') OR p.is_primary_admin = TRUE) as is_admin,
         (r.code = 'manager') as is_manager,
         (r.code = 'staff') as is_staff,
         (r.code IN ('platform_admin', 'super_admin') OR public.is_platform_admin()) as is_platform_admin
  INTO v_profile
  FROM public.profiles p
  LEFT JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = v_uid;

  IF NOT FOUND OR NOT v_profile.is_active THEN
    RAISE EXCEPTION 'Forbidden: User profile is not active or does not exist';
  END IF;

  -- 3. Fetch request with row-level lock (FOR UPDATE) to prevent race conditions / duplicate concurrent deletes
  SELECT r.id, r.display_id, r.organization_id, r.department_id, r.site_id, r.created_by, r.status
  INTO v_req
  FROM public.requests r
  WHERE r.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found: %', p_request_id;
  END IF;

  -- 4. Multi-tenant isolation boundary (Platform Admins exempt)
  IF NOT v_profile.is_platform_admin THEN
    IF v_profile.organization_id IS NULL 
       OR v_req.organization_id IS NULL 
       OR v_profile.organization_id IS DISTINCT FROM v_req.organization_id THEN
      RAISE EXCEPTION 'Forbidden: Request does not belong to user organization';
    END IF;
  END IF;

  -- 5. Status constraint: STRICTLY Approved only!
  IF LOWER(TRIM(v_req.status)) NOT IN ('approved') THEN
    RAISE EXCEPTION 'Validation error: Only Approved requests can be permanently deleted (current status: %)', v_req.status;
  END IF;

  -- 6. Role-based authorization check:
  -- Allowed callers:
  -- a) Platform Admin or Organization Admin (within same organization)
  -- b) Scoped Manager (manager with active scope over target department & site)
  -- c) Requester (Staff or Manager who created the request)
  IF NOT (
    v_profile.is_platform_admin
    OR (v_profile.is_admin AND v_profile.organization_id = v_req.organization_id)
    OR (v_profile.is_manager AND public.is_manager_of_scope(v_req.department_id, v_req.site_id))
    OR (v_req.created_by = v_uid)
  ) THEN
    RAISE EXCEPTION 'Forbidden: User is not authorized to delete request %', v_req.display_id;
  END IF;

  -- 7. Identify exclusively owned storage files
  -- Find files attached to this request that are NOT referenced by any other request,
  -- general document, or unresolved document record.
  SELECT COALESCE(array_agg(ra.file_path), ARRAY[]::TEXT[])
  INTO v_exclusive_files
  FROM public.request_attachments ra
  WHERE ra.request_id = p_request_id
    AND ra.file_path IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.request_attachments other_ra 
      WHERE other_ra.request_id <> p_request_id AND other_ra.file_path = ra.file_path
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.documents d 
      WHERE d.file_path = ra.file_path
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.admin_unresolved_documents aud 
      WHERE aud.file_path = ra.file_path
    );

  -- 8. Queue exclusive files for asynchronous Storage API deletion
  -- Note: We NEVER delete directly from storage.objects via SQL, eliminating orphaned
  -- S3/GCS objects and preserving Storage API authorization integrity.
  IF array_length(v_exclusive_files, 1) > 0 THEN
    INSERT INTO public.storage_deletion_queue (
      organization_id,
      bucket_id,
      file_path,
      request_id,
      request_display_id,
      status,
      created_by
    )
    SELECT
      v_req.organization_id,
      'documents',
      f,
      p_request_id,
      v_req.display_id,
      'pending',
      v_uid
    FROM unnest(v_exclusive_files) AS f;

    v_queued_files_count := array_length(v_exclusive_files, 1);
  END IF;

  -- 9. Clean up request-specific notifications cleanly
  -- Isolates strictly by organization, request event types, and exact request identifiers.
  DELETE FROM public.notifications
  WHERE organization_id = v_req.organization_id
    AND event_type IN ('request_submitted', 'request_assigned', 'request_approved', 'request_completed', 'request_rejected', 'request_forwarded')
    AND (
      action_id = v_req.display_id
      OR idempotency_key LIKE 'req\_%\_' || p_request_id::text || '\_%' ESCAPE '\'
      OR idempotency_key LIKE 'req\_%\_' || p_request_id::text ESCAPE '\'
    );
  GET DIAGNOSTICS v_deleted_notifications_count = ROW_COUNT;

  -- 10. Delete child relational records cleanly
  DELETE FROM public.request_forwards WHERE request_id = p_request_id;
  DELETE FROM public.request_attachments WHERE request_id = p_request_id;
  DELETE FROM public.request_approvers WHERE request_id = p_request_id;
  DELETE FROM public.request_history WHERE request_id = p_request_id;

  -- 11. Delete parent request
  DELETE FROM public.requests WHERE id = p_request_id;

  -- 12. Return comprehensive audit summary (Internal storage file paths are OMITTED)
  RETURN jsonb_build_object(
    'success', true,
    'deleted_request_id', p_request_id,
    'deleted_display_id', v_req.display_id,
    'queued_storage_files_count', v_queued_files_count,
    'deleted_notifications_count', v_deleted_notifications_count,
    'storage_cleanup_status', CASE WHEN v_queued_files_count > 0 THEN 'queued' ELSE 'none' END
  );
END;
$$;

COMMENT ON FUNCTION public.delete_approved_request(UUID)
IS 'Permanently deletes an Approved request, queues exclusive storage files for official Storage API removal, cleans up request notifications, and removes dependent records in a safe transaction with strict authorization.';

REVOKE ALL ON FUNCTION public.delete_approved_request(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.delete_approved_request(UUID) TO authenticated, service_role;

COMMIT;
