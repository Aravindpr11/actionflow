-- Migration: 20260922000003_secure_delete_action_rpc.sql
-- Description: Creates secure delete_action_authorized RPC with tenant isolation, role verification, and closed action retention protection.

CREATE OR REPLACE FUNCTION public.delete_action_authorized(p_action_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID;
  v_status TEXT;
  v_caller_org UUID;
  v_caller_role TEXT;
BEGIN
  -- 1. Check if action exists and fetch tenant and status
  SELECT organization_id, status INTO v_org_id, v_status
  FROM public.actions
  WHERE id = p_action_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action not found');
  END IF;

  -- 2. Fetch authenticated caller's profile
  SELECT organization_id, role INTO v_caller_org, v_caller_role
  FROM public.profiles
  WHERE id = auth.uid();

  -- 3. Tenant Isolation Check
  IF v_caller_org IS NULL OR v_org_id IS DISTINCT FROM v_caller_org THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Tenant isolation violation');
  END IF;

  -- 4. Role Authorization Check (Manager, Admin, Platform Admin only)
  IF lower(coalesce(v_caller_role, '')) NOT IN ('manager', 'admin', 'platform_admin', 'super_admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Manager role required to delete action');
  END IF;

  -- 5. Closed Action Protection: Closed actions are permanently retained for audit/compliance
  IF lower(trim(coalesce(v_status, ''))) = 'closed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLOSED_ACTION');
  END IF;

  -- 6. Cascade delete associated progress history records
  DELETE FROM public.action_progress_updates
  WHERE action_id = p_action_id;

  -- 7. Delete the action record
  DELETE FROM public.actions
  WHERE id = p_action_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Grant execution to authenticated users
GRANT EXECUTE ON FUNCTION public.delete_action_authorized(UUID) TO authenticated;

