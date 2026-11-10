-- ============================================================================
-- Migration: 20260921000009_safe_test_user_cleanup.sql
-- Description: Safely cleans up orphan/abandoned test auth users while strictly
-- protecting core platform and tenant accounts.
-- ============================================================================

DO $$
DECLARE
  v_orphan_id UUID := '9ed6de5d-ce77-43eb-a227-973f391e9155'::UUID;
  v_orphan_email TEXT;
BEGIN
  -- 1. Verify target user
  SELECT email INTO v_orphan_email FROM auth.users WHERE id = v_orphan_id;

  IF v_orphan_email IS NOT NULL THEN
    -- Ensure target is NOT one of the 4 protected accounts
    IF v_orphan_email IN (
      'arvin.pr1112@gmail.com',
      'aravind11.sobha@gmail.com',
      'webonant@gmail.com',
      'aravindpr.1111@gmail.com'
    ) THEN
      RAISE EXCEPTION 'CRITICAL: Attempted to delete protected core account %', v_orphan_email;
    END IF;

    -- Ensure target has NO assigned actions or created actions
    IF EXISTS (SELECT 1 FROM public.actions WHERE assigned_to = v_orphan_id OR created_by = v_orphan_id) THEN
      RAISE EXCEPTION 'Safety check failed: User % has action dependencies.', v_orphan_email;
    END IF;

    -- Clean up any residual records if any exist
    DELETE FROM public.team_members WHERE profile_id = v_orphan_id;
    DELETE FROM public.manager_scopes WHERE manager_profile_id = v_orphan_id;
    DELETE FROM public.account_requests WHERE auth_user_id = v_orphan_id;
    DELETE FROM public.profiles WHERE id = v_orphan_id;

    -- Delete from auth.users
    DELETE FROM auth.users WHERE id = v_orphan_id;

    RAISE NOTICE 'Successfully cleaned up orphan test user % (%)', v_orphan_email, v_orphan_id;
  ELSE
    RAISE NOTICE 'Orphan test user % already cleaned up.', v_orphan_id;
  END IF;
END $$;

