-- ============================================================================
-- Migration: 20261109000006_fix_action_subtasks_jsonb_storage_authorization.sql
-- Description:
--   Fix subtask assignee check in public.can_user_access_storage_document(TEXT):
--   In ActionFlow, action subtasks are stored as a JSONB array in `actions.subtasks`
--   (not in a separate table).
--   This migration queries `actions.subtasks` via `jsonb_array_elements` checking
--   `assigned_staff_id` and `assigned_staff_email` against caller profile.
--   Preserves all existing security controls:
--   - Creator, primary assignee, co-assignee (action_assignees), contributor (action_contributors)
--   - Manager scopes (is_manager_of_scope, department-wide, site-wide, organization-scope created)
--   - Admin / Platform Admin organization-wide access
--   - Strictly denies same-department staff without an explicit authorized relationship
-- ============================================================================

BEGIN;

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
  SELECT p.id, p.organization_id::text as org_id, p.department_id, p.email, p.is_active,
         (r.code IN ('admin', 'company_admin', 'super_admin') OR p.is_primary_admin = TRUE) as is_admin,
         (r.code = 'manager') as is_manager,
         (r.code IN ('platform_admin', 'super_admin')) as is_platform_admin
  INTO v_profile
  FROM public.profiles p
  LEFT JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = v_uid;

  IF NOT FOUND OR NOT v_profile.is_active THEN
    RETURN FALSE;
  END IF;

  -- Verify user belongs to the target organization (Platform Admins exempt)
  IF NOT v_profile.is_platform_admin AND NOT public.check_user_in_org(v_org_id) THEN
    RETURN FALSE;
  END IF;

  -- 2. NARROW ROUTING: Request attachments must use Request-specific authorization.
  IF v_folder = 'requests' THEN
    RETURN public.can_user_access_storage_request(p_file_path);
  END IF;

  -- 3. ACTION ATTACHMENTS ACCESS: <org_id>/actions/<action_id>/<file_name>
  -- Evaluated strictly BEFORE general document access.
  -- Department or team membership alone NEVER grants action attachment access.
  IF v_folder = 'actions' AND v_action_ref IS NOT NULL AND v_action_ref != '' THEN
    -- Admins have organization-wide access
    IF v_profile.is_admin OR v_profile.is_platform_admin THEN
      RETURN TRUE;
    END IF;

    -- Strict relationship or manager scope verification
    IF EXISTS (
      SELECT 1 FROM public.actions a
      WHERE (a.id::text = v_action_ref OR a.action_number = v_action_ref)
        AND (
          -- Explicit Action Relationships (Staff & Managers):
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
          OR (
            a.subtasks IS NOT NULL 
            AND jsonb_typeof(a.subtasks) = 'array'
            AND EXISTS (
              SELECT 1 FROM jsonb_array_elements(a.subtasks) elem
              WHERE elem->>'assigned_staff_id' = v_uid::text
                 OR (v_profile.email IS NOT NULL AND lower(trim(COALESCE(elem->>'assigned_staff_email', ''))) = lower(trim(v_profile.email)))
            )
          )
          -- Authorized Manager Scope:
          OR (
            v_profile.is_manager AND (
              (a.scope_type = 'organization' AND a.created_by = v_uid)
              OR (COALESCE(a.scope_type, 'specific') = 'specific' AND public.is_manager_of_scope(a.department_id, a.site_id))
              OR (a.scope_type = 'department' AND (
                public.is_manager_of_department_wide(a.department_id)
                OR EXISTS (
                  SELECT 1 FROM public.manager_scopes ms
                  WHERE ms.manager_profile_id = v_uid AND ms.department_id = a.department_id
                )
              ))
              OR (a.scope_type = 'site' AND (
                public.is_manager_of_site_wide(a.site_id)
                OR EXISTS (
                  SELECT 1 FROM public.manager_scopes ms
                  WHERE ms.manager_profile_id = v_uid AND ms.site_id = a.site_id
                )
              ))
            )
          )
        )
    ) THEN
      RETURN TRUE;
    END IF;

    -- If no authorized relationship or manager scope exists, block access
    RETURN FALSE;
  END IF;

  -- 4. GENERAL DOCUMENTS: Managers & Admins have full access across departments in their organization
  IF v_profile.is_admin OR v_profile.is_manager OR v_profile.is_platform_admin THEN
    RETURN TRUE;
  END IF;

  -- 5. Lookup document metadata in public.documents
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

  -- 6. Explicit internal share recipient
  IF EXISTS (
    SELECT 1 FROM public.document_shares ds
    WHERE ds.document_id = v_doc.id
      AND ds.user_id = v_uid
  ) THEN
    RETURN TRUE;
  END IF;

  -- 7. Author / creator
  IF v_doc.created_by = v_uid THEN
    RETURN TRUE;
  END IF;

  -- 8. DEPARTMENT ISOLATION for unshared documents
  IF v_doc.department_id IS NOT NULL AND (v_profile.department_id IS NULL OR v_profile.department_id != v_doc.department_id) THEN
    RETURN FALSE;
  END IF;

  -- 9. Linked action participant
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
        OR (
          a.subtasks IS NOT NULL 
          AND jsonb_typeof(a.subtasks) = 'array'
          AND EXISTS (
            SELECT 1 FROM jsonb_array_elements(a.subtasks) elem
            WHERE elem->>'assigned_staff_id' = v_uid::text
               OR (v_profile.email IS NOT NULL AND lower(trim(COALESCE(elem->>'assigned_staff_email', ''))) = lower(trim(v_profile.email)))
          )
        )
      )
  ) THEN
    RETURN TRUE;
  END IF;

  -- 10. General organizational and department guidelines & policies
  IF v_doc.department_id IS NULL AND v_doc.category IN ('HSSE Manuals', 'Policies', 'Policies & Procedures', 'Manuals & Guides', 'General') THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_user_access_storage_document(TEXT) TO authenticated, service_role;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;
