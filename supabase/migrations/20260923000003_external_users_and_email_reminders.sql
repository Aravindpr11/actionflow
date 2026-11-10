-- ============================================================================
-- Migration: 20260923000003_external_users_and_email_reminders.sql
-- Description: External action recipients, recipient_type on actions, and
--              persisted action email reminder jobs with strict multi-tenant isolation.
-- ============================================================================

-- 1. Create external_action_recipients table
CREATE TABLE IF NOT EXISTS public.external_action_recipients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  full_name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL,
  company_name VARCHAR(255) DEFAULT '',
  phone VARCHAR(50) DEFAULT '',
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Unique index per organization + lower(email)
CREATE UNIQUE INDEX IF NOT EXISTS idx_ext_recipients_org_email 
ON public.external_action_recipients(organization_id, lower(trim(email)));

CREATE INDEX IF NOT EXISTS idx_ext_recipients_org_active
ON public.external_action_recipients(organization_id, is_active);

-- Enable RLS on external_action_recipients
ALTER TABLE public.external_action_recipients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ext_recipients_select" ON public.external_action_recipients;
CREATE POLICY "ext_recipients_select" ON public.external_action_recipients
FOR SELECT USING (
  organization_id = public.get_my_organization_id() OR public.is_platform_admin()
);

DROP POLICY IF EXISTS "ext_recipients_insert" ON public.external_action_recipients;
CREATE POLICY "ext_recipients_insert" ON public.external_action_recipients
FOR INSERT WITH CHECK (
  (organization_id = public.get_my_organization_id() AND (public.is_manager() OR public.is_admin())) 
  OR public.is_platform_admin()
);

DROP POLICY IF EXISTS "ext_recipients_update" ON public.external_action_recipients;
CREATE POLICY "ext_recipients_update" ON public.external_action_recipients
FOR UPDATE USING (
  (organization_id = public.get_my_organization_id() AND (public.is_manager() OR public.is_admin()))
  OR public.is_platform_admin()
) WITH CHECK (
  (organization_id = public.get_my_organization_id() AND (public.is_manager() OR public.is_admin()))
  OR public.is_platform_admin()
);

DROP POLICY IF EXISTS "ext_recipients_delete" ON public.external_action_recipients;
CREATE POLICY "ext_recipients_delete" ON public.external_action_recipients
FOR DELETE USING (
  (organization_id = public.get_my_organization_id() AND (public.is_manager() OR public.is_admin()))
  OR public.is_platform_admin()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.external_action_recipients TO authenticated, service_role;


-- 2. Alter public.actions to link external recipients & email reminders
ALTER TABLE public.actions
ADD COLUMN IF NOT EXISTS recipient_type VARCHAR(20) NOT NULL DEFAULT 'internal',
ADD COLUMN IF NOT EXISTS external_recipient_id UUID REFERENCES public.external_action_recipients(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS email_reminder_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Constraint check on recipient_type
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_actions_recipient_type'
  ) THEN
    ALTER TABLE public.actions
    ADD CONSTRAINT chk_actions_recipient_type CHECK (recipient_type IN ('internal', 'external'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_actions_recipient_type
ON public.actions(organization_id, recipient_type);

CREATE INDEX IF NOT EXISTS idx_actions_external_recipient
ON public.actions(organization_id, external_recipient_id);


-- 3. Create public.action_email_reminders table
CREATE TABLE IF NOT EXISTS public.action_email_reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  action_id UUID NOT NULL REFERENCES public.actions(id) ON DELETE CASCADE,
  external_recipient_id UUID REFERENCES public.external_action_recipients(id) ON DELETE SET NULL,
  recipient_name VARCHAR(255) NOT NULL,
  recipient_email VARCHAR(255) NOT NULL,
  reminder_type VARCHAR(50) NOT NULL DEFAULT 'pending_action',
  email_subject TEXT NOT NULL,
  email_body TEXT NOT NULL,
  scheduled_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  status VARCHAR(50) NOT NULL DEFAULT 'pending',
  sent_at TIMESTAMPTZ,
  failure_reason TEXT,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_reminder_status CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'cancelled')),
  CONSTRAINT chk_reminder_type CHECK (reminder_type IN ('pending_action', 'follow_up', 'due_date', 'overdue', 'review_ready'))
);

CREATE INDEX IF NOT EXISTS idx_action_email_reminders_status
ON public.action_email_reminders(organization_id, status);

CREATE INDEX IF NOT EXISTS idx_action_email_reminders_action
ON public.action_email_reminders(action_id, status);

-- Enable RLS on action_email_reminders
ALTER TABLE public.action_email_reminders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "action_email_reminders_select" ON public.action_email_reminders;
CREATE POLICY "action_email_reminders_select" ON public.action_email_reminders
FOR SELECT USING (
  organization_id = public.get_my_organization_id() OR public.is_platform_admin()
);

DROP POLICY IF EXISTS "action_email_reminders_insert" ON public.action_email_reminders;
CREATE POLICY "action_email_reminders_insert" ON public.action_email_reminders
FOR INSERT WITH CHECK (
  (organization_id = public.get_my_organization_id() AND (public.is_manager() OR public.is_admin()))
  OR public.is_platform_admin()
);

