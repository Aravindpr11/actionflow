-- ============================================================================
-- Migration: 20260925000001_action_email_reminder_persistence.sql
-- Description: Supports explicit multi-schedule, multi-recipient email reminder
--              persistence for both internal and external recipients.
--              Preserves existing external reminders, enforces recipient integrity,
--              and stops automatic reminder broadcasts on assignment.
-- ============================================================================

-- 1. Upgrade action_email_reminders schema
ALTER TABLE public.action_email_reminders
    ADD COLUMN IF NOT EXISTS reminder_group_id VARCHAR(100),
    ADD COLUMN IF NOT EXISTS recipient_type VARCHAR(20) NOT NULL DEFAULT 'internal'
        CHECK (recipient_type IN ('internal', 'external')),
    ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

-- Ensure external_recipient_id is nullable (to allow internal recipients)
ALTER TABLE public.action_email_reminders
    ALTER COLUMN external_recipient_id DROP NOT NULL;

-- 2. Safely backfill existing data
-- Existing rows created under migration 20260923000003 are external recipient reminders
UPDATE public.action_email_reminders
SET recipient_type = 'external'
WHERE external_recipient_id IS NOT NULL;

-- Existing rows without a reminder group ID receive a legacy group identifier
UPDATE public.action_email_reminders
SET reminder_group_id = 'legacy-' || id::text
WHERE reminder_group_id IS NULL;

-- 3. Recipient Integrity Constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_reminder_recipient_integrity'
  ) THEN
    ALTER TABLE public.action_email_reminders
    ADD CONSTRAINT chk_reminder_recipient_integrity CHECK (
      (recipient_type = 'external' AND external_recipient_id IS NOT NULL) OR
      (recipient_type = 'internal' AND external_recipient_id IS NULL)
    );
  END IF;
END $$;

-- 4. Idempotency & Lookup Indexes
-- Prevent duplicate pending reminder dispatches for the exact same action + schedule + recipient
CREATE UNIQUE INDEX IF NOT EXISTS idx_action_reminders_unique_pending
ON public.action_email_reminders(action_id, reminder_group_id, lower(trim(recipient_email)))
WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_action_email_reminders_group_status
ON public.action_email_reminders(action_id, reminder_group_id, status);

CREATE INDEX IF NOT EXISTS idx_action_email_reminders_profile
ON public.action_email_reminders(organization_id, profile_id);

