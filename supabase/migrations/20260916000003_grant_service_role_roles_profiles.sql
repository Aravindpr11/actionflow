-- ============================================================================
-- Grant Roles & Profiles Permissions to service_role
-- Migration: 20260916000003_grant_service_role_roles_profiles.sql
-- ============================================================================
-- Grants table privileges on public.roles and public.profiles to service_role
-- so server-side administrative workflows and Edge Functions (e.g. invite-company-admin)
-- can query application roles and manage user profile records.
-- ============================================================================

GRANT SELECT ON public.roles TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.profiles
TO service_role;

