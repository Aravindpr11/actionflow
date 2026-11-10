-- ============================================================================
-- Migration: 20261104000003_request_storage_and_completion_hardening.sql
-- Description:
--   1. Storage Policy Hardening:
--      - Adjusts public.can_user_access_storage_document(TEXT) to delegate any
--        request attachment paths (split_part(p_file_path, '/', 2) = 'requests')
--        strictly to public.can_user_access_storage_request(TEXT).
--      - Hardens storage.objects policy "documents_storage_select" to strictly
--        exclude the 'requests' directory (split_part(name, '/', 2) != 'requests').
--      - Ensures normal Documents files retain 100% existing access behavior
--        while guaranteeing out-of-scope managers cannot bypass request storage RLS.
--   2. Completion Authorization Hardening:
--      - Hardens public.complete_request(UUID, TEXT) RPC to enforce:
--        * Requester (created_by): Permitted
--        * Company Admin / Platform Admin: Permitted
--        * Scoped Manager (is_manager_of_scope): Permitted
--        * Designated Approvers: EXCLUDED (approval does NOT grant completion)
--        * Forwardees, Unrelated Staff, Out-of-scope Managers: EXCLUDED
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Route Request Attachments in can_user_access_storage_document
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_user_access_storage_document(p_file_path TEXT)
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
  v_doc RECORD;
  v_profile RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN FALSE;
  END IF;

  -- 1. Check user profile & active status
  SELECT p.id, p.organization_id::text as org_id, p.department_id, p.is_active,
         (r.code IN ('manager', 'admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = TRUE) as is_manager
  INTO v_profile
  FROM public.profiles p
  LEFT JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = v_uid;

  IF NOT FOUND OR NOT v_profile.is_active THEN
    RETURN FALSE;
  END IF;

  IF v_profile.org_id != v_org_id THEN
    RETURN FALSE;
  END IF;

  -- 2. NARROW ROUTING: Request attachments must use Request-specific authorization.
  -- Out-of-scope managers cannot bypass request RLS through documents_storage_select.
  IF v_folder = 'requests' THEN
    RETURN public.can_user_access_storage_request(p_file_path);
  END IF;

  -- 3. Managers & Admins have full access across departments in their organization for normal documents
  IF v_profile.is_manager THEN
    RETURN TRUE;
  END IF;

  -- 4. Lookup document metadata
  SELECT * INTO v_doc
  FROM public.documents
  WHERE file_path = p_file_path
    AND organization_id = v_org_id
    AND is_archived = FALSE;

  -- If not yet in documents (e.g. freshly uploaded by owner within upload session),
  -- restrict access strictly to the object owner
  IF NOT FOUND THEN
    RETURN EXISTS (
      SELECT 1 FROM storage.objects
      WHERE name = p_file_path
        AND bucket_id = 'documents'
        AND (owner = v_uid OR owner_id = v_uid::text)
    );
  END IF;

  -- 5. Explicit internal share recipient (verified by sharing trigger):
  IF EXISTS (
    SELECT 1 FROM public.document_shares ds
    WHERE ds.document_id = v_doc.id
      AND ds.user_id = v_uid
  ) THEN
    RETURN TRUE;
  END IF;

  -- 6. Author / creator:
  IF v_doc.created_by = v_uid THEN
    RETURN TRUE;
  END IF;

  -- 7. DEPARTMENT ISOLATION for unshared documents:
  -- Staff CANNOT access documents belonging to another department without an explicit share!
  IF v_doc.department_id IS NOT NULL AND (v_profile.department_id IS NULL OR v_profile.department_id != v_doc.department_id) THEN
    RETURN FALSE;
  END IF;

  -- 8. Linked action participant:
  IF v_doc.action_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.actions a
    WHERE (a.id::text = v_doc.action_id OR a.action_number = v_doc.action_id)
      AND (
        a.assigned_to = v_uid
        OR a.created_by = v_uid
        OR EXISTS (
          SELECT 1 FROM public.action_contributors ac
          WHERE ac.action_id = a.id AND ac.profile_id = v_uid
        )
        OR EXISTS (
          SELECT 1 FROM public.action_assignees aa
          WHERE aa.action_id = a.id AND aa.profile_id = v_uid
        )
      )
  ) THEN
    RETURN TRUE;
  END IF;

  -- 9. General organizational and department guidelines & policies:
  IF v_doc.department_id IS NULL AND v_doc.category IN ('HSSE Manuals', 'Policies', 'Policies & Procedures', 'Manuals & Guides', 'General') THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_user_access_storage_document(TEXT) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. Narrow documents_storage_select to Non-Request Storage Objects
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "documents_storage_select" ON storage.objects;
CREATE POLICY "documents_storage_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND split_part(name, '/', 2) != 'requests'
    AND public.can_user_access_storage_document(name)
  );

-- ----------------------------------------------------------------------------
-- 3. Hardened Stored Procedure: complete_request
--    Designated Approvers do NOT have completion authority.
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
  -- a. Original Submitter / Requester (confirming completion of work)
  -- b. Company Admin / Platform Admin
  -- c. Manager with active supervisory scope over the request's department & site
  -- Explicitly DENIED: Designated approvers (approval alone != completion),
  -- forwarded recipients, out-of-scope managers, and ordinary staff.
  IF v_req.created_by = v_caller_id THEN
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

COMMIT;

