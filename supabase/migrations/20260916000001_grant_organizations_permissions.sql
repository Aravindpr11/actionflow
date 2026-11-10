-- ============================================================================
-- Grant Organizations Permissions
-- Migration: 20260916000001_grant_organizations_permissions.sql
-- ============================================================================
-- Fixes PostgreSQL error 42501 ("permission denied for table organizations")
-- when Platform Admins attempt to insert, update, or delete organizations.
-- Table-level privileges are required for RLS policy "Platform admin manage organizations"
-- to be evaluated. Row-level security strictly restricts write access to is_platform_admin().
-- ============================================================================

GRANT INSERT, UPDATE, DELETE ON public.organizations TO authenticated;

