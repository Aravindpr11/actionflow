-- ============================================================================
-- Migration: 20261110000002_request_user_isolation_and_access_control.sql
-- Description:
--   1. Centralized Request Access Security Definer Function:
--      - app_private.can_user_access_request(UUID) strictly authorizes:
--        * Requester (created_by): Permitted
--        * Designated Approvers (in public.request_approvers): Permitted
--        * Authorized Forwardees (in public.request_forwards): Permitted
--        * Company Admin / Platform Admin: Permitted (organization-wide governance)
--        * Scoped Managers (public.is_manager_of_scope): Permitted within authorized department/site
--        * Unrelated Staff / Out-of-Scope Managers / Newly Created Users: STRICTLY DENIED (0 rows)
--      - Hardened with search_path = '' and located in app_private schema to
--        eliminate public PostgREST RPC exposure and search-path injection.
--   2. Harmonized RLS Policies across Parent & All Child Tables:
--      - public.requests: Enforces app_private.can_user_access_request(id)
--      - public.request_approvers: Enforces app_private.can_user_access_request(request_id)
--      - public.request_attachments: Enforces app_private.can_user_access_request(request_id)
--      - public.request_forwards: Enforces app_private.can_user_access_request(request_id)
--      - public.request_history: Enforces app_private.can_user_access_request(request_id)
--   3. Storage RLS Harmonization for Request Attachments:
--      - app_private.can_user_access_storage_request(TEXT) delegates directly to
--        app_private.can_user_access_request(request_id), guaranteeing 1:1 access control.
-- ============================================================================

BEGIN;

