-- ============================================================================
-- Migration: 20261103000003_documents_sharing_and_department_authorization.sql
-- Description:
--   1. Authorizes cross-department document sharing by Managers with supervisory scopes.
--   2. Authorizes reverse sharing workflow from Staff to Department Managers.
--   3. Maintains strict department isolation for Staff-to-Staff peer sharing.
--   4. Grants explicit SELECT and storage download access for legitimate share recipients.
--   5. Enforces immediate revocation: revoked shares instantly terminate access.
--   6. Enforces strict organization isolation across all document workflows.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Helper Function: check_manager_has_department_scope
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_manager_has_department_scope(
  p_manager_id UUID,
  p_department_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_is_admin BOOLEAN;
  v_mgr_dept UUID;
BEGIN
  IF p_manager_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- 1. Check if manager has administrative or platform owner authority
  SELECT (r.code IN ('admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = TRUE), p.department_id
  INTO v_is_admin, v_mgr_dept
  FROM public.profiles p
  LEFT JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = p_manager_id AND p.is_active = TRUE;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  IF v_is_admin THEN
    RETURN TRUE;
  END IF;

  -- Documents without department metadata (general/org-wide) are within manager scope
  IF p_department_id IS NULL THEN
    RETURN TRUE;
  END IF;

  -- 2. Check primary department match
  IF v_mgr_dept IS NOT NULL AND v_mgr_dept = p_department_id THEN
    RETURN TRUE;
  END IF;

  -- 3. Check supervisory scopes in manager_scopes
  IF EXISTS (
    SELECT 1 FROM public.manager_scopes ms
    WHERE ms.manager_profile_id = p_manager_id
      AND ms.department_id = p_department_id
  ) THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_manager_has_department_scope(UUID, UUID) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. Hardened Document Share Department & Scope Isolation Trigger
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_document_share_department_isolation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_doc RECORD;
  v_recipient RECORD;
  v_sharer RECORD;
BEGIN
  -- 1. Lookup document
  SELECT id, organization_id, department_id, created_by
  INTO v_doc
  FROM public.documents
  WHERE id = NEW.document_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Document % not found.', NEW.document_id;
  END IF;

  -- Ensure organization matches
  IF NEW.organization_id != v_doc.organization_id THEN
    RAISE EXCEPTION 'Share organization does not match document organization.';
  END IF;

  -- 2. Lookup recipient profile
  SELECT p.id, p.organization_id::text as org_id, p.department_id, p.is_active,
         (r.code IN ('manager', 'admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = TRUE) as is_manager
  INTO v_recipient
  FROM public.profiles p
  LEFT JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = NEW.user_id;

  IF NOT FOUND OR NOT v_recipient.is_active THEN
    RAISE EXCEPTION 'Share recipient is inactive or does not exist.';
  END IF;

  IF v_recipient.org_id != v_doc.organization_id THEN
    RAISE EXCEPTION 'Recipient belongs to a different organization.';
  END IF;

  -- 3. Lookup sharer profile
  IF auth.uid() IS NOT NULL OR NEW.shared_by IS NOT NULL THEN
    SELECT p.id, p.organization_id::text as org_id, p.department_id, p.is_active,
           (r.code IN ('manager', 'admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = TRUE) as is_manager
    INTO v_sharer
    FROM public.profiles p
    LEFT JOIN public.roles r ON p.role_id = r.id
    WHERE p.id = COALESCE(auth.uid(), NEW.shared_by::uuid);

    IF NOT FOUND OR NOT v_sharer.is_active THEN
      RAISE EXCEPTION 'Sharer is inactive or not found.';
    END IF;

    IF v_sharer.org_id != v_doc.organization_id THEN
      RAISE EXCEPTION 'Sharer belongs to a different organization.';
    END IF;
  END IF;

  -- 4. BUSINESS RULE ENFORCEMENT

  -- CASE A: Sharer is MANAGER or ADMIN
  IF v_sharer.is_manager THEN
    -- If sharing with a Staff member:
    IF NOT v_recipient.is_manager THEN
      -- Manager must have supervisory scope over the recipient's department
      IF NOT public.check_manager_has_department_scope(v_sharer.id, v_recipient.department_id) THEN
        RAISE EXCEPTION 'Department Isolation Violation: Manager does not have supervisory authority over recipient department (Recipient Dept: %).',
          v_recipient.department_id;
      END IF;

      -- If document belongs to a specific department, manager must have scope over document's department or have authored it
      IF v_doc.department_id IS NOT NULL AND v_doc.created_by != v_sharer.id THEN
        IF NOT public.check_manager_has_department_scope(v_sharer.id, v_doc.department_id) THEN
          RAISE EXCEPTION 'Department Isolation Violation: Manager does not have supervisory authority over document department (Doc Dept: %).',
            v_doc.department_id;
        END IF;
      END IF;
    END IF;
    -- Note: Manager-to-Manager sharing within the same organization is authorized.

  -- CASE B: Sharer is STAFF
  ELSE
    -- If recipient is another STAFF member:
    IF NOT v_recipient.is_manager THEN
      -- Staff can only share documents they authored with other staff members
      IF v_doc.created_by != v_sharer.id THEN
        RAISE EXCEPTION 'Staff members can only share documents they authored.';
      END IF;

      -- Staff can never share cross-department with other staff members
      IF v_doc.department_id IS NOT NULL AND (v_recipient.department_id IS NULL OR v_recipient.department_id != v_doc.department_id) THEN
        RAISE EXCEPTION 'Department Isolation Violation: Staff member cannot receive shares for documents outside their own department (Doc Dept: %, Recipient Dept: %).',
          v_doc.department_id, v_recipient.department_id;
      END IF;

      IF v_sharer.department_id IS NOT NULL AND (v_recipient.department_id IS NULL OR v_recipient.department_id != v_sharer.department_id) THEN
        RAISE EXCEPTION 'Staff members cannot share documents outside their own department.';
      END IF;

    -- If recipient is a DEPARTMENT MANAGER or ADMIN:
    ELSE
      -- Reverse sharing from Staff to authorized Manager:
      -- Manager must supervise staff's department or the document's department
      IF NOT public.check_manager_has_department_scope(v_recipient.id, v_sharer.department_id)
         AND NOT public.check_manager_has_department_scope(v_recipient.id, v_doc.department_id) THEN
        RAISE EXCEPTION 'Staff member cannot share document with a manager who does not supervise their department.';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.enforce_document_share_department_isolation() TO authenticated, service_role;

DROP TRIGGER IF EXISTS trg_enforce_document_share_isolation ON public.document_shares;
CREATE TRIGGER trg_enforce_document_share_isolation
  BEFORE INSERT OR UPDATE ON public.document_shares
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_document_share_department_isolation();

-- ----------------------------------------------------------------------------
-- 3. Hardened Documents SELECT RLS Policy
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "documents_org_select" ON public.documents;
CREATE POLICY "documents_org_select" ON public.documents
  FOR SELECT USING (
    -- User must be active in document's organization
    public.check_user_in_org(organization_id)
    AND (
      -- Managers & Admins have org-wide visibility
      public.check_user_is_manager_or_admin(organization_id)
      
      -- Staff members:
      OR (
        -- 1. Author can view their own document
        auth.uid() = documents.created_by
        
        -- 2. Explicit internal share recipient (authorized by sharing trigger)
        OR EXISTS (
          SELECT 1 FROM public.document_shares ds
          WHERE ds.document_id = documents.id
            AND ds.user_id = auth.uid()
        )
        
        -- 3. Department documents: isolated to own department
        OR (
          documents.department_id IS NOT NULL
          AND documents.department_id = public.get_user_department_id(auth.uid())
        )
        
        -- 4. General / Org-wide guidelines & policies
        OR (
          documents.department_id IS NULL
          AND documents.category IN ('HSSE Manuals', 'Policies', 'Policies & Procedures', 'Manuals & Guides', 'General')
        )
        
        -- 5. Linked action participant
        OR (
          documents.action_id IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM public.actions a
            WHERE (a.id::text = documents.action_id OR a.action_number = documents.action_id)
              AND (
                a.assigned_to = auth.uid()
                OR a.created_by = auth.uid()
                OR EXISTS (
                  SELECT 1 FROM public.action_contributors ac
                  WHERE ac.action_id = a.id AND ac.profile_id = auth.uid()
                )
                OR EXISTS (
                  SELECT 1 FROM public.action_assignees aa
                  WHERE aa.action_id = a.id AND aa.profile_id = auth.uid()
                )
              )
          )
        )
      )
    )
  );

-- ----------------------------------------------------------------------------
-- 4. Storage Objects Security: Document-Level & Department Authorization
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

  -- 2. Managers & Admins have full access across departments in their organization
  IF v_profile.is_manager THEN
    RETURN TRUE;
  END IF;

  -- 3. Lookup document metadata
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

  -- 4. Explicit internal share recipient (verified by sharing trigger):
  IF EXISTS (
    SELECT 1 FROM public.document_shares ds
    WHERE ds.document_id = v_doc.id
      AND ds.user_id = v_uid
  ) THEN
    RETURN TRUE;
  END IF;

  -- 5. Author / creator:
  IF v_doc.created_by = v_uid THEN
    RETURN TRUE;
  END IF;

  -- 6. DEPARTMENT ISOLATION for unshared documents:
  -- Staff CANNOT access documents belonging to another department without an explicit share!
  IF v_doc.department_id IS NOT NULL AND (v_profile.department_id IS NULL OR v_profile.department_id != v_doc.department_id) THEN
    RETURN FALSE;
  END IF;

  -- 7. Linked action participant:
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

  -- 8. General organizational and department guidelines & policies:
  IF v_doc.department_id IS NULL AND v_doc.category IN ('HSSE Manuals', 'Policies', 'Policies & Procedures', 'Manuals & Guides', 'General') THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_user_access_storage_document(TEXT) TO authenticated, service_role;

COMMIT;

