-- ============================================================================
-- Migration: 20261107000002_staff_delete_closed_action.sql
-- Description:
--   1. Ensures deleted_at and deleted_by audit columns and status check constraint
--      exist on public.actions for safe soft-deletion.
--   2. Upgrades delete_action_authorized RPC to allow Staff members to soft-delete
--      strictly closed actions assigned to them or created by them.
--   3. Enforces database-level authorization guard preventing Staff from deleting
--      open, in-progress, or active actions.
--   4. Upgrades delete_actions_bulk_authorized RPC to support bulk soft-deletion of
--      closed actions by Staff with the same authorization guards.
--   5. Preserves soft-deletion behavior (status = 'Deleted', audit logs, retention
--      of foreign keys and historical progress).
--   6. Preserves all Manager multi-scoping, Admin authority, and Tenant isolation.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Status Check Constraint & Audit Columns
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  ALTER TABLE public.actions DROP CONSTRAINT IF EXISTS actions_status_check;
  ALTER TABLE public.actions ADD CONSTRAINT actions_status_check
    CHECK (status IN (
      'Open',
      'In Progress',
      'Pending Review',
      'Ready for Review',
      'Overdue',
      'Closed',
      'Rejected',
      'Deleted'
    ));
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

ALTER TABLE public.actions
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL DEFAULT NULL;

CREATE INDEX IF NOT EXISTS idx_actions_deleted_at ON public.actions(deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_actions_status_deleted ON public.actions(status);

-- ----------------------------------------------------------------------------
-- 2. Stored Procedure: public.delete_action_authorized (Soft Delete)
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
      -- A. Verify staff user is either creator or assignee
      SELECT EXISTS (
        SELECT 1 FROM public.action_assignees
        WHERE action_id = p_action_id
          AND profile_id = auth.uid()
      ) INTO v_is_assignee;

      IF NOT (v_created_by = auth.uid() OR v_assigned_to = auth.uid() OR v_is_assignee) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: You can only delete actions created by or assigned to you.');
      END IF;

      -- B. Strictly closed actions only for Staff
      IF lower(trim(coalesce(v_status, ''))) <> 'closed' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Staff members can only delete closed actions. Active actions cannot be deleted.');
      END IF;
    END IF;
  END IF;

  -- 6. Closed Action Protection
  IF NOT p_allow_closed AND lower(trim(coalesce(v_status, ''))) = 'closed' THEN
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
-- 3. Stored Procedure: public.delete_actions_bulk_authorized (Soft Delete)
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

    IF NOT p_allow_closed AND lower(trim(coalesce(v_status, ''))) = 'closed' THEN
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
        SELECT EXISTS (
          SELECT 1 FROM public.action_assignees
          WHERE action_id = v_curr_id
            AND profile_id = v_caller_id
        ) INTO v_is_assignee;

        IF NOT (v_created_by = v_caller_id OR v_assigned_to = v_caller_id OR v_is_assignee) THEN
          RETURN jsonb_build_object(
            'success', false,
            'deleted_count', 0,
            'failed_ids', ARRAY[v_curr_id::TEXT],
            'error', 'Unauthorized: Action ' || v_curr_id::TEXT || ' is not assigned to or created by caller'
          );
        END IF;

        IF lower(trim(coalesce(v_status, ''))) <> 'closed' THEN
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

  -- PHASE 2: Bulk Soft Delete
  UPDATE public.actions
     SET status = 'Deleted',
         deleted_at = timezone('utc'::text, now()),
         deleted_by = v_caller_id,
         updated_at = timezone('utc'::text, now())
   WHERE id = ANY(p_action_ids);

  -- PHASE 3: Audit Log
  FOREACH v_curr_id IN ARRAY p_action_ids LOOP
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
        v_caller_org,
        v_caller_id,
        'ACTION_BULK_SOFT_DELETED',
        'action',
        v_curr_id::TEXT,
        'Action ' || v_curr_id::TEXT || ' bulk soft deleted',
        jsonb_build_object(
          'action_id', v_curr_id,
          'deleted_at', timezone('utc'::text, now())
        )
      );
    EXCEPTION
      WHEN OTHERS THEN NULL;
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
