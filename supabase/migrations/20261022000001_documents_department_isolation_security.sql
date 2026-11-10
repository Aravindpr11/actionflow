-- ============================================================================
-- Migration: 20261022000001_documents_department_isolation_security.sql
-- Description:
--   1. Enforces strict department isolation on documents and private storage.
--   2. Prevents cross-department sharing to staff members via BEFORE trigger.
--   3. Synchronizes shared_internal_count dynamically on share insert/update/delete.
--   4. Eliminates recursive RLS policy deadlocks on document_shares.
--   5. Secures storage.objects and signed URLs with can_user_access_storage_document.
--   6. Ensures safe search_path and proper execution grants on helper functions.
--   7. Hardens documents_storage_update to prevent cross-department overwrites.
--   8. Restricts unindexed storage object access strictly to the object owner.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Ensure Private 'documents' Storage Bucket Exists
-- ----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('documents', 'documents', false)
ON CONFLICT (id) DO UPDATE SET public = false;

-- ----------------------------------------------------------------------------
-- 2. Helper Functions (with Explicit Safe search_path)
-- ----------------------------------------------------------------------------

-- Helper: Get active user's department ID
CREATE OR REPLACE FUNCTION public.get_user_department_id(p_user_id UUID DEFAULT auth.uid())
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
AS $$
  SELECT department_id FROM public.profiles
  WHERE id = p_user_id AND is_active = TRUE;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_department_id(UUID) TO authenticated, service_role;

-- Helper: Check caller belongs to an organization and is active
CREATE OR REPLACE FUNCTION public.check_user_in_org(p_org_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND (organization_id::text = p_org_id OR p_org_id IS NULL)
      AND is_active = TRUE
  );
$$;

GRANT EXECUTE ON FUNCTION public.check_user_in_org(TEXT) TO authenticated, service_role;

-- Helper: Check caller is manager, company admin, or platform owner
CREATE OR REPLACE FUNCTION public.check_user_is_manager_or_admin(p_org_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    LEFT JOIN public.roles r ON p.role_id = r.id
    WHERE p.id = auth.uid()
      AND (p.organization_id::text = p_org_id OR p_org_id IS NULL)
      AND p.is_active = TRUE
      AND (
        r.code IN ('manager', 'admin')
        OR p.is_primary_admin = TRUE
      )
  );
$$;

GRANT EXECUTE ON FUNCTION public.check_user_is_manager_or_admin(TEXT) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. Hardened Documents Table RLS Policies
-- ----------------------------------------------------------------------------
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "documents_org_select" ON public.documents;
CREATE POLICY "documents_org_select" ON public.documents
  FOR SELECT USING (
    -- User must be active in document's organization
    public.check_user_in_org(organization_id)
    AND (
      -- Managers & Admins have org-wide visibility
      public.check_user_is_manager_or_admin(organization_id)
      
      -- Staff members: Strictly isolated to own department or org-wide
      OR (
        (
          documents.department_id IS NULL
          OR documents.department_id = public.get_user_department_id(auth.uid())
        )
        AND (
          -- Author can view their own document
          auth.uid() = documents.created_by
          
          -- Explicit internal share recipient (intra-department verified by trigger)
          OR EXISTS (
            SELECT 1 FROM public.document_shares ds
            WHERE ds.document_id = documents.id
              AND ds.user_id = auth.uid()
          )
          
          -- Linked action participant
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
          
          -- General organizational and department guidelines & policies
          OR documents.category IN ('HSSE Manuals', 'Policies')
        )
      )
    )
  );

DROP POLICY IF EXISTS "documents_org_insert" ON public.documents;
CREATE POLICY "documents_org_insert" ON public.documents
  FOR INSERT WITH CHECK (
    public.check_user_in_org(organization_id)
    AND (
      public.check_user_is_manager_or_admin(organization_id)
      OR (
        auth.uid() = created_by
        AND department_id IS NOT NULL
        AND department_id = public.get_user_department_id(auth.uid())
      )
    )
  );

DROP POLICY IF EXISTS "documents_org_update" ON public.documents;
CREATE POLICY "documents_org_update" ON public.documents
  FOR UPDATE USING (
    public.check_user_in_org(organization_id)
    AND (
      public.check_user_is_manager_or_admin(organization_id)
      OR (
        auth.uid() = created_by
        AND (
          documents.department_id IS NULL
          OR documents.department_id = public.get_user_department_id(auth.uid())
        )
      )
    )
  );

