-- ============================================================================
-- Migration: 20260924000001_external_action_update_and_email_service.sql
-- Description:
--   1. Create public.external_action_tokens table for secure tokenized contractor access.
--   2. Safely resolve public.action_progress_updates.updated_by FK for external actors.
--   3. Create SECURITY DEFINER RPC public.create_or_get_external_action_token for managers.
--   4. Create SECURITY DEFINER RPC public.get_external_action_by_token for contractor portal.
--   5. Create SECURITY DEFINER RPC public.submit_external_action_update for contractor updates.
--   6. Enforce least-privilege grants, safe search_path, and strict tenant isolation.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Table: public.external_action_tokens
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.external_action_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash VARCHAR(64) NOT NULL UNIQUE,
  action_id UUID NOT NULL REFERENCES public.actions(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  external_recipient_id UUID NOT NULL REFERENCES public.external_action_recipients(id) ON DELETE CASCADE,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '7 days'),
  is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  access_count INT NOT NULL DEFAULT 0,
  last_accessed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for fast SHA-256 lookup and tenant filtering
CREATE UNIQUE INDEX IF NOT EXISTS idx_ext_tokens_hash 
  ON public.external_action_tokens(token_hash);

CREATE INDEX IF NOT EXISTS idx_ext_tokens_action 
  ON public.external_action_tokens(action_id);

CREATE INDEX IF NOT EXISTS idx_ext_tokens_org 
  ON public.external_action_tokens(organization_id);

-- Enable RLS on external_action_tokens
ALTER TABLE public.external_action_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ext_tokens_select_manager" ON public.external_action_tokens;
CREATE POLICY "ext_tokens_select_manager" ON public.external_action_tokens
FOR SELECT USING (
  (organization_id = public.get_my_organization_id() AND (public.is_manager() OR public.is_admin()))
  OR public.is_platform_admin()
);

DROP POLICY IF EXISTS "ext_tokens_insert_manager" ON public.external_action_tokens;
CREATE POLICY "ext_tokens_insert_manager" ON public.external_action_tokens
FOR INSERT WITH CHECK (
  (organization_id = public.get_my_organization_id() AND (public.is_manager() OR public.is_admin()))
  OR public.is_platform_admin()
);

DROP POLICY IF EXISTS "ext_tokens_update_manager" ON public.external_action_tokens;
CREATE POLICY "ext_tokens_update_manager" ON public.external_action_tokens
FOR UPDATE USING (
  (organization_id = public.get_my_organization_id() AND (public.is_manager() OR public.is_admin()))
  OR public.is_platform_admin()
) WITH CHECK (
  (organization_id = public.get_my_organization_id() AND (public.is_manager() OR public.is_admin()))
  OR public.is_platform_admin()
);

