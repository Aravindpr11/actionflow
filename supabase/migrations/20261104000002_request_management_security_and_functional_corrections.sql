-- ============================================================================
-- Migration: 20261104000002_request_management_security_and_functional_corrections.sql
-- Description:
--   Security & Authorization Hardening for ActionFlow Request Management:
--   1. Manager Visibility: Restricts request SELECT visibility to active manager
--      scopes (department_id + site_id) via public.is_manager_of_scope.
--   2. Storage Security: Adds public.can_user_access_storage_request helper and
--      storage.objects policy for request attachments under <org_id>/requests/...,
--      ensuring participants (creator, approver, forwardee, scoped manager, admin)
--      can download while blocking unauthorized cross-tenant/cross-scope access.
--   3. Request Completion: Hardens public.complete_request RPC with strict
--      caller identity checks, restricting completion authority to the requester,
--      designated approvers, scoped managers, and company admins.
--   4. Request Forwarding: Hardens public.forward_request RPC to verify caller
--      organization membership and view/forward authority on the target request.
--
-- IMPORTANT NOTICE:
--   As per repository change control policies, this migration must NOT be executed
--   automatically on remote environments. It is tested on local PostgreSQL Docker
--   and must be reviewed before deployment to production Supabase.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Storage Access Helper for Request Attachments
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_user_access_storage_request(p_file_path TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_org_id TEXT := split_part(p_file_path, '/', 1);
  v_folder TEXT := split_part(p_file_path, '/', 2);
  v_profile RECORD;
  v_req RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN FALSE;
  END IF;

  -- 1. Verify user profile & active status in organization
  SELECT p.id, p.organization_id::text as org_id, p.is_active,
         (r.code IN ('admin', 'company_admin', 'super_admin') OR p.is_primary_admin = TRUE) as is_admin,
         (r.code = 'manager') as is_manager
  INTO v_profile
  FROM public.profiles p
  LEFT JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = v_uid;

  IF NOT FOUND OR NOT v_profile.is_active THEN
    RETURN FALSE;
  END IF;

  -- Tenant boundary check
  IF NOT public.check_user_in_org(v_org_id) THEN
    RETURN FALSE;
  END IF;

  -- 2. Company Admins have full access within their organization
  IF v_profile.is_admin THEN
    RETURN TRUE;
  END IF;

  -- 3. Lookup attachment metadata linked to request
  SELECT r.id as request_id, r.department_id, r.site_id, r.created_by, ra.uploaded_by
  INTO v_req
  FROM public.request_attachments ra
  JOIN public.requests r ON ra.request_id = r.id
  WHERE ra.file_path = p_file_path
    AND ra.organization_id::text = v_org_id;

  -- If not yet linked to requests table (e.g. upload in flight), allow object owner
  IF NOT FOUND THEN
    RETURN EXISTS (
      SELECT 1 FROM storage.objects
      WHERE name = p_file_path
        AND bucket_id = 'documents'
        AND (owner = v_uid OR owner_id = v_uid::text)
    );
  END IF;

  -- 4. Uploader / Submitter
  IF v_req.created_by = v_uid OR v_req.uploaded_by = v_uid THEN
    RETURN TRUE;
  END IF;

  -- 5. Designated Approver
  IF EXISTS (
    SELECT 1 FROM public.request_approvers
    WHERE request_id = v_req.request_id AND approver_id = v_uid
  ) THEN
    RETURN TRUE;
  END IF;

  -- 6. Explicit Forward Recipient
  IF EXISTS (
    SELECT 1 FROM public.request_forwards
    WHERE request_id = v_req.request_id AND to_user_id = v_uid
  ) THEN
    RETURN TRUE;
  END IF;

  -- 7. Scoped Manager
  IF v_profile.is_manager AND public.is_manager_of_scope(v_req.department_id, v_req.site_id) THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.can_user_access_storage_request(TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.can_user_access_storage_request(TEXT) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. Permissive Storage RLS Policy for Request Attachments
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "request_attachments_storage_select" ON storage.objects;
CREATE POLICY "request_attachments_storage_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND split_part(name, '/', 2) = 'requests'
    AND public.can_user_access_storage_request(name)
  );

-- ----------------------------------------------------------------------------
-- 3. Hardened Request Multi-Tenant SELECT Policy (Manager Scope Enforcement)
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Requests multi-tenant select policy" ON public.requests;
CREATE POLICY "Requests multi-tenant select policy"
  ON public.requests FOR SELECT TO authenticated
  USING (
    organization_id = (SELECT organization_id FROM public.profiles WHERE id = auth.uid() AND is_active = true)
    AND (
      -- 1. Requester / Creator
      created_by = auth.uid()
      -- 2. Designated Approver
      OR EXISTS (
        SELECT 1 FROM public.request_approvers
        WHERE request_id = requests.id AND approver_id = auth.uid()
      )
      -- 3. Authorized Forward Recipient
      OR EXISTS (
        SELECT 1 FROM public.request_forwards
        WHERE request_id = requests.id AND to_user_id = auth.uid()
      )
      -- 4. Company Admins / Platform Admins (Organization-wide)
      OR (
        EXISTS (
          SELECT 1 FROM public.profiles p
          JOIN public.roles r ON p.role_id = r.id
          WHERE p.id = auth.uid()
            AND (r.code IN ('admin', 'company_admin', 'super_admin') OR p.is_primary_admin = true)
        )
      )
      -- 5. Managers: Strictly constrained to active Department & Site scopes
      OR (
        EXISTS (
          SELECT 1 FROM public.profiles p
          JOIN public.roles r ON p.role_id = r.id
          WHERE p.id = auth.uid() AND r.code = 'manager'
        )
        AND public.is_manager_of_scope(requests.department_id, requests.site_id)
      )
    )
  );

-- ----------------------------------------------------------------------------
-- 4. Hardened Stored Procedure: complete_request
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_request(
  p_request_id UUID,
  p_notes TEXT DEFAULT ''
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
  v_is_authorized BOOLEAN := FALSE;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_req FROM public.requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found.';
  END IF;

  SELECT * INTO v_caller_profile FROM public.profiles WHERE id = v_caller_id;
  IF NOT FOUND OR v_caller_profile.is_active IS NOT TRUE THEN
    RAISE EXCEPTION 'Active user profile not found.';
  END IF;
  SELECT r.code INTO v_caller_role FROM public.roles r WHERE r.id = v_caller_profile.role_id;

  -- 1. Organization boundary check
  IF v_caller_profile.organization_id != v_req.organization_id THEN
    RAISE EXCEPTION 'Cross-organization request completion is prohibited.';
  END IF;

  -- 2. State validation
  IF v_req.status = 'Completed' THEN
    RAISE EXCEPTION 'Request is already marked as Completed.';
  END IF;

  IF v_req.status != 'Approved' THEN
    RAISE EXCEPTION 'Only Approved requests can be marked as Completed. Current status: %', v_req.status;
  END IF;

  -- 3. Authorization check:
  -- Authorized callers:
  -- a. Original Submitter / Requester
  -- b. Designated Approver on this request
  -- c. Company Admin / Platform Admin
  -- d. Manager with active supervisory scope over the request's department & site
  -- Explicitly DENIED: Forwarded recipients, unrelated staff, out-of-scope managers
  IF v_req.created_by = v_caller_id THEN
    v_is_authorized := TRUE;
  ELSIF EXISTS (SELECT 1 FROM public.request_approvers WHERE request_id = p_request_id AND approver_id = v_caller_id) THEN
    v_is_authorized := TRUE;
  ELSIF v_caller_role IN ('admin', 'company_admin', 'super_admin') OR v_caller_profile.is_primary_admin = TRUE THEN
    v_is_authorized := TRUE;
  ELSIF v_caller_role = 'manager' AND public.is_manager_of_scope(v_req.department_id, v_req.site_id) THEN
    v_is_authorized := TRUE;
  END IF;

  IF NOT v_is_authorized THEN
    RAISE EXCEPTION 'Access Denied: You do not have authorization to mark this request as completed.';
  END IF;

  -- 4. State transition
  UPDATE public.requests
  SET status = 'Completed',
      completed_at = now(),
      completed_by = v_caller_id,
      updated_at = now()
  WHERE id = p_request_id;

  -- 5. Audit history
  INSERT INTO public.request_history (
    request_id,
    organization_id,
    actor_id,
    actor_name,
    actor_role,
    action,
    details
  ) VALUES (
    p_request_id,
    v_req.organization_id,
    v_caller_id,
    v_caller_profile.full_name,
    COALESCE(v_caller_role, 'User'),
    'Completed',
    'Work marked as Completed.' || CASE WHEN length(trim(p_notes)) > 0 THEN ' Notes: ' || p_notes ELSE '' END
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. Hardened Stored Procedure: forward_request
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.forward_request(
  p_request_id UUID,
  p_to_user_id UUID,
  p_notes TEXT DEFAULT ''
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
  v_recipient_profile public.profiles%ROWTYPE;
  v_req public.requests%ROWTYPE;
  v_is_authorized BOOLEAN := FALSE;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_req FROM public.requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found.';
  END IF;

  SELECT * INTO v_caller_profile FROM public.profiles WHERE id = v_caller_id;
  IF NOT FOUND OR v_caller_profile.is_active IS NOT TRUE THEN
    RAISE EXCEPTION 'Active user profile not found.';
  END IF;
  SELECT r.code INTO v_caller_role FROM public.roles r WHERE r.id = v_caller_profile.role_id;

  -- 1. Caller organization verification
  IF v_caller_profile.organization_id != v_req.organization_id THEN
    RAISE EXCEPTION 'Access Denied: You do not belong to the organization of this request.';
  END IF;

  -- 2. Caller access & forwarding authorization check
  -- Caller must be authorized viewer/actor: creator, approver, forwardee, admin, or scoped manager
  IF v_req.created_by = v_caller_id THEN
    v_is_authorized := TRUE;
  ELSIF EXISTS (SELECT 1 FROM public.request_approvers WHERE request_id = p_request_id AND approver_id = v_caller_id) THEN
    v_is_authorized := TRUE;
  ELSIF EXISTS (SELECT 1 FROM public.request_forwards WHERE request_id = p_request_id AND to_user_id = v_caller_id) THEN
    v_is_authorized := TRUE;
  ELSIF v_caller_role IN ('admin', 'company_admin', 'super_admin') OR v_caller_profile.is_primary_admin = TRUE THEN
    v_is_authorized := TRUE;
  ELSIF v_caller_role = 'manager' AND public.is_manager_of_scope(v_req.department_id, v_req.site_id) THEN
    v_is_authorized := TRUE;
  END IF;

  IF NOT v_is_authorized THEN
    RAISE EXCEPTION 'Access Denied: You are not authorized to view or forward this request.';
  END IF;

  -- 3. Recipient validation
  SELECT * INTO v_recipient_profile FROM public.profiles WHERE id = p_to_user_id;
  IF NOT FOUND OR v_recipient_profile.is_active IS NOT TRUE THEN
    RAISE EXCEPTION 'Recipient user profile not found or is inactive.';
  END IF;

  IF v_recipient_profile.organization_id != v_req.organization_id THEN
    RAISE EXCEPTION 'Cross-organization forwarding is prohibited.';
  END IF;

  IF p_to_user_id = v_caller_id THEN
    RAISE EXCEPTION 'Cannot forward a request to yourself.';
  END IF;

  -- 4. Insert forward record (grants read access, zero approval rights)
  INSERT INTO public.request_forwards (
    request_id,
    organization_id,
    from_user_id,
    from_user_name,
    to_user_id,
    to_user_name,
    notes
  ) VALUES (
    p_request_id,
    v_req.organization_id,
    v_caller_id,
    v_caller_profile.full_name,
    p_to_user_id,
    v_recipient_profile.full_name,
    p_notes
  );

  -- 5. Append audit history
  INSERT INTO public.request_history (
    request_id,
    organization_id,
    actor_id,
    actor_name,
    actor_role,
    action,
    details
  ) VALUES (
    p_request_id,
    v_req.organization_id,
    v_caller_id,
    v_caller_profile.full_name,
    COALESCE(v_caller_role, 'User'),
    'Forwarded',
    'Forwarded to ' || v_recipient_profile.full_name || '.' || CASE WHEN length(trim(p_notes)) > 0 THEN ' Notes: ' || p_notes ELSE '' END
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

COMMIT;