-- 5. Update fn_validate_action_before_write() to allow email_reminder_enabled for internal actions
CREATE OR REPLACE FUNCTION public.fn_validate_action_before_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_org_id UUID;
  v_is_platform BOOLEAN := false;
  v_is_company_admin BOOLEAN := false;
  v_is_mgr BOOLEAN := false;
  v_dept_active BOOLEAN;
  v_dept_org UUID;
  v_site_active BOOLEAN;
  v_site_org UUID;
  v_assignee_org UUID;
  v_assignee_active BOOLEAN;
  v_assignee_status VARCHAR(50);
  v_ext_org UUID;
  v_ext_active BOOLEAN;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NOT NULL THEN
    v_is_platform := public.is_platform_admin();
    v_is_company_admin := public.is_admin();
    v_is_mgr := public.is_manager();
    v_caller_org_id := public.get_my_organization_id();
  END IF;

  -- Date synchronizations
  NEW.created_date := COALESCE(NEW.created_date, NEW.date_raised, CURRENT_DATE);
  NEW.date_raised := COALESCE(NEW.date_raised, NEW.created_date, CURRENT_DATE);
  NEW.start_date := COALESCE(NEW.start_date, NEW.date_raised, CURRENT_DATE);
  NEW.due_date := COALESCE(NEW.due_date, NEW.target_date);
  NEW.target_date := COALESCE(NEW.target_date, NEW.due_date);

  -- A. Enforce Organization Binding
  IF NOT v_is_platform THEN
    IF v_caller_org_id IS NULL THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: User is not linked to an active organization.';
    END IF;
    NEW.organization_id := v_caller_org_id;
  END IF;

  -- B. Auto-bind created_by on INSERT
  IF TG_OP = 'INSERT' THEN
    IF NEW.created_by IS NULL THEN
      NEW.created_by := v_caller_id;
    ELSIF NOT v_is_platform AND NEW.created_by != v_caller_id THEN
      NEW.created_by := v_caller_id;
    END IF;
  END IF;

  -- C. Validate Department (must exist, belong to org, and be active)
  SELECT is_active, organization_id INTO v_dept_active, v_dept_org
  FROM public.departments WHERE id = NEW.department_id;
  IF v_dept_org IS NULL OR v_dept_org != NEW.organization_id THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Department does not belong to this organization.';
  END IF;
  IF v_dept_active IS NOT TRUE THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive department.';
  END IF;

  -- D. Validate Site (must exist, belong to org, and be active)
  SELECT is_active, organization_id INTO v_site_active, v_site_org
  FROM public.sites WHERE id = NEW.site_id;
  IF v_site_org IS NULL OR v_site_org != NEW.organization_id THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Site does not belong to this organization.';
  END IF;
  IF v_site_active IS NOT TRUE THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive site.';
  END IF;

  -- E. Manager Scope Enforcement
  IF v_is_mgr AND NOT v_is_company_admin AND NOT v_is_platform THEN
    IF NOT public.is_manager_of_scope(NEW.department_id, NEW.site_id) THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: You do not have manager authority over this department and site scope.';
    END IF;
  END IF;

  -- F. Recipient Type & Assignment Validation
  IF NEW.recipient_type = 'external' THEN
    -- External recipient mode: clear internal assigned_to to avoid FK violation
    NEW.assigned_to := NULL;
    IF NEW.external_recipient_id IS NULL THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: External recipient ID is required when recipient type is external.';
    END IF;
    SELECT organization_id, is_active
    INTO v_ext_org, v_ext_active
    FROM public.external_action_recipients WHERE id = NEW.external_recipient_id;

    IF v_ext_org IS NULL OR v_ext_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: External recipient does not belong to this organization.';
    END IF;
    IF v_ext_active IS NOT TRUE THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: External recipient is inactive.';
    END IF;
  ELSE
    -- Internal recipient mode: clear external_recipient_id
    NEW.external_recipient_id := NULL;
    -- Note: NEW.email_reminder_enabled is preserved (not forced to FALSE)

    -- Validate internal Assignee (if assigned_to is specified)
    IF NEW.assigned_to IS NOT NULL THEN
      SELECT organization_id, is_active, status
      INTO v_assignee_org, v_assignee_active, v_assignee_status
      FROM public.profiles WHERE id = NEW.assigned_to;

      IF v_assignee_org IS NULL OR v_assignee_org != NEW.organization_id THEN
        RAISE EXCEPTION 'ActionFlow Security Violation: Assigned user does not belong to this organization.';
      END IF;
      IF v_assignee_active IS NOT TRUE OR v_assignee_status != 'active' THEN
        RAISE EXCEPTION 'ActionFlow Validation Error: Assigned user is inactive or not approved.';
      END IF;
    END IF;
  END IF;

  -- G. Auto-maintain history log
  IF TG_OP = 'INSERT' THEN
    IF NEW.history IS NULL OR jsonb_array_length(NEW.history) = 0 THEN
      NEW.history := jsonb_build_array(
        jsonb_build_object(
          'timestamp', now(),
          'action', 'Action created',
          'actor_id', v_caller_id,
          'status', NEW.status
        )
      );
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.updated_at := now();
    IF NEW.status IS DISTINCT FROM OLD.status OR NEW.percent_complete IS DISTINCT FROM OLD.percent_complete THEN
      NEW.history := COALESCE(OLD.history, '[]'::jsonb) || jsonb_build_object(
        'timestamp', now(),
        'action', format('Status changed to %s (%s%%)', NEW.status, NEW.percent_complete),
        'actor_id', v_caller_id,
        'old_status', OLD.status,
        'new_status', NEW.status,
        'old_percent', OLD.percent_complete,
        'new_percent', NEW.percent_complete
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- 6. Update fn_handle_action_email_reminder()
-- Handles bulk cancellation when email reminders are turned OFF or when an action is Closed.
-- Does NOT auto-create reminders simply on assignment (Manager configuration is authoritative).
-- Does NOT cancel reminders merely because recipient_type is 'internal'.
CREATE OR REPLACE FUNCTION public.fn_handle_action_email_reminder()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  -- When Email Reminder is switched OFF or Action is Closed: Cancel pending jobs
  IF (TG_OP = 'UPDATE' AND (NEW.email_reminder_enabled = FALSE OR NEW.status = 'Closed')) THEN
    UPDATE public.action_email_reminders
    SET status = 'cancelled', updated_at = now()
    WHERE action_id = NEW.id AND status = 'pending';
  END IF;

  RETURN NEW;
END;
$$;

-- Reload schema cache for PostgREST
NOTIFY pgrst, 'reload schema';
