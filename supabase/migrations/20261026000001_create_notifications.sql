-- Migration: 20261026000001_create_notifications.sql
-- Description: Create dedicated notifications table for in-app HSSE alerts and reminders.
-- Strict Privacy Rules:
-- 1. auth.uid() = user_id for SELECT, UPDATE, DELETE (strict user-isolation).
-- 2. Authenticated users can insert notifications addressed to specific users ONLY when authorized
--    by official action workflows (manager-to-staff assignment/reopen, staff-to-manager progress/completion).
-- 3. Cross-organization notification injection and unauthorized same-organization spam are strictly blocked.
-- 4. Idempotency key prevents duplicate notifications on rebuilds, retries, or repetitive saves.
-- 5. Isolated from personal calendar tasks and external documents.

CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    event_type TEXT NOT NULL CHECK (event_type IN (
        'action_assigned',
        'due_date_approaching',
        'action_overdue',
        'status_changed',
        'action_updated',
        'action_completed',
        'action_reopened'
    )),
    action_id TEXT,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    idempotency_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    read_at TIMESTAMPTZ
);

-- Enable Row Level Security
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- Security Definer Helpers for Notification Authorization
-- These execute as SECURITY DEFINER to bypass caller RLS visibility restrictions
-- on public.profiles without recursion or leaking PII.
-- ----------------------------------------------------------------------------

-- Helper 1: Verify recipient is an active member of the specified organization
CREATE OR REPLACE FUNCTION public.is_valid_notification_recipient(
    p_user_id UUID,
    p_organization_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_user_id
      AND organization_id = p_organization_id
      AND is_active = TRUE
  );
$$;

COMMENT ON FUNCTION public.is_valid_notification_recipient(UUID, UUID)
IS 'Returns true if recipient user exists, belongs to the specified organization, and is active. Used by notifications RLS.';

REVOKE ALL ON FUNCTION public.is_valid_notification_recipient(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_valid_notification_recipient(UUID, UUID) TO authenticated, service_role;

-- Helper 2: Check if a user is an active manager or admin within an organization
CREATE OR REPLACE FUNCTION public.is_org_manager_or_admin(
    p_user_id UUID,
    p_organization_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    JOIN public.roles r ON p.role_id = r.id
    WHERE p.id = p_user_id
      AND p.organization_id = p_organization_id
      AND r.code IN ('admin', 'manager')
      AND p.is_active = TRUE
  );
$$;

COMMENT ON FUNCTION public.is_org_manager_or_admin(UUID, UUID)
IS 'Returns true if user is an active admin or manager in the specified organization. Used by notifications RLS.';

REVOKE ALL ON FUNCTION public.is_org_manager_or_admin(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_org_manager_or_admin(UUID, UUID) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- RLS Policies
-- ----------------------------------------------------------------------------

-- 1. SELECT: Users can ONLY see their own notifications
DROP POLICY IF EXISTS "Users can view their own notifications" ON public.notifications;
CREATE POLICY "Users can view their own notifications"
    ON public.notifications FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

-- 2. INSERT: Authenticated users can insert notifications:
--    - Self-reminders for approaching/overdue target dates
--    - Official Action workflow notifications between authorized managers and assignees
DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON public.notifications;
CREATE POLICY "Authenticated users can insert notifications"
    ON public.notifications FOR INSERT
    TO authenticated
    WITH CHECK (
        -- 1. Self-notifications (due date reminders and overdue alerts)
        (
            auth.uid() = user_id
            AND organization_id IS NOT NULL
            AND organization_id = (
                SELECT p.organization_id 
                FROM public.profiles p 
                WHERE p.id = auth.uid() AND p.is_active = TRUE
            )
        )
        OR
        -- 2. Official Action workflow notifications (Manager <-> Staff)
        (
            organization_id IS NOT NULL
            -- Caller must belong to the specified organization and be active
            AND organization_id = (
                SELECT p.organization_id 
                FROM public.profiles p 
                WHERE p.id = auth.uid() AND p.is_active = TRUE
            )
            -- Recipient must also belong to the exact same organization and be active
            AND public.is_valid_notification_recipient(user_id, organization_id)
            -- Must be tied to a valid official action within the same organization
            AND action_id IS NOT NULL
            AND EXISTS (
                SELECT 1 
                FROM public.actions a
                WHERE (a.id::text = notifications.action_id OR a.action_number = notifications.action_id)
                  AND a.organization_id = notifications.organization_id
                  AND (
                      -- Scenario A: Manager/creator notifying assignee (assignment, status change, reopen)
                      (
                          (
                              a.created_by = auth.uid() 
                              OR public.is_org_manager_or_admin(auth.uid(), notifications.organization_id)
                          )
                          AND (
                              a.assigned_to = notifications.user_id
                              OR EXISTS (
                                  SELECT 1 FROM public.action_assignees aa
                                  WHERE aa.action_id = a.id AND aa.profile_id = notifications.user_id
                              )
                          )
                      )
                      OR
                      -- Scenario B: Staff assignee notifying manager/creator (progress update, completion)
                      (
                          (
                              a.assigned_to = auth.uid()
                              OR EXISTS (
                                  SELECT 1 FROM public.action_assignees aa
                                  WHERE aa.action_id = a.id AND aa.profile_id = auth.uid()
                              )
                          )
                          AND (
                              a.created_by = notifications.user_id
                              OR EXISTS (
                                  SELECT 1 FROM public.action_assignees aa
                                  WHERE aa.action_id = a.id AND aa.assigned_by = notifications.user_id
                              )
                              OR public.is_org_manager_or_admin(notifications.user_id, notifications.organization_id)
                          )
                      )
                  )
            )
        )
    );

-- 3. UPDATE: Users can ONLY update their own notifications (e.g. mark read/unread)
DROP POLICY IF EXISTS "Users can update their own notifications" ON public.notifications;
CREATE POLICY "Users can update their own notifications"
    ON public.notifications FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 4. DELETE: Users can ONLY delete their own notifications
DROP POLICY IF EXISTS "Users can delete their own notifications" ON public.notifications;
CREATE POLICY "Users can delete their own notifications"
    ON public.notifications FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- Partial unique index on idempotency_key to prevent duplicates at the database level
CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_idempotency_key
    ON public.notifications(idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- Index for fast user retrieval ordered by creation time
CREATE INDEX IF NOT EXISTS idx_notifications_user_created_at
    ON public.notifications(user_id, created_at DESC);

-- Permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notifications TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notifications TO service_role;