DROP POLICY IF EXISTS "documents_org_delete" ON public.documents;
CREATE POLICY "documents_org_delete" ON public.documents
  FOR DELETE USING (
    public.check_user_in_org(organization_id)
    AND (
      public.check_user_is_manager_or_admin(organization_id)
      OR (
        auth.uid() = created_by
        AND (
          documents.department_id IS NULL
          OR documents.department_id = public.get_user_department_id(auth.uid())
        )
      )
    )
  );

-- ----------------------------------------------------------------------------
-- 4. Document Shares Business Rules Trigger (Cross-Department Share Prevention)
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
         (r.code IN ('manager', 'admin') OR p.is_primary_admin = TRUE) as is_manager
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

  -- 3. DEPARTMENT ISOLATION ENFORCEMENT:
  -- If the document belongs to a specific department:
  -- Staff recipients MUST belong to that SAME department!
  IF v_doc.department_id IS NOT NULL AND NOT v_recipient.is_manager THEN
    IF v_recipient.department_id IS NULL OR v_recipient.department_id != v_doc.department_id THEN
      RAISE EXCEPTION 'Department Isolation Violation: Staff member cannot receive shares for documents outside their own department (Doc Dept: %, Recipient Dept: %).',
        v_doc.department_id, v_recipient.department_id;
    END IF;
  END IF;

  -- 4. SHARER AUTHORIZATION:
  IF auth.uid() IS NOT NULL THEN
    SELECT p.id, p.organization_id::text as org_id, p.department_id, p.is_active,
           (r.code IN ('manager', 'admin') OR p.is_primary_admin = TRUE) as is_manager
    INTO v_sharer
    FROM public.profiles p
    LEFT JOIN public.roles r ON p.role_id = r.id
    WHERE p.id = auth.uid();

    IF NOT FOUND OR NOT v_sharer.is_active THEN
      RAISE EXCEPTION 'Sharer is inactive or not found.';
    END IF;

    -- If sharer is staff:
    IF NOT v_sharer.is_manager THEN
      -- Staff can only share documents they created
      IF v_doc.created_by != auth.uid() THEN
        RAISE EXCEPTION 'Staff members can only share documents they authored.';
      END IF;
      -- Staff can only share documents of their current department
      IF v_doc.department_id IS NOT NULL AND (v_sharer.department_id IS NULL OR v_sharer.department_id != v_doc.department_id) THEN
        RAISE EXCEPTION 'Staff members cannot share documents belonging to another department.';
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
-- 5. Trigger to Automatically Synchronize shared_internal_count
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_document_share_counts()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_doc_id TEXT;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.document_id IS DISTINCT FROM NEW.document_id THEN
    UPDATE public.documents
    SET shared_internal_count = (
      SELECT count(*) FROM public.document_shares WHERE document_id = OLD.document_id
    )
    WHERE id = OLD.document_id;
  END IF;

  v_doc_id := COALESCE(NEW.document_id, OLD.document_id);
  UPDATE public.documents
  SET shared_internal_count = (
    SELECT count(*) FROM public.document_shares WHERE document_id = v_doc_id
  )
  WHERE id = v_doc_id;
  RETURN NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_document_share_counts() TO authenticated, service_role;

DROP TRIGGER IF EXISTS trg_sync_doc_share_counts ON public.document_shares;
CREATE TRIGGER trg_sync_doc_share_counts
  AFTER INSERT OR UPDATE OR DELETE ON public.document_shares
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_document_share_counts();

-- ----------------------------------------------------------------------------
-- 6. Decoupled Document Shares RLS Policies (Prevents Recursive 42P17 Errors)
-- ----------------------------------------------------------------------------
ALTER TABLE public.document_shares ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "document_shares_manage" ON public.document_shares;
DROP POLICY IF EXISTS "document_shares_select" ON public.document_shares;
CREATE POLICY "document_shares_select" ON public.document_shares
  FOR SELECT USING (
    public.check_user_in_org(organization_id)
    AND (
      public.check_user_is_manager_or_admin(organization_id)
      OR user_id = auth.uid()
      OR shared_by = auth.uid()
    )
  );

DROP POLICY IF EXISTS "document_shares_insert" ON public.document_shares;
CREATE POLICY "document_shares_insert" ON public.document_shares
  FOR INSERT WITH CHECK (
    public.check_user_in_org(organization_id)
    AND (
      public.check_user_is_manager_or_admin(organization_id)
      OR shared_by = auth.uid()
    )
  );

