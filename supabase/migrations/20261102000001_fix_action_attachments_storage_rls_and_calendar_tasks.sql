-- ============================================================================
-- Migration: 20261102000001_fix_action_attachments_storage_rls_and_calendar_tasks.sql
-- Description:
--   1. Fixes Action Attachments Preview/Download 404 & Upload 403:
--      - Updates `can_user_access_storage_document(p_file_path TEXT)` to grant
--        assigned staff, creators, contributors, and subtask assignees access to
--        action evidence storage objects in the private 'documents' bucket under
--        paths formatted as '<org_id>/actions/<action_id>/<file_name>'.
--      - Updates `check_user_in_org(p_org_id TEXT)` to recognize organization UUID,
--        organization code, and default organization aliases ('SOBHA-001', 'org-sobha-01', 'default-org').
--   2. Architectural Decoupling Notice:
--      - Table `public.calendar_tasks` and its RLS policies are canonically defined
--        and managed in `20261025000001_create_calendar_tasks.sql`.
--      - To prevent conflicting schema definitions, mismatched priority constraints,
--        and duplicate RLS policies, calendar table DDL has been excluded here.
--
-- IMPORTANT NOTICE:
--   As per repository change control policies, this migration must NOT be executed
--   automatically. It must be reviewed and deployed manually to the remote Supabase
--   instance via the Supabase Dashboard SQL Editor or CLI by the authorized administrator.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Helper function: check_user_in_org (Updated for UUID and Org Code Aliases)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_user_in_org(p_org_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    LEFT JOIN public.organizations o ON p.organization_id = o.id
    WHERE p.id = auth.uid()
      AND p.is_active = TRUE
      AND (
        p_org_id IS NULL
        OR p.organization_id::text = p_org_id
        OR o.code = p_org_id
        OR (
          p_org_id IN ('SOBHA-001', 'org-sobha-01', 'default-org')
          AND (
            p.organization_id = '00000000-0000-0000-0000-000000000001'::uuid
            OR o.code IN ('SOBHA-001', 'org-sobha-01')
          )
        )
      )
  );
$$;

GRANT EXECUTE ON FUNCTION public.check_user_in_org(TEXT) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. Storage Helper Function: can_user_access_storage_document
--    (Updated to support action attachments under <org_id>/actions/<action_id>/...)
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
  v_action_ref TEXT := split_part(p_file_path, '/', 3);
  v_doc RECORD;
  v_profile RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN FALSE;
  END IF;

  -- 1. Check user profile & active status
  SELECT p.id, p.organization_id::text as org_id, p.department_id, p.is_active,
         (r.code IN ('manager', 'admin', 'company_admin', 'super_admin') OR p.is_primary_admin = TRUE) as is_manager
  INTO v_profile
  FROM public.profiles p
  LEFT JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = v_uid;

  IF NOT FOUND OR NOT v_profile.is_active THEN
    RETURN FALSE;
  END IF;

  -- Verify user belongs to the target organization
  IF NOT public.check_user_in_org(v_org_id) THEN
    RETURN FALSE;
  END IF;

  -- 2. Managers & Admins have full access across the organization
  IF v_profile.is_manager THEN
    RETURN TRUE;
  END IF;

  -- 3. Action Attachments Access: <org_id>/actions/<action_id>/<file_name>
  IF v_folder = 'actions' AND v_action_ref IS NOT NULL AND v_action_ref != '' THEN
    IF EXISTS (
      SELECT 1 FROM public.actions a
      WHERE (a.id::text = v_action_ref OR a.action_number = v_action_ref)
        AND (
          a.assigned_to = v_uid
          OR a.created_by = v_uid
          OR EXISTS (SELECT 1 FROM public.action_contributors ac WHERE ac.action_id = a.id AND ac.profile_id = v_uid)
          OR EXISTS (SELECT 1 FROM public.action_assignees aa WHERE aa.action_id = a.id AND aa.profile_id = v_uid)
          OR EXISTS (SELECT 1 FROM public.action_subtasks ast WHERE ast.action_id = a.id AND ast.assigned_to = v_uid)
        )
    ) THEN
      RETURN TRUE;
    END IF;
  END IF;

  -- 4. Lookup document metadata in public.documents
  SELECT * INTO v_doc
  FROM public.documents
  WHERE file_path = p_file_path
    AND (organization_id = v_org_id OR organization_id = v_profile.org_id)
    AND is_archived = FALSE;

  -- If not in documents table (e.g. freshly uploaded storage object), allow if caller is object owner
  IF NOT FOUND THEN
    RETURN EXISTS (
      SELECT 1 FROM storage.objects
      WHERE name = p_file_path
        AND bucket_id = 'documents'
        AND (owner = v_uid OR owner_id = v_uid::text)
    );
  END IF;

  -- 5. Department Isolation for general documents
  IF v_doc.department_id IS NOT NULL AND (v_profile.department_id IS NULL OR v_profile.department_id != v_doc.department_id) THEN
    RETURN FALSE;
  END IF;

  -- 6. Document author
  IF v_doc.created_by = v_uid THEN
    RETURN TRUE;
  END IF;

  -- 7. Document explicit share
  IF EXISTS (
    SELECT 1 FROM public.document_shares ds
    WHERE ds.document_id = v_doc.id
      AND ds.user_id = v_uid
  ) THEN
    RETURN TRUE;
  END IF;

  -- 8. General policy / manual
  IF v_doc.category IN ('HSSE Manuals', 'Policies') THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_user_access_storage_document(TEXT) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. Architectural Decoupling: Calendar Tasks Table & Policies
-- ----------------------------------------------------------------------------
-- NOTE: The `public.calendar_tasks` table and its strict owner-isolated RLS policies
-- are canonically defined in:
--   supabase/migrations/20261025000001_create_calendar_tasks.sql
--
-- Redundant DDL and duplicate RLS policies previously placed here have been removed
-- to prevent schema divergence (e.g. auth.users vs public.profiles foreign keys,
-- priority check case differences) and duplicate policy overhead.
-- If applying migrations to a fresh database, execute 20261025000001 first.

-- ----------------------------------------------------------------------------
-- 4. Reload PostgREST Schema Cache
-- ----------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';

COMMIT;

