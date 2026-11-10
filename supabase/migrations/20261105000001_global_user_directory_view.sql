-- ============================================================================
-- Migration: 20261105000001_global_user_directory_view.sql
-- Description:
--   Updates public.directory_profiles security barrier view to establish a
--   consistent, shared user directory across Manager and Staff portals:
--   1. Active users (Managers, Staff, Admins) can discover all active colleagues
--      within their tenant organization for operational assignments, forwarding,
--      supporting contributors, document sharing, and request workflows.
--   2. Strict multi-tenant organization isolation is maintained:
--      (p.organization_id = public.get_my_organization_id()).
--   3. Cross-tenant access is strictly blocked; users from other organizations
--      are never visible.
--   4. Inactive users (is_active = false) and inactive callers (is_active_user() = false)
--      remain completely excluded.
--   5. Exposes sanitized operational fields: id, full_name, designation, department_id,
--      department_name, site_id, site_name, role_id, role_name, avatar_url, is_active,
--      email, phone, role_code, organization_id, is_primary_admin.
--   6. Base table public.profiles RLS remains restricted and protected.
-- ============================================================================

CREATE OR REPLACE VIEW public.directory_profiles
WITH (security_barrier = true)
AS
SELECT
  p.id,
  p.full_name,
  p.designation,
  p.department_id,
  d.name AS department_name,
  p.site_id,
  s.name AS site_name,
  p.role_id,
  r.name AS role_name,
  p.avatar_url,
  p.is_active,
  p.email,
  p.phone,
  r.code AS role_code,
  p.organization_id,
  p.is_primary_admin
FROM public.profiles p
JOIN public.roles r ON p.role_id = r.id
LEFT JOIN public.departments d ON p.department_id = d.id
LEFT JOIN public.sites s ON p.site_id = s.id
WHERE p.is_active = true
  AND public.is_active_user()
  AND (
    public.is_platform_admin()
    OR p.organization_id = public.get_my_organization_id()
  );

COMMENT ON VIEW public.directory_profiles IS
'Sanitized organization directory view with security barrier; exposes safe operational fields for active colleagues within the same tenant organization without direct table access to public.profiles.';

REVOKE ALL ON public.directory_profiles FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.directory_profiles TO authenticated, service_role;

