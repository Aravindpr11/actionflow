-- ============================================================================
-- Migration: 20261105000002_action_assignees_tenant_and_status_validation.sql
-- Description: Enforce strict tenant isolation, active status, and manager
--              authority validation on action_assignees before insert/update.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.validate_action_assignee_before_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_action_org UUID;
  v_profile_org UUID;
  v_profile_active BOOLEAN;
  v_profile_status VARCHAR(50);
  v_caller_id UUID;
  v_is_platform BOOLEAN;
BEGIN
  v_caller_id := auth.uid();
  v_is_platform := public.is_platform_admin();

  -- 1. Ensure action exists and fetch its organization
  SELECT organization_id INTO v_action_org
  FROM public.actions WHERE id = NEW.action_id;

  IF v_action_org IS NULL THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Action % does not exist.', NEW.action_id;
  END IF;

  -- 2. Organization match
  IF NEW.organization_id != v_action_org THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Assignee organization does not match action organization.';
  END IF;

  -- 3. Profile existence, organization match, and active status
  SELECT organization_id, is_active, status
  INTO v_profile_org, v_profile_active, v_profile_status
  FROM public.profiles WHERE id = NEW.profile_id;

  IF v_profile_org IS NULL OR v_profile_org != v_action_org THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Assigned profile does not belong to this organization.';
  END IF;

  IF v_profile_active IS NOT TRUE OR v_profile_status != 'active' THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Assigned user is inactive or not approved.';
  END IF;

  -- 4. Caller authorization (if caller is authenticated)
  IF v_caller_id IS NOT NULL AND NOT v_is_platform THEN
    IF NOT app_private.can_manage_action(NEW.action_id) THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Caller is not authorized to manage assignees for this action.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_action_assignee_before_write ON public.action_assignees;
CREATE TRIGGER trg_validate_action_assignee_before_write
  BEFORE INSERT OR UPDATE ON public.action_assignees
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_action_assignee_before_write();

REVOKE ALL ON FUNCTION public.validate_action_assignee_before_write() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.validate_action_assignee_before_write() TO authenticated, service_role;

