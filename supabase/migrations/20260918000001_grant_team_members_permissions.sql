-- ============================================================================
-- Grant Team Members Permissions
-- Migration: 20260918000001_grant_team_members_permissions.sql
-- ============================================================================
-- Fixes PostgreSQL error 42501 ("permission denied for table team_members")
-- when authenticated users (Company Admin, Managers, and Staff) query or manage
-- team memberships in the Admin and Users portal.
--
-- Table-level privileges are required before Row Level Security (RLS) policies
-- can be evaluated by PostgreSQL. Row Level Security policies ("Allow read team members"
-- and "Admin and Manager manage team members") strictly confine access to users
-- belonging to the same organization via get_my_organization_id().
-- ============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON public.team_members TO authenticated;

