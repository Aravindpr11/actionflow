-- ============================================================================
-- Migration: 20260923000002_allow_closed_delete_in_my_actions.sql
-- Description:
--   Enhance delete_action_authorized RPC to accept optional p_allow_closed BOOLEAN (default false).
--   When p_allow_closed is true (e.g. Manager deleting from My Actions), closed status
--   does not block deletion while maintaining full tenant isolation, role check,
--   scope authorization, and cascade deletion of related child records.
-- ============================================================================

-- Drop 1-argument function signature if necessary to avoid ambiguous signature conflicts
DROP FUNCTION IF EXISTS public.delete_action_authorized(UUID);

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
  v_org_id       UUID;
  v_dept_id      UUID;
  v_site_id      UUID;
  v_status       TEXT;
  v_caller_org   UUID;
  v_is_admin     BOOLEAN;
  v_is_manager   BOOLEAN;
  v_is_platform  BOOLEAN;
BEGIN
  -- 1. Require authenticated caller
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Authentication required');
  END IF;

  -- 2. Fetch action existence, tenant, and scope fields
  SELECT organization_id, department_id, site_id, status
    INTO v_org_id, v_dept_id, v_site_id, v_status
    FROM public.actions
   WHERE id = p_action_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action not found');
  END IF;

  -- 3. Resolve caller's organization using existing helper
  v_caller_org := public.get_my_organization_id();

  -- 4. Tenant Isolation Check
  IF v_caller_org IS NULL OR v_org_id IS DISTINCT FROM v_caller_org THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Tenant isolation violation');
  END IF;

  -- 5. Role Authorization
  v_is_admin    := public.is_admin();
  v_is_manager  := public.is_manager();
  v_is_platform := public.is_platform_admin();

  IF NOT (v_is_admin OR v_is_manager OR v_is_platform) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Manager role required to delete action');
  END IF;

  -- 6. Manager Scope Authorization
  IF v_is_manager AND NOT v_is_admin AND NOT v_is_platform THEN
    IF NOT public.is_manager_of_scope(v_dept_id, v_site_id) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Manager scope does not cover this action''s department and site');
    END IF;
  END IF;

  -- 7. Closed Action Protection: retained for HSE audit/compliance (unless caller explicitly authorized closed deletion e.g. from My Actions)
  IF NOT p_allow_closed AND lower(trim(coalesce(v_status, ''))) = 'closed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLOSED_ACTION');
  END IF;

  -- 8. Safe cascade delete associated child records
  DELETE FROM public.action_follow_ups WHERE action_id = p_action_id;
  DELETE FROM public.action_contributors WHERE action_id = p_action_id;
  DELETE FROM public.action_assignees WHERE action_id = p_action_id;
  DELETE FROM public.action_progress_updates WHERE action_id = p_action_id;

  -- 9. Delete the action record
  DELETE FROM public.actions WHERE id = p_action_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Provide single-argument overload for backwards compatibility
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

-- Grant execution to authenticated users
GRANT EXECUTE ON FUNCTION public.delete_action_authorized(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_action_authorized(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

