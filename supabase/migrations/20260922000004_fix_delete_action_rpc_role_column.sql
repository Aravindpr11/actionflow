-- Migration: 20260922000004_fix_delete_action_rpc_role_column.sql
-- Description: Fixes delete_action_authorized RPC that incorrectly referenced
--   a non-existent `role` column on profiles.
--
-- Root Cause:
--   The prior RPC (20260922000003) executed:
--     SELECT organization_id, role INTO ... FROM public.profiles WHERE id = auth.uid();
--   However, public.profiles has NO `role` column. Role is stored in the separate
--   `public.roles` table and linked via profiles.role_id (FK). This caused:
--     PostgrestException: column "role" does not exist (code 42703)
--
-- Fix:
--   Replace the raw profiles query with the existing project-standard SECURITY DEFINER
--   helper functions which already perform the correct role JOIN internally:
--     - public.is_admin()             -> true if caller has role code = 'admin'
--     - public.is_manager()           -> true if caller has role code = 'manager'
--     - public.is_platform_admin()    -> true if caller is in platform_admins
--     - public.get_my_organization_id() -> caller's organization_id from profiles
--     - public.is_manager_of_scope(dept_id, site_id) -> validates manager scope
--
-- Authorization enforced:
--   1. Authenticated user (auth.uid() must not be null)
--   2. Same organization / tenant isolation
--   3. Manager, Admin, or Platform Admin role required
--   4. Manager scope authorization: Manager must own a scope covering the action's
--      department + site (Admin and Platform Admin bypass scope check)
--   5. Closed actions cannot be deleted (HSE compliance retention)
--   6. Action must exist (not found → safe error)
--   7. Cross-tenant deletion is rejected at step 2

CREATE OR REPLACE FUNCTION public.delete_action_authorized(p_action_id UUID)
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

  -- 3. Resolve caller's organization using the existing helper (no raw profile.role query)
  v_caller_org := public.get_my_organization_id();

  -- 4. Tenant Isolation Check
  IF v_caller_org IS NULL OR v_org_id IS DISTINCT FROM v_caller_org THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Tenant isolation violation');
  END IF;

  -- 5. Role Authorization — use existing SECURITY DEFINER helpers (they do the JOIN internally)
  v_is_admin    := public.is_admin();
  v_is_manager  := public.is_manager();
  v_is_platform := public.is_platform_admin();

  IF NOT (v_is_admin OR v_is_manager OR v_is_platform) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Manager role required to delete action');
  END IF;

  -- 6. Manager Scope Authorization
  --    Admin and Platform Admin bypass scope check (they have org-wide authority).
  --    Managers must own a scope covering the action's department + site.
  IF v_is_manager AND NOT v_is_admin AND NOT v_is_platform THEN
    IF NOT public.is_manager_of_scope(v_dept_id, v_site_id) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Manager scope does not cover this action''s department and site');
    END IF;
  END IF;

  -- 7. Closed Action Protection: retained for HSE audit/compliance
  IF lower(trim(coalesce(v_status, ''))) = 'closed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLOSED_ACTION');
  END IF;

  -- 8. Cascade delete associated progress history records first
  DELETE FROM public.action_progress_updates
   WHERE action_id = p_action_id;

  -- 9. Delete the action record
  DELETE FROM public.actions
   WHERE id = p_action_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Grant execution to authenticated users
GRANT EXECUTE ON FUNCTION public.delete_action_authorized(UUID) TO authenticated;