DROP POLICY IF EXISTS "action_email_reminders_update" ON public.action_email_reminders;
CREATE POLICY "action_email_reminders_update" ON public.action_email_reminders
FOR UPDATE USING (
  (organization_id = public.get_my_organization_id() AND (public.is_manager() OR public.is_admin()))
  OR public.is_platform_admin()
) WITH CHECK (
  (organization_id = public.get_my_organization_id() AND (public.is_manager() OR public.is_admin()))
  OR public.is_platform_admin()
);

DROP POLICY IF EXISTS "action_email_reminders_delete" ON public.action_email_reminders;
CREATE POLICY "action_email_reminders_delete" ON public.action_email_reminders
FOR DELETE USING (
  (organization_id = public.get_my_organization_id() AND (public.is_manager() OR public.is_admin()))
  OR public.is_platform_admin()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.action_email_reminders TO authenticated, service_role;


-- 4. Update fn_validate_action_before_write() trigger function
CREATE OR REPLACE FUNCTION public.fn_validate_action_before_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
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
    -- Internal recipient mode: clear external_recipient_id & email reminder
    NEW.external_recipient_id := NULL;
    NEW.email_reminder_enabled := FALSE;

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


-- 5. Trigger for automated pending email reminder creation & cancellation
CREATE OR REPLACE FUNCTION public.fn_handle_action_email_reminder()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_ext_name VARCHAR(255);
  v_ext_email VARCHAR(255);
  v_action_num VARCHAR(50);
  v_subject_text TEXT;
  v_body_text TEXT;
BEGIN
  -- A. When Email Reminder is switched OFF, or Action is Closed: Cancel pending jobs
  IF (TG_OP = 'UPDATE' AND (NEW.email_reminder_enabled = FALSE OR NEW.status = 'Closed' OR NEW.recipient_type = 'internal')) THEN
    UPDATE public.action_email_reminders
    SET status = 'cancelled', updated_at = now()
    WHERE action_id = NEW.id AND status = 'pending';
    RETURN NEW;
  END IF;

  -- B. When Email Reminder is ON for External Recipient: Create pending reminder
  IF NEW.recipient_type = 'external' AND NEW.email_reminder_enabled = TRUE AND NEW.status != 'Closed' THEN
    -- Check if this is an INSERT or an UPDATE where reminder was just enabled / changed
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND (OLD.email_reminder_enabled = FALSE OR OLD.external_recipient_id IS DISTINCT FROM NEW.external_recipient_id)) THEN
      SELECT full_name, email INTO v_ext_name, v_ext_email
      FROM public.external_action_recipients
      WHERE id = NEW.external_recipient_id;

      IF v_ext_email IS NOT NULL AND trim(v_ext_email) != '' THEN
        v_action_num := COALESCE(NEW.action_number, NEW.id::text);
        v_subject_text := 'ActionFlow Reminder: Action Assigned [' || v_action_num || '] - ' || NEW.title;
        v_body_text := 'Dear ' || v_ext_name || ',' || E'\n\n' ||
          'You have been assigned to an Action in ActionFlow.' || E'\n\n' ||
          '--------------------------------------------------' || E'\n' ||
          'Action ID: ' || v_action_num || E'\n' ||
          'Subject: ' || NEW.title || E'\n' ||
          'Action Required / Instruction: ' || NEW.action_required || E'\n' ||
          'Status: ' || NEW.status || ' (' || NEW.percent_complete || '%)' || E'\n' ||
          'Priority: ' || NEW.priority || E'\n' ||
          'Date Raised: ' || to_char(NEW.date_raised, 'DD Mon YYYY') || E'\n' ||
          'Start Date: ' || to_char(NEW.start_date, 'DD Mon YYYY') || E'\n' ||
          'Target / Due Date: ' || to_char(NEW.target_date, 'DD Mon YYYY') || E'\n' ||
          CASE WHEN NEW.next_follow_up_date IS NOT NULL 
               THEN 'Next Follow-up Date: ' || to_char(NEW.next_follow_up_date, 'DD Mon YYYY') || E'\n' 
               ELSE '' END ||
          '--------------------------------------------------' || E'\n\n' ||
          'Please review this action and fulfill the necessary requirements.' || E'\n\n' ||
          'ActionFlow Automated Notification System';

        INSERT INTO public.action_email_reminders (
          organization_id,
          action_id,
          external_recipient_id,
          recipient_name,
          recipient_email,
          reminder_type,
          email_subject,
          email_body,
          scheduled_at,
          status,
          created_by
        ) VALUES (
          NEW.organization_id,
          NEW.id,
          NEW.external_recipient_id,
          v_ext_name,
          v_ext_email,
          'pending_action',
          v_subject_text,
          v_body_text,
          now(),
          'pending',
          NEW.created_by
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_action_email_reminder ON public.actions;
CREATE TRIGGER trg_action_email_reminder
AFTER INSERT OR UPDATE ON public.actions
FOR EACH ROW EXECUTE FUNCTION public.fn_handle_action_email_reminder();

-- 6. Reload schema cache for PostgREST
NOTIFY pgrst, 'reload schema';

