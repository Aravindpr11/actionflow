-- ============================================================================
-- Migration: 20261110000003_storage_objects_insert_and_request_resubmit.sql
-- Description:
--   1. Harden storage.objects documents_storage_select to inline owner verification
--      so newly inserted objects can be evaluated on RETURNING without statement snapshot delay.
--   2. Implement public.resubmit_request() RPC allowing requesters of rejected requests
--      to address approver feedback and resubmit into the approval workflow.
-- ============================================================================

-- 1. Storage SELECT Policy Update on 'documents' bucket
DROP POLICY IF EXISTS "documents_storage_select" ON storage.objects;
CREATE POLICY "documents_storage_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND split_part(name, '/', 2) != 'requests'
    AND (
      owner = auth.uid()
      OR owner_id = auth.uid()::text
      OR app_private.can_user_access_storage_document(name)
    )
  );

-- 2. Stored Procedure: public.resubmit_request
CREATE OR REPLACE FUNCTION public.resubmit_request(
  p_request_id UUID,
  p_comments TEXT DEFAULT '',
  p_additional_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_profile public.profiles%ROWTYPE;
  v_caller_role VARCHAR(50);
  v_req public.requests%ROWTYPE;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_req FROM public.requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found.';
  END IF;

  -- Only the original requester may resubmit
  IF v_req.created_by != v_caller_id THEN
    RAISE EXCEPTION 'Access Denied: Only the original requester may resubmit this request.';
  END IF;

  -- Can only resubmit if current status is Rejected
  IF v_req.status != 'Rejected' THEN
    RAISE EXCEPTION 'Only rejected requests can be resubmitted. Current status: %', v_req.status;
  END IF;

  SELECT * INTO v_caller_profile FROM public.profiles WHERE id = v_caller_id;
  SELECT r.name INTO v_caller_role FROM public.roles r WHERE r.id = v_caller_profile.role_id;

  -- Reset request status to Pending, clear rejection fields, update additional_notes
  UPDATE public.requests
  SET status = 'Pending',
      rejection_reason = NULL,
      rejected_by = NULL,
      rejected_at = NULL,
      additional_notes = COALESCE(p_additional_notes, additional_notes),
      updated_at = now()
  WHERE id = p_request_id;

  -- Reset all approvers back to Pending
  UPDATE public.request_approvers
  SET status = 'Pending',
      decision_comments = NULL,
      decided_at = NULL
  WHERE request_id = p_request_id;

  -- Record Resubmitted event in request_history
  INSERT INTO public.request_history (
    request_id, organization_id, actor_id, actor_name, actor_role, action, details
  ) VALUES (
    p_request_id, v_req.organization_id, v_caller_id, v_caller_profile.full_name,
    COALESCE(v_caller_role, 'Requester'), 'Resubmitted',
    CASE 
      WHEN p_comments IS NOT NULL AND length(trim(p_comments)) > 0 
      THEN 'Requester responded and resubmitted: ' || trim(p_comments)
      ELSE 'Request resubmitted for approval.'
    END
  );

  RETURN jsonb_build_object(
    'success', true,
    'request_id', p_request_id,
    'status', 'Pending'
  );
END;
$$;

COMMENT ON FUNCTION public.resubmit_request(UUID, TEXT, TEXT)
IS 'Allows original requester to respond to rejection feedback and resubmit request into the approval cycle.';

REVOKE ALL ON FUNCTION public.resubmit_request(UUID, TEXT, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.resubmit_request(UUID, TEXT, TEXT) TO authenticated, service_role;
