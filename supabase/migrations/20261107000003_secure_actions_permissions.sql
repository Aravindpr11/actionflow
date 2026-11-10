-- ============================================================================
-- Migration: 20261107000003_secure_actions_permissions.sql
-- Description: Reconcile operational column SELECT privileges on public.actions.
--
-- Root cause identified during read-only audit (7 Nov 2026):
--   Migration 20261017000001_action_subtasks_security.sql executed:
--     REVOKE SELECT ON public.actions FROM authenticated, anon, public;
--     GRANT SELECT (38 columns) ON public.actions TO authenticated;
--
--   Five operational columns were NOT included in the GRANT:
--     closure_comment, created_date, deleted_at, deleted_by, scope_type
--
--   Additionally, the table-level SELECT was revoked so PostgREST metadata
--   checks fail and return PostgreSQL 42501 for any query that requests
--   any unlisted column (including the above five).
--
-- This migration:
--   1. Grants SELECT on the 5 missing operational columns to authenticated.
--   2. Explicitly confirms subtasks SELECT is NOT granted.
--   3. Does NOT grant unrestricted table-level SELECT on public.actions.
--   4. Preserves all existing RLS policies and trigger guards.
--   5. Does NOT modify any previously applied migration.
--   6. Reloads PostgREST schema cache.
--
-- Security contract preserved:
--   - Raw subtasks JSONB column is inaccessible via direct PostgREST queries.
--   - Subtask access is authorized exclusively via SECURITY DEFINER RPCs:
--       get_action_subtasks(UUID), get_actions_subtasks_batch(UUID[]/TEXT[])
--   - Direct subtask mutations by staff are blocked by trigger:
--       trg_guard_action_subtasks_update
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Grant SELECT on the 5 operational columns that were missed in
--    migration 20261017000001_action_subtasks_security.sql
-- ----------------------------------------------------------------------------

-- closure_comment: Required by ActionService._selectQuery, action closure
--                  workflow, Excel exports, Manager Action Details screen.
GRANT SELECT (closure_comment) ON public.actions TO authenticated;

-- created_date: Required by RLS policy scope checks and action filtering.
GRANT SELECT (created_date) ON public.actions TO authenticated;

-- deleted_at: Required by soft-deletion workflow and admin delete guards.
GRANT SELECT (deleted_at) ON public.actions TO authenticated;

-- deleted_by: Required by audit trail and admin delete authorization.
GRANT SELECT (deleted_by) ON public.actions TO authenticated;

-- scope_type: Required by Manager/Staff select RLS policies:
--             ("scope_type = 'specific' AND is_manager_of_scope(...)")
--             and by ActionRecord.fromSupabase scope classification.
GRANT SELECT (scope_type) ON public.actions TO authenticated;

-- ----------------------------------------------------------------------------
-- 2. Explicitly confirm subtasks column SELECT is NOT granted.
--    This is idempotent: if already revoked, this is a no-op.
--    Subtask data must only be retrieved via the authorized RPCs below:
--      - public.get_action_subtasks(UUID)
--      - public.get_action_subtasks(TEXT)
--      - public.get_actions_subtasks_batch(UUID[])
--      - public.get_actions_subtasks_batch(TEXT[])
-- ----------------------------------------------------------------------------
REVOKE SELECT (subtasks) ON public.actions FROM authenticated, anon, public;

-- ----------------------------------------------------------------------------
-- 3. Notify PostgREST to reload its schema cache.
--    PostgREST caches table metadata at startup; this ensures it picks up
--    the new column-level grants without requiring a service restart.
-- ----------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';
