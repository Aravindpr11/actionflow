-- ============================================================================
-- Grant Organizations Permissions to service_role
-- Migration: 20260916000002_grant_service_role_organizations.sql
-- ============================================================================
-- Grants table privileges on public.organizations to service_role so server-side
-- Edge Functions (e.g. invite-company-admin) and administrative workers can
-- query and manage tenant organizations without 42501 permission denied errors.
-- ============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.organizations
TO service_role;

