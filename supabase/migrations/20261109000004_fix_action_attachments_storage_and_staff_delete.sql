-- ============================================================================
-- Migration: 20261109000004_fix_action_attachments_storage_and_staff_delete.sql
-- Description:
--   1. Action Attachments Storage Access:
--      - Updates `can_user_access_storage_document(p_file_path TEXT)` to ensure
--        assigned staff, creators, contributors, assignees, subtask assignees,
--        and scoped department staff can preview and download action attachments
--        under path '<org_id>/actions/<action_id>/<file_name>' in the private
--        'documents' bucket.
--   2. Status-Independent Staff Action Register Deletion:
--      - Updates `delete_action_authorized` and `delete_actions_bulk_authorized`
--        so that Staff creators (created_by = auth.uid()) can delete actions they
--        created regardless of status (Open, In Progress, Closed).
--      - Strictly preserves Closed-only deletion rule for non-creator assignees
--        deleting from My Actions.
--      - Preserves all Manager multi-scoping, Admin authority, and Tenant isolation.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Storage Helper: can_user_access_storage_document
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
         (r.code IN ('manager', 'admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = TRUE) as is_manager
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

  -- 2. NARROW ROUTING: Request attachments must use Request-specific authorization.
  IF v_folder = 'requests' THEN
    RETURN public.can_user_access_storage_request(p_file_path);
  END IF;

  -- 3. Managers & Admins have full access across departments in their organization
  IF v_profile.is_manager THEN
    RETURN TRUE;
  END IF;

  -- 4. ACTION ATTACHMENTS ACCESS: <org_id>/actions/<action_id>/<file_name>
  IF v_folder = 'actions' AND v_action_ref IS NOT NULL AND v_action_ref != '' THEN
    IF EXISTS (
      SELECT 1 FROM public.actions a
      WHERE (a.id::text = v_action_ref OR a.action_number = v_action_ref)
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
          OR EXISTS (
            SELECT 1 FROM public.action_subtasks ast
            WHERE ast.action_id = a.id AND ast.assigned_to = v_uid
          )
          OR (a.department_id = v_profile.department_id AND v_profile.is_active = TRUE)
        )
    ) THEN
      RETURN TRUE;
    END IF;
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

-- ----------------------------------------------------------------------------
-- 2. Stored Procedure: public.delete_action_authorized
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.delete_action_authorized(uuid);
DROP FUNCTION IF EXISTS public.delete_action_authorized(uuid, boolean);

CREATE OR REPLACE FUNCTION public.delete_action_authorized(
  p_action_id uuid,
  p_allow_closed boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_org_id       UUID;
  v_dept_id      UUID;
  v_site_id      UUID;
  v_created_by   UUID;
  v_assigned_to  UUID;
  v_scope_type   TEXT;
  v_status       TEXT;
  v_caller_org   UUID;
  v_is_admin     BOOLEAN;
  v_is_manager   BOOLEAN;
  v_is_platform  BOOLEAN;
  v_is_creator   BOOLEAN := FALSE;
  v_is_assignee  BOOLEAN := FALSE;
BEGIN
  -- 1. Require authenticated caller
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Authentication required');
  END IF;

  -- 2. Fetch action existence, tenant, and scope fields
  SELECT organization_id, department_id, site_id, status, created_by, assigned_to, COALESCE(scope_type, 'specific')
  INTO v_org_id, v_dept_id, v_site_id, v_status, v_created_by, v_assigned_to, v_scope_type
  FROM public.actions
  WHERE id = p_action_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action not found');
  END IF;

  -- If already deleted
  IF lower(trim(coalesce(v_status, ''))) = 'deleted' THEN
    RETURN jsonb_build_object('success', true, 'message', 'Action is already deleted');
  END IF;

  -- 3. Resolve caller roles and tenant
  v_is_platform := public.is_platform_admin();
  v_is_admin    := public.is_admin();
  v_is_manager  := public.is_manager();
  v_caller_org  := public.get_my_organization_id();

  -- 4. Cross-Tenant Isolation
  IF NOT v_is_platform AND (v_org_id IS DISTINCT FROM v_caller_org) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Cross-tenant operation blocked');
  END IF;

  -- 5. Role and Scope Authority
  IF NOT v_is_platform AND NOT v_is_admin THEN
    IF v_is_manager THEN
      -- Manager Scope Authorization
      IF NOT (
        (v_scope_type = 'organization' AND v_created_by = auth.uid())
        OR (v_scope_type = 'specific' AND (v_created_by = auth.uid() OR public.is_manager_of_scope(v_dept_id, v_site_id)))
        OR (v_scope_type = 'department' AND (v_created_by = auth.uid() OR public.is_manager_of_department_wide(v_dept_id)))
        OR (v_scope_type = 'site' AND (v_created_by = auth.uid() OR public.is_manager_of_site_wide(v_site_id)))
      ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Manager scope does not cover this action');
      END IF;
    ELSE
      -- Staff Role Authorization Guard
      v_is_creator := (v_created_by = auth.uid());

      SELECT EXISTS (
        SELECT 1 FROM public.action_assignees
        WHERE action_id = p_action_id
          AND profile_id = auth.uid()
      ) INTO v_is_assignee;

      IF NOT (v_is_creator OR v_assigned_to = auth.uid() OR v_is_assignee) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: You can only delete actions created by or assigned to you.');
      END IF;

      -- If caller is NOT the creator (they are an assignee deleting from My Actions),
      -- deletion is strictly restricted to closed actions.
      -- If caller IS the creator (deleting from Action Register), they can delete in any status (Open, In Progress, Closed).
      IF NOT v_is_creator AND lower(trim(coalesce(v_status, ''))) <> 'closed' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Staff members can only delete closed actions. Active actions cannot be deleted.');
      END IF;
    END IF;
  END IF;

  -- 6. Closed Action Protection
  -- If action is closed, non-creators require p_allow_closed = true
  IF NOT p_allow_closed AND lower(trim(coalesce(v_status, ''))) = 'closed' AND NOT (v_created_by = auth.uid()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLOSED_ACTION');
  END IF;

  -- 7. Safe Soft Delete
  UPDATE public.actions
  SET
    status = 'Deleted',
    deleted_at = timezone('utc'::text, now()),
    deleted_by = auth.uid(),
    updated_at = timezone('utc'::text, now())
  WHERE id = p_action_id;

  -- 8. Audit Log record (safe attempt)
  BEGIN
    INSERT INTO public.platform_audit_logs (
      organization_id,
      actor_id,
      event_type,
      target_type,
      target_id,
      description,
      metadata
    ) VALUES (
      v_org_id,
      auth.uid(),
      'ACTION_SOFT_DELETED',
      'action',
      p_action_id::TEXT,
      'Action ' || p_action_id::TEXT || ' soft deleted',
      jsonb_build_object(
        'action_id', p_action_id,
        'previous_status', v_status,
        'deleted_at', timezone('utc'::text, now())
      )
    );
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('success', true);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.delete_action_authorized(uuid, boolean) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. Stored Procedure: public.delete_actions_bulk_authorized
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.delete_actions_bulk_authorized(UUID[]);
DROP FUNCTION IF EXISTS public.delete_actions_bulk_authorized(UUID[], BOOLEAN);

CREATE OR REPLACE FUNCTION public.delete_actions_bulk_authorized(
  p_action_ids UUID[],
  p_allow_closed BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id       UUID;
  v_caller_org      UUID;
  v_is_admin        BOOLEAN;
  v_is_manager      BOOLEAN;
  v_is_platform     BOOLEAN;
  v_curr_id         UUID;
  v_org_id          UUID;
  v_dept_id         UUID;
  v_site_id         UUID;
  v_scope_type      TEXT;
  v_status          TEXT;
  v_created_by      UUID;
  v_assigned_to     UUID;
  v_is_manager_scope BOOLEAN;
  v_is_creator      BOOLEAN;
  v_is_assignee     BOOLEAN;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'deleted_count', 0,
      'failed_ids', ARRAY[]::TEXT[],
      'error', 'Unauthorized: Authentication required'
    );
  END IF;

  IF p_action_ids IS NULL OR array_length(p_action_ids, 1) = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'deleted_count', 0,
      'failed_ids', ARRAY[]::TEXT[],
      'error', NULL
    );
  END IF;

  v_caller_org  := public.get_my_organization_id();
  v_is_admin    := public.is_admin();
  v_is_manager  := public.is_manager();
  v_is_platform := public.is_platform_admin();

  -- PHASE 1: Pre-validation of all actions
  FOREACH v_curr_id IN ARRAY p_action_ids LOOP
    SELECT organization_id, department_id, site_id, status, created_by, assigned_to, COALESCE(scope_type, 'specific')
      INTO v_org_id, v_dept_id, v_site_id, v_status, v_created_by, v_assigned_to, v_scope_type
      FROM public.actions
     WHERE id = v_curr_id;

    IF NOT FOUND THEN
      RETURN jsonb_build_object(
        'success', false,
        'deleted_count', 0,
        'failed_ids', ARRAY[v_curr_id::TEXT],
        'error', 'Action not found: ' || v_curr_id::TEXT
      );
    END IF;

    IF v_caller_org IS NULL OR v_org_id IS DISTINCT FROM v_caller_org THEN
      RETURN jsonb_build_object(
        'success', false,
        'deleted_count', 0,
        'failed_ids', ARRAY[v_curr_id::TEXT],
        'error', 'Unauthorized: Tenant isolation violation for action ' || v_curr_id::TEXT
      );
    END IF;

    IF NOT p_allow_closed AND lower(trim(coalesce(v_status, ''))) = 'closed' AND NOT (v_created_by = v_caller_id) THEN
      RETURN jsonb_build_object(
        'success', false,
        'deleted_count', 0,
        'failed_ids', ARRAY[v_curr_id::TEXT],
        'error', 'CLOSED_ACTION: ' || v_curr_id::TEXT
      );
    END IF;

    -- Authority Check
    IF NOT v_is_platform AND NOT v_is_admin THEN
      IF v_is_manager THEN
        v_is_manager_scope := (
          (v_scope_type = 'organization' AND v_created_by = v_caller_id)
          OR (v_scope_type = 'specific' AND (v_created_by = v_caller_id OR public.is_manager_of_scope(v_dept_id, v_site_id)))
          OR (v_scope_type = 'department' AND (v_created_by = v_caller_id OR public.is_manager_of_department_wide(v_dept_id)))
          OR (v_scope_type = 'site' AND (v_created_by = v_caller_id OR public.is_manager_of_site_wide(v_site_id)))
        );

        IF NOT v_is_manager_scope THEN
          RETURN jsonb_build_object(
            'success', false,
            'deleted_count', 0,
            'failed_ids', ARRAY[v_curr_id::TEXT],
            'error', 'Unauthorized: Manager scope does not cover action ' || v_curr_id::TEXT
          );
        END IF;
      ELSE
        -- Staff Role Check
        v_is_creator := (v_created_by = v_caller_id);

        SELECT EXISTS (
          SELECT 1 FROM public.action_assignees
          WHERE action_id = v_curr_id
            AND profile_id = v_caller_id
        ) INTO v_is_assignee;

        IF NOT (v_is_creator OR v_assigned_to = v_caller_id OR v_is_assignee) THEN
          RETURN jsonb_build_object(
            'success', false,
            'deleted_count', 0,
            'failed_ids', ARRAY[v_curr_id::TEXT],
            'error', 'Unauthorized: Action ' || v_curr_id::TEXT || ' is not assigned to or created by caller'
          );
        END IF;

        IF NOT v_is_creator AND lower(trim(coalesce(v_status, ''))) <> 'closed' THEN
          RETURN jsonb_build_object(
            'success', false,
            'deleted_count', 0,
            'failed_ids', ARRAY[v_curr_id::TEXT],
            'error', 'Unauthorized: Staff members can only delete closed actions. Action ' || v_curr_id::TEXT || ' is not closed.'
          );
        END IF;
      END IF;
    END IF;
  END LOOP;

  -- PHASE 2: Execute soft-deletes and audit logging
  FOREACH v_curr_id IN ARRAY p_action_ids LOOP
    SELECT status INTO v_status FROM public.actions WHERE id = v_curr_id;

    UPDATE public.actions
       SET status = 'Deleted',
           deleted_at = timezone('utc'::text, now()),
           deleted_by = v_caller_id,
           updated_at = timezone('utc'::text, now())
     WHERE id = v_curr_id;

    BEGIN
      INSERT INTO public.platform_audit_logs (
        organization_id, actor_id, event_type, target_type, target_id, description, metadata
      ) VALUES (
        v_caller_org, v_caller_id, 'ACTION_SOFT_DELETED', 'action', v_curr_id::TEXT,
        'Action ' || v_curr_id::TEXT || ' bulk soft deleted',
        jsonb_build_object('action_id', v_curr_id, 'previous_status', v_status, 'bulk', true)
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'deleted_count', array_length(p_action_ids, 1),
    'failed_ids', ARRAY[]::TEXT[],
    'error', NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_actions_bulk_authorized(UUID[], BOOLEAN) TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. Reload PostgREST Schema Cache
-- ----------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';

COMMIT;
