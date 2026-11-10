-- ============================================================================
-- Migration: 20261024000001_fix_directory_profiles_staff_manager_visibility.sql
-- Description:
--   Updates public.directory_profiles security barrier view so that:
--   1. Staff users can discover active colleagues in their assigned department.
--   2. Staff users can discover active managers and administrators in the same organization
--      (enabling document sharing with authorized managers/admins across departments).
--   3. Strict multi-tenant organization isolation is preserved (p.organization_id = public.get_my_organization_id()).
--   4. Inactive users and inactive callers remain completely excluded (p.is_active = true AND public.is_active_user()).
--   5. Sensitive profile data and PII remain protected; no direct table access to public.profiles is granted.
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
  p.is_active
FROM public.profiles p
JOIN public.roles r ON p.role_id = r.id
LEFT JOIN public.departments d ON p.department_id = d.id
LEFT JOIN public.sites s ON p.site_id = s.id
WHERE p.is_active = true
  AND public.is_active_user()
  AND (
    -- Platform Admin has complete visibility across all organizations
    public.is_platform_admin()
    -- Scoped to caller's own organization
    OR (
      p.organization_id = public.get_my_organization_id()
      AND (
        -- Company Admin has visibility across their own organization
        public.is_admin()
        -- Managers have visibility strictly restricted to active profiles in their managed scopes
        OR (public.is_manager() AND public.is_manager_of_scope(p.department_id, p.site_id))
        -- Staff visibility:
        -- 1. Colleagues in the staff member's own assigned department
        -- 2. Active managers and administrators within the same organization (for escalation & document sharing)
        OR (
          NOT public.is_manager()
          AND (
            (p.department_id IS NOT NULL AND p.department_id = public.get_my_department_id())
            OR r.code IN ('manager', 'admin')
            OR p.is_primary_admin = true
          )
        )
        -- Users can always see their own directory entry
        OR p.id = auth.uid()
      )
    )
  );

COMMENT ON VIEW public.directory_profiles IS
'Sanitized directory view with security barrier; exposes safe operational fields scoped by role, department, and organization without PII.';

GRANT SELECT ON public.directory_profiles TO authenticated, service_role;

