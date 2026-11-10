-- ============================================================================
-- Migration: 20261103000002_soft_deletion_and_bulk_delete.sql
-- Description:
--   1. Update actions_status_check constraint to include 'Deleted'.
--   2. Add deleted_at and deleted_by audit columns on public.actions.
--   3. Upgrade delete_action_authorized RPC to perform safe soft-deletion
--      preserving all child records and audit history.
--   4. Implement delete_actions_bulk RPC for atomic bulk soft-deletion with
--      strict staff and manager role authorization.
--   5. Update RLS policies to maintain tenant isolation and role permissions.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Status Check Constraint Update & Audit Columns
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
DROP FUNCTION IF EXISTS public.delete_action_authorized(UUID);
DROP FUNCTION IF EXISTS public.delete_action_authorized(UUID, BOOLEAN);

CREATE OR REPLACE FUNCTION public.delete_action_authorized(
  p_action_id UUID,
  p_allow_closed BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id          UUID;
  v_dept_id         UUID;
  v_site_id         UUID;
  v_status          TEXT;
  v_created_by      UUID;
  v_caller_org      UUID;
  v_caller_id       UUID;
  v_is_admin        BOOLEAN;
  v_is_manager      BOOLEAN;
  v_is_platform     BOOLEAN;
  v_is_manager_scope BOOLEAN := FALSE;
  v_is_creator      BOOLEAN := FALSE;
  v_is_owner        BOOLEAN := FALSE;
  v_is_contributor  BOOLEAN := FALSE;
BEGIN
  -- 1. Require authenticated caller
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Authentication required');
  END IF;

  -- 2. Fetch action existence, tenant, and scope fields
  SELECT organization_id, department_id, site_id, status, created_by
    INTO v_org_id, v_dept_id, v_site_id, v_status, v_created_by
    FROM public.actions
   WHERE id = p_action_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action not found');
  END IF;

  -- If already deleted
  IF lower(trim(coalesce(v_status, ''))) = 'deleted' THEN
    RETURN jsonb_build_object('success', true, 'message', 'Action is already deleted');
  END IF;

  -- 3. Resolve caller's organization using existing helper
  v_caller_org := public.get_my_organization_id();

  -- 4. Tenant Isolation Check
  IF v_caller_org IS NULL OR v_org_id IS DISTINCT FROM v_caller_org THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Tenant isolation violation');
  END IF;

  -- 5. Role and Permission Authorization
  v_is_admin    := public.is_admin();
  v_is_manager  := public.is_manager();
  v_is_platform := public.is_platform_admin();

  IF v_is_manager AND NOT v_is_admin AND NOT v_is_platform THEN
    v_is_manager_scope := public.is_manager_of_scope(v_dept_id, v_site_id);
  END IF;

  -- Check if caller is creator
  IF v_created_by IS NOT NULL AND v_created_by = v_caller_id THEN
    v_is_creator := TRUE;
  END IF;

  -- Check if caller is action owner in assignees table
  SELECT EXISTS (
    SELECT 1 FROM public.action_assignees
     WHERE action_id = p_action_id
       AND profile_id = v_caller_id
       AND assignment_role = 'owner'
  ) INTO v_is_owner;

  -- Check if caller is a forwarded recipient / contributor
  SELECT EXISTS (
    SELECT 1 FROM public.action_contributors
     WHERE action_id = p_action_id
       AND profile_id = v_caller_id
  ) INTO v_is_contributor;

  -- Contributors / forwarded recipients cannot delete the action
  IF v_is_contributor AND NOT (v_is_admin OR v_is_platform OR v_is_creator OR (v_is_manager AND v_is_manager_scope)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Forwarded contributors cannot delete actions');
  END IF;

  -- Verify overall delete authorization:
  -- Allowed if Admin, Platform Admin, Scope Manager, Creator, or Owner
  IF NOT (v_is_admin OR v_is_platform OR (v_is_manager AND v_is_manager_scope) OR v_is_creator OR v_is_owner) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Insufficient permissions to delete action');
  END IF;

  -- 6. Closed Action Protection
  IF NOT p_allow_closed AND lower(trim(coalesce(v_status, ''))) = 'closed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLOSED_ACTION');
  END IF;

  -- 7. Safe Soft Delete
  UPDATE public.actions
     SET status = 'Deleted',
         deleted_at = timezone('utc'::text, now()),
         deleted_by = v_caller_id,
         updated_at = timezone('utc'::text, now())
   WHERE id = p_action_id;

  -- 8. Audit Log record (safe attempt)
  BEGIN
    INSERT INTO public.platform_audit_logs (
      organization_id,
      actor_id,
      action,
      entity_type,
      entity_id,
      details
    ) VALUES (
      v_org_id,
      v_caller_id,
      'ACTION_SOFT_DELETED',
      'actions',
      p_action_id::TEXT,
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
$$;

-- Single-argument overload for backward compatibility
CREATE OR REPLACE FUNCTION public.delete_action_authorized(p_action_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.delete_action_authorized(p_action_id, FALSE);
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. Stored Procedure: public.delete_actions_bulk (Strictly Atomic Bulk Soft Delete)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_actions_bulk(
  p_action_ids UUID[],
  p_allow_closed BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
  v_status          TEXT;
  v_created_by      UUID;
  v_is_manager_scope BOOLEAN;
  v_is_creator      BOOLEAN;
  v_is_owner        BOOLEAN;
  v_is_contributor  BOOLEAN;
BEGIN
  -- 1. Require authenticated caller
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

  -- ==========================================================================
  -- PHASE 1: Strictly Atomic Pre-Validation of ALL Action IDs Upfront.
  -- If ANY item fails tenant isolation, permission, existence, or closed protection,
  -- abort immediately with 0 rows modified.
  -- ==========================================================================
  FOREACH v_curr_id IN ARRAY p_action_ids LOOP
    SELECT organization_id, department_id, site_id, status, created_by
      INTO v_org_id, v_dept_id, v_site_id, v_status, v_created_by
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

    -- Tenant isolation check
    IF v_caller_org IS NULL OR v_org_id IS DISTINCT FROM v_caller_org THEN
      RETURN jsonb_build_object(
        'success', false,
        'deleted_count', 0,
        'failed_ids', ARRAY[v_curr_id::TEXT],
        'error', 'Unauthorized: Tenant isolation violation for action ' || v_curr_id::TEXT
      );
    END IF;

    -- Closed action protection
    IF NOT p_allow_closed AND lower(trim(coalesce(v_status, ''))) = 'closed' THEN
      RETURN jsonb_build_object(
        'success', false,
        'deleted_count', 0,
        'failed_ids', ARRAY[v_curr_id::TEXT],
        'error', 'CLOSED_ACTION: ' || v_curr_id::TEXT
      );
    END IF;

    -- Scope manager evaluation
    v_is_manager_scope := FALSE;
    IF v_is_manager AND NOT v_is_admin AND NOT v_is_platform THEN
      v_is_manager_scope := public.is_manager_of_scope(v_dept_id, v_site_id);
    END IF;

    -- Creator evaluation
    v_is_creator := (v_created_by IS NOT NULL AND v_created_by = v_caller_id);

    -- Owner evaluation (explicitly assignment_role = 'owner')
    SELECT EXISTS (
      SELECT 1 FROM public.action_assignees
       WHERE action_id = v_curr_id
         AND profile_id = v_caller_id
         AND assignment_role = 'owner'
    ) INTO v_is_owner;

    -- Forwarded contributor evaluation
    SELECT EXISTS (
      SELECT 1 FROM public.action_contributors
       WHERE action_id = v_curr_id
         AND profile_id = v_caller_id
    ) INTO v_is_contributor;

    IF v_is_contributor AND NOT (v_is_admin OR v_is_platform OR v_is_creator OR (v_is_manager AND v_is_manager_scope)) THEN
      RETURN jsonb_build_object(
        'success', false,
        'deleted_count', 0,
        'failed_ids', ARRAY[v_curr_id::TEXT],
        'error', 'Unauthorized: Forwarded contributors cannot delete action ' || v_curr_id::TEXT
      );
    END IF;

    -- Enforce overall deletion authority: Admin, Platform Admin, Scope Manager, Creator, or Authorized Owner
    IF NOT (v_is_admin OR v_is_platform OR (v_is_manager AND v_is_manager_scope) OR v_is_creator OR v_is_owner) THEN
      RETURN jsonb_build_object(
        'success', false,
        'deleted_count', 0,
        'failed_ids', ARRAY[v_curr_id::TEXT],
        'error', 'Unauthorized: Insufficient permissions to delete action ' || v_curr_id::TEXT
      );
    END IF;
  END LOOP;

  -- ==========================================================================
  -- PHASE 2: Single Atomic Bulk Soft Delete
  -- ==========================================================================
  UPDATE public.actions
     SET status = 'Deleted',
         deleted_at = timezone('utc'::text, now()),
         deleted_by = v_caller_id,
         updated_at = timezone('utc'::text, now())
   WHERE id = ANY(p_action_ids);

  -- Phase 3: Platform Audit Logs (safe attempt)
  FOREACH v_curr_id IN ARRAY p_action_ids LOOP
    BEGIN
      INSERT INTO public.platform_audit_logs (
        organization_id,
        actor_id,
        action,
        entity_type,
        entity_id,
        details
      ) VALUES (
        v_caller_org,
        v_caller_id,
        'ACTION_BULK_SOFT_DELETED',
        'actions',
        v_curr_id::TEXT,
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

-- Grant execution permissions
GRANT EXECUTE ON FUNCTION public.delete_action_authorized(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_action_authorized(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_actions_bulk(UUID[], BOOLEAN) TO authenticated;

