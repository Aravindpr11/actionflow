-- Migration: 20261107000004_notifications_realtime_and_events.sql
-- Description: Expand notification event types, enable Supabase Realtime, provide safe creation RPC, and harden RLS.

-- 1. Expand event_type check constraint on public.notifications
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_event_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_event_type_check CHECK (event_type IN (
    -- Action events
    'action_assigned',
    'action_forwarded',
    'contributor_added',
    'subtask_assigned',
    'subtask_delegated',
    'status_changed',
    'action_updated',
    'action_completed',
    'action_reopened',
    'due_date_approaching',
    'action_overdue',
    -- Request events
    'request_submitted',
    'request_assigned',
    'request_approved',
    'request_rejected',
    'request_forwarded',
    'request_completed',
    -- Calendar events
    'calendar_event_assigned',
    'calendar_event_updated',
    'calendar_event_reminder',
    -- System events
    'system_alert',
    'announcement',
    'general'
));

-- 2. Add public.notifications to supabase_realtime publication
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
      AND schemaname = 'public' 
      AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
END $$;

-- 3. Set replica identity to FULL for notifications
ALTER TABLE public.notifications REPLICA IDENTITY FULL;

-- 4. Secure RPC for creating notifications without PostgREST RLS .select() cross-user trap
CREATE OR REPLACE FUNCTION public.create_app_notification(
    p_user_id UUID,
    p_organization_id UUID,
    p_title TEXT,
    p_message TEXT,
    p_event_type TEXT,
    p_action_id TEXT DEFAULT NULL,
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_caller_org_id UUID;
    v_recipient_org_id UUID;
    v_new_id UUID;
    v_existing_id UUID;
    v_created_at TIMESTAMPTZ;
BEGIN
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required to send notifications';
    END IF;

    -- Validate caller active membership & get caller org
    SELECT organization_id INTO v_caller_org_id
    FROM public.profiles
    WHERE id = v_caller_id AND is_active = TRUE;

    IF v_caller_org_id IS NULL THEN
        RAISE EXCEPTION 'Caller is not an active profile';
    END IF;

    -- Target organization must match caller organization (strict tenant isolation)
    IF p_organization_id IS NOT NULL AND p_organization_id != v_caller_org_id THEN
        RAISE EXCEPTION 'Cross-organization notification prohibited';
    END IF;

    -- Validate recipient active membership & org match
    SELECT organization_id INTO v_recipient_org_id
    FROM public.profiles
    WHERE id = p_user_id AND is_active = TRUE;

    IF v_recipient_org_id IS NULL OR v_recipient_org_id != v_caller_org_id THEN
        RAISE EXCEPTION 'Recipient does not belong to the same active organization';
    END IF;

    -- Idempotency check: return existing record if key matches
    IF p_idempotency_key IS NOT NULL AND p_idempotency_key != '' THEN
        SELECT id, created_at INTO v_existing_id, v_created_at
        FROM public.notifications
        WHERE user_id = p_user_id AND idempotency_key = p_idempotency_key
        LIMIT 1;

        IF v_existing_id IS NOT NULL THEN
            RETURN jsonb_build_object(
                'id', v_existing_id,
                'user_id', p_user_id,
                'organization_id', v_caller_org_id,
                'title', p_title,
                'message', p_message,
                'event_type', p_event_type,
                'action_id', p_action_id,
                'is_read', false,
                'idempotency_key', p_idempotency_key,
                'created_at', v_created_at,
                'is_duplicate', true
            );
        END IF;
    END IF;

    -- Insert notification
    INSERT INTO public.notifications (
        user_id,
        organization_id,
        title,
        message,
        event_type,
        action_id,
        is_read,
        idempotency_key,
        created_at
    ) VALUES (
        p_user_id,
        v_caller_org_id,
        p_title,
        p_message,
        p_event_type,
        p_action_id,
        FALSE,
        p_idempotency_key,
        timezone('utc'::text, now())
    )
    RETURNING id, created_at INTO v_new_id, v_created_at;

    RETURN jsonb_build_object(
        'id', v_new_id,
        'user_id', p_user_id,
        'organization_id', v_caller_org_id,
        'title', p_title,
        'message', p_message,
        'event_type', p_event_type,
        'action_id', p_action_id,
        'is_read', false,
        'idempotency_key', p_idempotency_key,
        'created_at', v_created_at,
        'is_duplicate', false
    );
END;
$$;

COMMENT ON FUNCTION public.create_app_notification(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT)
IS 'Creates an in-app notification securely enforcing active organization membership. Returns the created notification payload.';

REVOKE ALL ON FUNCTION public.create_app_notification(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_app_notification(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

-- 5. Harden and update direct INSERT RLS policy on public.notifications
DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON public.notifications;
CREATE POLICY "Authenticated users can insert notifications"
    ON public.notifications FOR INSERT
    TO authenticated
    WITH CHECK (
        organization_id IS NOT NULL
        AND organization_id = (
            SELECT p.organization_id 
            FROM public.profiles p 
            WHERE p.id = auth.uid() AND p.is_active = TRUE
        )
        AND public.is_valid_notification_recipient(user_id, organization_id)
    );

-- 6. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