-- Ensure app_private schema exists and has restricted usage
CREATE SCHEMA IF NOT EXISTS app_private;
REVOKE ALL ON SCHEMA app_private FROM public, anon;
GRANT USAGE ON SCHEMA app_private TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 1. Centralized Request Authorization Helper: can_user_access_request(UUID)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app_private.can_user_access_request(p_request_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := (SELECT auth.uid());
  v_req RECORD;
  v_profile RECORD;
BEGIN
  IF v_uid IS NULL OR p_request_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- 1. Fetch user profile & active role status
  SELECT p.id, p.organization_id, p.department_id, p.is_active,
         (r.code IN ('admin', 'company_admin', 'super_admin') OR p.is_primary_admin = TRUE) as is_admin,
         (r.code = 'manager') as is_manager,
         (r.code IN ('platform_admin', 'super_admin') OR public.is_platform_admin()) as is_platform_admin
  INTO v_profile
  FROM public.profiles p
  LEFT JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = v_uid;

  IF NOT FOUND OR NOT v_profile.is_active THEN
    RETURN FALSE;
  END IF;

  -- 2. Fetch request metadata
  SELECT r.id, r.organization_id, r.department_id, r.site_id, r.created_by
  INTO v_req
  FROM public.requests r
  WHERE r.id = p_request_id;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  -- 3. Multi-tenant isolation boundary (Platform Admins exempt)
  -- Strictly deny access if required organization identifiers are NULL or distinct
  IF NOT v_profile.is_platform_admin THEN
    IF v_profile.organization_id IS NULL 
       OR v_req.organization_id IS NULL 
       OR v_profile.organization_id IS DISTINCT FROM v_req.organization_id THEN
      RETURN FALSE;
    END IF;
  END IF;

  -- 4. Requester / Creator
  IF v_req.created_by = v_uid THEN
    RETURN TRUE;
  END IF;

  -- 5. Platform Admin Governance (separate, explicitly authorized path)
  IF v_profile.is_platform_admin THEN
    RETURN TRUE;
  END IF;

  -- 6. Company Admin Governance (strictly constrained to active admin in the same organization)
  IF v_profile.is_admin 
     AND v_profile.organization_id IS NOT NULL 
     AND v_profile.organization_id = v_req.organization_id THEN
    RETURN TRUE;
  END IF;

  -- 7. Designated Approver (Past, Present, or Future step in chain)
  IF EXISTS (
    SELECT 1 FROM public.request_approvers ra
    WHERE ra.request_id = p_request_id AND ra.approver_id = v_uid
  ) THEN
    RETURN TRUE;
  END IF;

  -- 8. Authorized Forward Recipient
  IF EXISTS (
    SELECT 1 FROM public.request_forwards rf
    WHERE rf.request_id = p_request_id AND rf.to_user_id = v_uid
  ) THEN
    RETURN TRUE;
  END IF;

  -- 9. Manager with Scope Over Target Department & Site (within caller organization)
  IF v_profile.is_manager 
     AND v_profile.organization_id IS NOT NULL
     AND v_profile.organization_id = v_req.organization_id
     AND public.is_manager_of_scope(v_req.department_id, v_req.site_id) THEN
    RETURN TRUE;
  END IF;

  -- All other users (unrelated staff, out-of-scope managers, new users) are strictly denied
  RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION app_private.can_user_access_request(UUID)
IS 'Enforces strict user isolation on requests in private schema: requester, designated approvers, forwardees, scoped managers, and admins.';

REVOKE ALL ON FUNCTION app_private.can_user_access_request(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION app_private.can_user_access_request(UUID) TO authenticated, service_role;

-- Clean up any obsolete public helper to close RPC attack surface
DROP FUNCTION IF EXISTS public.can_user_access_request(UUID);


-- ----------------------------------------------------------------------------
-- 2. Harmonize Storage Helper: app_private.can_user_access_storage_request(TEXT)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app_private.can_user_access_storage_request(p_file_path TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := (SELECT auth.uid());
  v_org_id TEXT := split_part(p_file_path, '/', 1);
  v_req RECORD;
BEGIN
  IF v_uid IS NULL OR v_org_id IS NULL OR length(trim(v_org_id)) = 0 THEN
    RETURN FALSE;
  END IF;

  -- Tenant boundary check: user must belong to target organization
  IF NOT public.check_user_in_org(v_org_id) THEN
    RETURN FALSE;
  END IF;

  -- Lookup attachment metadata linked to request
  SELECT ra.request_id
  INTO v_req
  FROM public.request_attachments ra
  WHERE ra.file_path = p_file_path
    AND ra.organization_id::text = v_org_id;

  -- If not yet linked to requests table (upload in flight), allow object owner
  IF NOT FOUND THEN
    RETURN EXISTS (
      SELECT 1 FROM storage.objects
      WHERE name = p_file_path
        AND bucket_id = 'documents'
        AND (owner = v_uid OR owner_id = v_uid::text)
    );
  END IF;

  -- Delegate strictly to request access helper
  RETURN app_private.can_user_access_request(v_req.request_id);
END;
$$;

COMMENT ON FUNCTION app_private.can_user_access_storage_request(TEXT)
IS 'Internal storage authorization for request attachments, delegating 1:1 to app_private.can_user_access_request.';

REVOKE ALL ON FUNCTION app_private.can_user_access_storage_request(TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION app_private.can_user_access_storage_request(TEXT) TO authenticated, service_role;

-- Drop legacy storage policy depending on public helper first
DROP POLICY IF EXISTS "request_attachments_storage_select" ON storage.objects;

-- Clean up obsolete public helper
DROP FUNCTION IF EXISTS public.can_user_access_storage_request(TEXT);


-- ----------------------------------------------------------------------------
-- 3. Update Table RLS Policies on public.requests
-- ----------------------------------------------------------------------------
ALTER TABLE public.requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Requests multi-tenant select policy" ON public.requests;
CREATE POLICY "Requests multi-tenant select policy"
  ON public.requests FOR SELECT TO authenticated
  USING (
    app_private.can_user_access_request(id)
  );

DROP POLICY IF EXISTS "Requests insert policy" ON public.requests;
CREATE POLICY "Requests insert policy"
  ON public.requests FOR INSERT TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND organization_id = (SELECT organization_id FROM public.profiles WHERE id = auth.uid() AND is_active = true)
  );


-- ----------------------------------------------------------------------------
-- 4. Update Table RLS Policies on public.request_approvers
-- ----------------------------------------------------------------------------
ALTER TABLE public.request_approvers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Request approvers select policy" ON public.request_approvers;
CREATE POLICY "Request approvers select policy"
  ON public.request_approvers FOR SELECT TO authenticated
  USING (
    app_private.can_user_access_request(request_id)
  );


-- ----------------------------------------------------------------------------
-- 5. Update Table RLS Policies on public.request_attachments
-- ----------------------------------------------------------------------------
ALTER TABLE public.request_attachments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Request attachments select policy" ON public.request_attachments;
CREATE POLICY "Request attachments select policy"
  ON public.request_attachments FOR SELECT TO authenticated
  USING (
    app_private.can_user_access_request(request_id)
  );

DROP POLICY IF EXISTS "Request attachments insert policy" ON public.request_attachments;
CREATE POLICY "Request attachments insert policy"
  ON public.request_attachments FOR INSERT TO authenticated
  WITH CHECK (
    app_private.can_user_access_request(request_id)
    AND uploaded_by = auth.uid()
  );


-- ----------------------------------------------------------------------------
-- 6. Update Table RLS Policies on public.request_forwards
-- ----------------------------------------------------------------------------
ALTER TABLE public.request_forwards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Request forwards select policy" ON public.request_forwards;
CREATE POLICY "Request forwards select policy"
  ON public.request_forwards FOR SELECT TO authenticated
  USING (
    app_private.can_user_access_request(request_id)
  );


-- ----------------------------------------------------------------------------
-- 7. Update Table RLS Policies on public.request_history
-- ----------------------------------------------------------------------------
ALTER TABLE public.request_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Request history select policy" ON public.request_history;
CREATE POLICY "Request history select policy"
  ON public.request_history FOR SELECT TO authenticated
  USING (
    app_private.can_user_access_request(request_id)
  );


-- ----------------------------------------------------------------------------
-- 8. Harmonize Storage RLS Policy on 'documents' Bucket for Requests
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "request_attachments_storage_select" ON storage.objects;
CREATE POLICY "request_attachments_storage_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND split_part(name, '/', 2) = 'requests'
    AND app_private.can_user_access_storage_request(name)
  );

COMMIT;