DROP POLICY IF EXISTS "ext_tokens_delete_manager" ON public.external_action_tokens;
CREATE POLICY "ext_tokens_delete_manager" ON public.external_action_tokens
FOR DELETE USING (
  (organization_id = public.get_my_organization_id() AND (public.is_manager() OR public.is_admin()))
  OR public.is_platform_admin()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.external_action_tokens TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 2. Safely Resolve action_progress_updates.updated_by FK for External Contractors
-- ----------------------------------------------------------------------------
-- Allow updated_by to be NULL for external contractor updates while keeping
-- foreign key constraint on public.profiles(id) for internal users.
ALTER TABLE public.action_progress_updates
  ALTER COLUMN updated_by DROP NOT NULL;

ALTER TABLE public.action_progress_updates
  ADD COLUMN IF NOT EXISTS external_recipient_id UUID REFERENCES public.external_action_recipients(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS updated_by_type VARCHAR(20) NOT NULL DEFAULT 'internal';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_progress_updates_actor'
  ) THEN
    ALTER TABLE public.action_progress_updates
      ADD CONSTRAINT chk_progress_updates_actor
      CHECK (
        (updated_by_type = 'internal' AND updated_by IS NOT NULL) OR
        (updated_by_type = 'external' AND external_recipient_id IS NOT NULL)
      );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_progress_updates_ext_recipient
  ON public.action_progress_updates(external_recipient_id);


-- ----------------------------------------------------------------------------
-- 3. Stored Procedure: create_or_get_external_action_token
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_or_get_external_action_token(
  p_action_id UUID,
  p_token_hash VARCHAR(64),
  p_expires_in_days INT DEFAULT 7
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
  v_expires_at TIMESTAMPTZ;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Authentication required.';
  END IF;

  v_is_platform := public.is_platform_admin();
  v_is_admin := public.is_admin();
  v_is_mgr := public.is_manager();
  v_caller_org := public.get_my_organization_id();

  -- 1. Fetch action
  SELECT * INTO v_action
  FROM public.actions
  WHERE id = p_action_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ActionFlow Error: Action not found.';
  END IF;

  -- 2. Tenant isolation check
  IF NOT v_is_platform AND (v_action.organization_id != v_caller_org) THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Access to action from another organization is forbidden.';
  END IF;

  -- 3. Manager authority and scope check
  IF NOT v_is_platform AND NOT v_is_admin THEN
    IF NOT v_is_mgr OR NOT public.is_manager_of_scope(v_action.department_id, v_action.site_id) THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Manager authority over this department and site scope is required.';
    END IF;
  END IF;

  -- 4. Verify action is external
  IF v_action.recipient_type != 'external' OR v_action.external_recipient_id IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Action does not have an assigned external recipient.';
  END IF;

  -- 5. Calculate expiration
  v_expires_at := now() + (COALESCE(p_expires_in_days, 7) || ' days')::interval;

  -- 6. Insert token record (or refresh if same hash re-submitted)
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
    v_action.external_recipient_id,
    v_caller_id,
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
    'action_id', v_action.id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_or_get_external_action_token TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 4. Stored Procedure: get_external_action_by_token (Public / Contractor)
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
BEGIN
  IF p_token_hash IS NULL OR trim(p_token_hash) = '' THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Access token is missing or empty.');
  END IF;

  -- 1. Find token
  SELECT * INTO v_token
  FROM public.external_action_tokens
  WHERE token_hash = trim(p_token_hash);

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Invalid access token. Please request a valid link from your ActionFlow manager.');
  END IF;

  -- 2. Check revocation
  IF v_token.is_revoked IS TRUE THEN
    RETURN jsonb_build_object(
      'valid', false,
      'error', 'This access link has been revoked. Please request a new link from your ActionFlow manager.',
      'is_revoked', true
    );
  END IF;

  -- 3. Check expiration
  IF v_token.expires_at < now() THEN
    RETURN jsonb_build_object(
      'valid', false,
      'error', 'This access link has expired. Please contact your ActionFlow manager for an updated link.',
      'is_expired', true
    );
  END IF;

  -- 4. Fetch action
  SELECT * INTO v_action
  FROM public.actions
  WHERE id = v_token.action_id AND organization_id = v_token.organization_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Associated action record was not found or has been removed.');
  END IF;

  -- 5. Fetch recipient
  SELECT * INTO v_recipient
  FROM public.external_action_recipients
  WHERE id = v_token.external_recipient_id;

  -- 6. Fetch metadata names
  SELECT name INTO v_dept_name FROM public.departments WHERE id = v_action.department_id;
  SELECT name INTO v_site_name FROM public.sites WHERE id = v_action.site_id;
  SELECT name INTO v_org_name FROM public.organizations WHERE id = v_action.organization_id;

  -- 7. Update access telemetry
  UPDATE public.external_action_tokens
  SET access_count = access_count + 1,
      last_accessed_at = now()
  WHERE token_hash = v_token.token_hash;

  -- 8. Return formatted payload (never exposing manager-only secrets)
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
      'recent_history', COALESCE(v_action.history, '[]'::jsonb)
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

-- Granted to anon for contractor deep-link access
GRANT EXECUTE ON FUNCTION public.get_external_action_by_token TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 5. Stored Procedure: submit_external_action_update (Public / Contractor)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_external_action_update(
  p_token_hash VARCHAR(64),
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
  v_token public.external_action_tokens%ROWTYPE;
  v_action public.actions%ROWTYPE;
  v_recipient public.external_action_recipients%ROWTYPE;
  v_update_id UUID;
  v_history_entry JSONB;
  v_sanitized_status VARCHAR(50);
BEGIN
  -- 1. Input validations
  IF p_token_hash IS NULL OR trim(p_token_hash) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Access token is missing.');
  END IF;

  v_sanitized_status := trim(p_status);

  -- STRICT SERVER-SIDE PRIVILEGE GUARD: Contractors CANNOT close actions
  IF lower(v_sanitized_status) = 'closed' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ActionFlow Security Violation: External contractors cannot approve or close actions. Please set status to Pending Review.'
    );
  END IF;

  IF p_comments IS NULL OR trim(p_comments) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Work update notes / comments are required.');
  END IF;

  IF p_progress < 0 OR p_progress > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Progress percentage must be between 0 and 100.');
  END IF;

  -- 2. Validate token and lock
  SELECT * INTO v_token
  FROM public.external_action_tokens
  WHERE token_hash = trim(p_token_hash)
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid access token.');
  END IF;

  IF v_token.is_revoked IS TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Access token has been revoked.');
  END IF;

  IF v_token.expires_at < now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Access token has expired.');
  END IF;

  -- 3. Fetch action and lock
  SELECT * INTO v_action
  FROM public.actions
  WHERE id = v_token.action_id AND organization_id = v_token.organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action record not found.');
  END IF;

  IF v_action.status = 'Closed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action is already closed.');
  END IF;

  -- 4. Fetch recipient
  SELECT * INTO v_recipient
  FROM public.external_action_recipients
  WHERE id = v_token.external_recipient_id;

  -- 5. Insert granular progress update record
  INSERT INTO public.action_progress_updates (
    organization_id,
    action_id,
    updated_by,
    external_recipient_id,
    updated_by_type,
    update_date,
    progress,
    status,
    comments,
    attachments,
    created_at
  ) VALUES (
    v_action.organization_id,
    v_action.id,
    NULL,
    v_recipient.id,
    'external',
    CURRENT_DATE,
    p_progress,
    v_sanitized_status,
    trim(p_comments),
    COALESCE(p_attachments, '[]'::jsonb),
    now()
  ) RETURNING id INTO v_update_id;

  -- 6. Build audit trail entry in action history
  v_history_entry := jsonb_build_object(
    'id', v_update_id,
    'timestamp', now(),
    'update_date', CURRENT_DATE,
    'actor_type', 'external',
    'actor_name', COALESCE(v_recipient.full_name, 'External Contractor'),
    'external_recipient_id', v_recipient.id,
    'progress', p_progress,
    'status', v_sanitized_status,
    'comment', trim(p_comments),
    'action', format('%s%% (External Update by %s) — %s', p_progress, COALESCE(v_recipient.full_name, 'External Contractor'), trim(p_comments))
  );

  -- 7. Update action record
  UPDATE public.actions
  SET
    percent_complete = p_progress,
    status = v_sanitized_status,
    history = COALESCE(history, '[]'::jsonb) || jsonb_build_array(v_history_entry),
    last_follow_up_date = CURRENT_DATE,
    updated_at = now()
  WHERE id = v_action.id;

  -- 8. Update token usage
  UPDATE public.external_action_tokens
  SET access_count = access_count + 1,
      last_accessed_at = now(),
      updated_at = now()
  WHERE token_hash = v_token.token_hash;

  RETURN jsonb_build_object(
    'success', true,
    'update_id', v_update_id,
    'action_id', v_action.id,
    'progress', p_progress,
    'status', v_sanitized_status,
    'submitted_at', now()
  );
END;
$$;

-- Granted to anon for contractor form submission
GRANT EXECUTE ON FUNCTION public.submit_external_action_update TO anon, authenticated, service_role;

-- Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';
