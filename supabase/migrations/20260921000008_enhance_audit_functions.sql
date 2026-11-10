-- ============================================================================
-- Migration: 20260921000008_enhance_audit_functions.sql
-- Description:
--   Add get_system_account_requests_audit and update get_system_users_audit
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_system_users_audit()
RETURNS TABLE (
  user_id UUID,
  email TEXT,
  full_name TEXT,
  role_code TEXT,
  organization_id UUID,
  org_name TEXT,
  is_active BOOLEAN,
  is_primary_admin BOOLEAN,
  scopes_count BIGINT,
  teams_count BIGINT,
  actions_assigned_count BIGINT,
  actions_created_count BIGINT,
  is_protected BOOLEAN
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT
    COALESCE(p.id, u.id) AS user_id,
    COALESCE(p.email, u.email)::TEXT AS email,
    COALESCE(p.full_name, 'No Profile')::TEXT AS full_name,
    COALESCE(r.code, 'unknown')::TEXT AS role_code,
    p.organization_id,
    COALESCE(o.name, 'No Org')::TEXT AS org_name,
    COALESCE(p.is_active, true) AS is_active,
    COALESCE(p.is_primary_admin, false) AS is_primary_admin,
    COALESCE(ms.cnt, 0) AS scopes_count,
    COALESCE(tm.cnt, 0) AS teams_count,
    COALESCE(act_ass.cnt, 0) AS actions_assigned_count,
    COALESCE(act_cre.cnt, 0) AS actions_created_count,
    (COALESCE(p.email, u.email) IN (
      'arvin.pr1112@gmail.com',
      'aravind11.sobha@gmail.com',
      'webonant@gmail.com',
      'aravindpr.1111@gmail.com'
    )) AS is_protected
  FROM auth.users u
  FULL OUTER JOIN public.profiles p ON u.id = p.id
  LEFT JOIN public.roles r ON p.role_id = r.id
  LEFT JOIN public.organizations o ON p.organization_id = o.id
  LEFT JOIN (
    SELECT manager_profile_id, count(*) AS cnt
    FROM public.manager_scopes
    GROUP BY manager_profile_id
  ) ms ON ms.manager_profile_id = COALESCE(p.id, u.id)
  LEFT JOIN (
    SELECT profile_id, count(*) AS cnt
    FROM public.team_members
    GROUP BY profile_id
  ) tm ON tm.profile_id = COALESCE(p.id, u.id)
  LEFT JOIN (
    SELECT assigned_to, count(*) AS cnt
    FROM public.actions
    GROUP BY assigned_to
  ) act_ass ON act_ass.assigned_to = COALESCE(p.id, u.id)
  LEFT JOIN (
    SELECT created_by, count(*) AS cnt
    FROM public.actions
    GROUP BY created_by
  ) act_cre ON act_cre.created_by = COALESCE(p.id, u.id)
  ORDER BY COALESCE(p.created_at, u.created_at) ASC;
$$;

GRANT EXECUTE ON FUNCTION public.get_system_users_audit() TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_system_account_requests_audit()
RETURNS TABLE (
  request_id UUID,
  auth_user_id UUID,
  email TEXT,
  full_name TEXT,
  role_id UUID,
  status TEXT,
  is_email_verified BOOLEAN,
  organization_id UUID,
  created_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT
    id AS request_id,
    auth_user_id,
    email::TEXT,
    full_name::TEXT,
    requested_role_id AS role_id,
    status::TEXT,
    is_email_verified,
    organization_id,
    created_at
  FROM public.account_requests
  ORDER BY created_at ASC;
$$;

GRANT EXECUTE ON FUNCTION public.get_system_account_requests_audit() TO anon, authenticated;