DROP POLICY IF EXISTS "document_shares_update" ON public.document_shares;
CREATE POLICY "document_shares_update" ON public.document_shares
  FOR UPDATE USING (
    public.check_user_in_org(organization_id)
    AND (
      public.check_user_is_manager_or_admin(organization_id)
      OR shared_by = auth.uid()
    )
  );

DROP POLICY IF EXISTS "document_shares_delete" ON public.document_shares;
CREATE POLICY "document_shares_delete" ON public.document_shares
  FOR DELETE USING (
    public.check_user_in_org(organization_id)
    AND (
      public.check_user_is_manager_or_admin(organization_id)
      OR shared_by = auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- 7. Storage Objects Security: Document-level & Department Isolation
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
         (r.code IN ('manager', 'admin') OR p.is_primary_admin = TRUE) as is_manager
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

  -- 2. Managers & Admins have full access across departments
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
  -- restrict access strictly to the object owner (managers/admins are already permitted above)
  IF NOT FOUND THEN
    RETURN EXISTS (
      SELECT 1 FROM storage.objects
      WHERE name = p_file_path
        AND bucket_id = 'documents'
        AND (owner = v_uid OR owner_id = v_uid::text)
    );
  END IF;

  -- 4. DEPARTMENT ISOLATION:
  -- Staff CANNOT access storage objects belonging to another department!
  IF v_doc.department_id IS NOT NULL AND (v_profile.department_id IS NULL OR v_profile.department_id != v_doc.department_id) THEN
    RETURN FALSE;
  END IF;

  -- 5. Within same department or org-wide:
  -- Allowed if author/creator
  IF v_doc.created_by = v_uid THEN
    RETURN TRUE;
  END IF;

  -- Allowed if explicitly shared
  IF EXISTS (
    SELECT 1 FROM public.document_shares ds
    WHERE ds.document_id = v_doc.id
      AND ds.user_id = v_uid
  ) THEN
    RETURN TRUE;
  END IF;

  -- Allowed if linked action participant
  IF v_doc.action_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.actions a
    WHERE (a.id::text = v_doc.action_id OR a.action_number = v_doc.action_id)
      AND (
        a.assigned_to = v_uid
        OR a.created_by = v_uid
        OR EXISTS (SELECT 1 FROM public.action_contributors ac WHERE ac.action_id = a.id AND ac.profile_id = v_uid)
        OR EXISTS (SELECT 1 FROM public.action_assignees aa WHERE aa.action_id = a.id AND aa.profile_id = v_uid)
      )
  ) THEN
    RETURN TRUE;
  END IF;

  -- Allowed if general policy/manual
  IF v_doc.category IN ('HSSE Manuals', 'Policies') THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_user_access_storage_document(TEXT) TO authenticated, service_role;

DROP POLICY IF EXISTS "documents_storage_select" ON storage.objects;
CREATE POLICY "documents_storage_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND public.can_user_access_storage_document(name)
  );

DROP POLICY IF EXISTS "documents_storage_insert" ON storage.objects;
CREATE POLICY "documents_storage_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'documents'
    AND public.check_user_in_org(split_part(name, '/', 1))
  );

DROP POLICY IF EXISTS "documents_storage_update" ON storage.objects;
CREATE POLICY "documents_storage_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'documents'
    AND (
      public.check_user_is_manager_or_admin(split_part(name, '/', 1))
      OR (
        (owner = auth.uid() OR owner_id = auth.uid()::text)
        AND public.can_user_access_storage_document(name)
      )
    )
  )
  WITH CHECK (
    bucket_id = 'documents'
    AND (
      public.check_user_is_manager_or_admin(split_part(name, '/', 1))
      OR (
        (owner = auth.uid() OR owner_id = auth.uid()::text)
        AND public.can_user_access_storage_document(name)
      )
    )
  );

DROP POLICY IF EXISTS "documents_storage_delete" ON storage.objects;
CREATE POLICY "documents_storage_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'documents'
    AND (
      public.check_user_is_manager_or_admin(split_part(name, '/', 1))
      OR (
        (owner = auth.uid() OR owner_id = auth.uid()::text)
        AND public.can_user_access_storage_document(name)
      )
    )
  );

-- ----------------------------------------------------------------------------
-- 8. Reload PostgREST Schema Cache
-- ----------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';

COMMIT;

