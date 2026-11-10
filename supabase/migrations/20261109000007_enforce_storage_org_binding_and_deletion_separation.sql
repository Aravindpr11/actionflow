-- ============================================================================
-- Migration: 20261109000007_enforce_storage_org_binding_and_deletion_separation.sql
-- Description:
--   1. Mandatory Storage Organization Binding:
--      In public.can_user_access_storage_document(TEXT), enforces that the requested
--      Storage path organization ID (v_org_id) strictly matches the referenced action's
--      actual organization_id (AND a.organization_id::text = v_org_id).
--      Validates that Company Admins and Platform Admins only gain access to action
--      evidence if the referenced action exists and belongs to the requested organization.
--   2. Deletion Authorization Separation:
--      In public.delete_action_authorized, public.delete_actions_bulk_authorized,
--      and public.delete_actions_bulk, adds p_portal_context TEXT DEFAULT 'action_register'.
--      - 'action_register': Caller MUST be the verified creator (v_created_by = auth.uid()).
--        Creator can delete their own actions in any status (Open, In Progress, Closed).
--      - 'my_actions': Caller MUST be an assignee (v_assigned_to = auth.uid() OR in action_assignees).
--        Assigned action deletion is strictly restricted to 'Closed' actions. Active actions
--        (Open, In Progress) cannot be deleted even if the caller created the action.
--      - Client-controlled parameter is NOT the sole boundary: backend cryptographically
--        validates auth.uid() against creator/assignee database fields.
--      - Manager and Admin management permissions remain 100% unchanged.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. HARDEN STORAGE ACCESS: can_user_access_storage_document
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
  SELECT p.id, p.organization_id::text as org_id, p.department_id, p.email, p.is_active,
         (r.code IN ('admin', 'company_admin', 'super_admin') OR p.is_primary_admin = TRUE) as is_admin,
         (r.code = 'manager') as is_manager,
         (r.code IN ('platform_admin', 'super_admin') OR public.is_platform_admin()) as is_platform_admin
  INTO v_profile
  FROM public.profiles p
  LEFT JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = v_uid;

  IF NOT FOUND OR NOT v_profile.is_active THEN
    RETURN FALSE;
  END IF;

  -- Verify user belongs to the target organization (Platform Admins exempt from single-org restriction)
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
    -- Mandatory tenant binding: The referenced action MUST exist and its organization_id MUST
    -- strictly match the requested storage path's organization ID (v_org_id).
    -- Company Admin / Platform Admin access is only valid if the action belongs to v_org_id.
    IF EXISTS (
      SELECT 1 FROM public.actions a
      WHERE (a.id::text = v_action_ref OR a.action_number = v_action_ref)
        AND a.organization_id::text = v_org_id
        AND (
          -- Admin organization-wide authority (strictly within v_org_id)
          v_profile.is_admin
          OR v_profile.is_platform_admin
          -- Explicit Action Relationships (Staff & Managers):
          OR a.assigned_to = v_uid
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
                 OR (
                   v_profile.email IS NOT NULL 
                   AND length(trim(v_profile.email)) > 0 
                   AND length(trim(COALESCE(elem->>'assigned_staff_email', ''))) > 0 
                   AND lower(trim(elem->>'assigned_staff_email')) = lower(trim(v_profile.email))
                 )
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

    -- If no authorized relationship, manager scope, or organization match exists, block access
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
      AND (a.organization_id::text = v_org_id OR a.organization_id::text = v_profile.org_id)
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
               OR (
                 v_profile.email IS NOT NULL 
                 AND length(trim(v_profile.email)) > 0 
                 AND length(trim(COALESCE(elem->>'assigned_staff_email', ''))) > 0 
                 AND lower(trim(elem->>'assigned_staff_email')) = lower(trim(v_profile.email))
               )
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


-- ----------------------------------------------------------------------------
-- 2. HARDEN SINGLE DELETION: delete_action_authorized
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.delete_action_authorized(UUID, BOOLEAN);
DROP FUNCTION IF EXISTS public.delete_action_authorized(UUID, BOOLEAN, TEXT);

CREATE OR REPLACE FUNCTION public.delete_action_authorized(
  p_action_id UUID,
  p_allow_closed BOOLEAN DEFAULT true,
  p_portal_context TEXT DEFAULT 'action_register'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
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

      -- Check contextual role authority:
      IF lower(trim(coalesce(p_portal_context, 'action_register'))) = 'my_actions' THEN
        -- Context: Staff My Actions (personal assigned work inbox)
        -- Caller MUST be an assignee (primary assignee or in action_assignees)
        IF NOT (v_assigned_to = auth.uid() OR v_is_assignee) THEN
          RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: You can only delete actions assigned to you from My Actions.');
        END IF;

        -- Assigned actions can ONLY be deleted if Closed (even if caller created it)
        IF lower(trim(coalesce(v_status, ''))) <> 'closed' THEN
          RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Staff members can only delete closed actions from My Actions. Active actions cannot be deleted.');
        END IF;

      ELSE
        -- Context: Staff Action Register (action register ownership)
        -- Caller MUST be the creator
        IF NOT v_is_creator THEN
          RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Only the creator can delete actions from Action Register.');
        END IF;

        -- Staff creators can delete their own actions in any status (Open, In Progress, Closed)
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
        'portal_context', p_portal_context,
        'deleted_at', timezone('utc'::text, now())
      )
    );
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_action_authorized(UUID, BOOLEAN, TEXT) TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 3. HARDEN BULK DELETION: delete_actions_bulk_authorized & delete_actions_bulk
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.delete_actions_bulk_authorized(UUID[], BOOLEAN);
DROP FUNCTION IF EXISTS public.delete_actions_bulk_authorized(UUID[], BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS public.delete_actions_bulk(UUID[], BOOLEAN);
DROP FUNCTION IF EXISTS public.delete_actions_bulk(UUID[], BOOLEAN, TEXT);

CREATE OR REPLACE FUNCTION public.delete_actions_bulk_authorized(
  p_action_ids UUID[],
  p_allow_closed BOOLEAN DEFAULT false,
  p_portal_context TEXT DEFAULT 'action_register'
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

        IF lower(trim(coalesce(p_portal_context, 'action_register'))) = 'my_actions' THEN
          IF NOT (v_assigned_to = v_caller_id OR v_is_assignee) THEN
            RETURN jsonb_build_object(
              'success', false,
              'deleted_count', 0,
              'failed_ids', ARRAY[v_curr_id::TEXT],
              'error', 'Unauthorized: Action ' || v_curr_id::TEXT || ' is not assigned to caller'
            );
          END IF;

          IF lower(trim(coalesce(v_status, ''))) <> 'closed' THEN
            RETURN jsonb_build_object(
              'success', false,
              'deleted_count', 0,
              'failed_ids', ARRAY[v_curr_id::TEXT],
              'error', 'Unauthorized: Staff members can only delete closed actions from My Actions. Action ' || v_curr_id::TEXT || ' is not closed.'
            );
          END IF;
        ELSE
          IF NOT v_is_creator THEN
            RETURN jsonb_build_object(
              'success', false,
              'deleted_count', 0,
              'failed_ids', ARRAY[v_curr_id::TEXT],
              'error', 'Unauthorized: Only the creator can delete action ' || v_curr_id::TEXT || ' from Action Register.'
            );
          END IF;
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
        jsonb_build_object('action_id', v_curr_id, 'previous_status', v_status, 'portal_context', p_portal_context, 'bulk', true)
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

GRANT EXECUTE ON FUNCTION public.delete_actions_bulk_authorized(UUID[], BOOLEAN, TEXT) TO authenticated, service_role;

-- Maintain alias for delete_actions_bulk
CREATE OR REPLACE FUNCTION public.delete_actions_bulk(
  p_action_ids UUID[],
  p_allow_closed BOOLEAN DEFAULT false,
  p_portal_context TEXT DEFAULT 'action_register'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  RETURN public.delete_actions_bulk_authorized(p_action_ids, p_allow_closed, p_portal_context);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_actions_bulk(UUID[], BOOLEAN, TEXT) TO authenticated, service_role;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;
