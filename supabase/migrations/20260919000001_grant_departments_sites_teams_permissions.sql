-- ============================================================================
-- Grant Company Structure & Account Management Permissions
-- Migration: 20260919000001_grant_departments_sites_teams_permissions.sql
-- ============================================================================
-- Fixes PostgreSQL error 42501 ("permission denied for table departments / sites / teams / ...")
-- when authenticated Company Admins attempt to insert, update, or delete records.
--
-- Table-level DAC privileges are required by PostgreSQL before Row Level Security (RLS)
-- policies can be evaluated.
--
-- Row Level Security (RLS) policies strictly restrict write/read access so that
-- Company Admins can ONLY insert, update, delete, or select rows where:
--   organization_id = public.get_my_organization_id()
-- or Platform Admins (public.is_platform_admin()).
-- ============================================================================

-- 1. Table-level permissions for authenticated application users
GRANT SELECT, INSERT, UPDATE, DELETE ON public.departments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sites TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.teams TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.team_members TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.account_requests TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.account_request_scopes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.manager_scopes TO authenticated;

-- 2. Table-level permissions for server-side service_role
GRANT SELECT, INSERT, UPDATE, DELETE ON public.departments TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sites TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.teams TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.team_members TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.account_requests TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.account_request_scopes TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.manager_scopes TO service_role;

-- 3. Sequence usage permissions
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated, service_role;

