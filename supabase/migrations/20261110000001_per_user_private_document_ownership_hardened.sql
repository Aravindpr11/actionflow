-- ============================================================================
-- Migration: 20261110000001_per_user_private_document_ownership_hardened.sql
-- Description: Enforce Per-User Private Document Ownership across Table RLS,
--              Sharing RLS, and Storage Objects RLS.
--              - Eliminates mutual RLS recursion via app_private SECURITY DEFINER helpers
--              - Prevents client probing attacks by deriving identity from auth.uid()
--              - Implements auditable legacy ownership resolution with NO admin blanket assignment
--              - Harmonizes Table RLS and Storage RLS 1:1, removing manager global bypass
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Private Internal Schema & Non-Probing Helper Functions
-- ----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS app_private;
REVOKE ALL ON SCHEMA app_private FROM public, anon;
GRANT USAGE ON SCHEMA app_private TO authenticated, service_role;

-- Helper to check if caller is an explicit share recipient
-- Runs as SECURITY DEFINER to bypass RLS recursion on document_shares.
-- Derives identity exclusively from auth.uid() to eliminate probing attacks.
CREATE OR REPLACE FUNCTION app_private.is_document_shared_with_caller(p_document_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM public.document_shares ds
    JOIN public.profiles p ON p.id = (SELECT auth.uid())
    WHERE ds.document_id = p_document_id
      AND ds.user_id = (SELECT auth.uid())
      AND ds.organization_id = p.organization_id::text
      AND p.is_active = true
  );
$$;

COMMENT ON FUNCTION app_private.is_document_shared_with_caller(TEXT)
IS 'Verifies caller share membership internally without exposing user IDs or triggering RLS recursion.';

REVOKE ALL ON FUNCTION app_private.is_document_shared_with_caller(TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION app_private.is_document_shared_with_caller(TEXT) TO authenticated;

-- Helper to check if caller is the document owner
-- Runs as SECURITY DEFINER to bypass RLS recursion on documents.
-- Derives identity exclusively from auth.uid() to eliminate probing attacks.
CREATE OR REPLACE FUNCTION app_private.is_caller_document_owner(p_document_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM public.documents d
    JOIN public.profiles p ON p.id = (SELECT auth.uid())
    WHERE d.id = p_document_id
      AND d.created_by = (SELECT auth.uid())
      AND d.organization_id = p.organization_id::text
      AND p.is_active = true
  );
$$;

COMMENT ON FUNCTION app_private.is_caller_document_owner(TEXT)
IS 'Verifies caller document ownership internally without exposing user IDs or triggering RLS recursion.';

REVOKE ALL ON FUNCTION app_private.is_caller_document_owner(TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION app_private.is_caller_document_owner(TEXT) TO authenticated;

-- Helper to check if caller has edit permission on a document via document_shares
-- Runs as SECURITY DEFINER to bypass RLS recursion on document_shares.
-- Derives identity exclusively from auth.uid() to eliminate probing attacks.
CREATE OR REPLACE FUNCTION app_private.can_caller_edit_document(p_document_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM public.document_shares ds
    JOIN public.profiles p ON p.id = (SELECT auth.uid())
    WHERE ds.document_id = p_document_id
      AND ds.user_id = (SELECT auth.uid())
      AND ds.permission = 'edit'
      AND ds.organization_id = p.organization_id::text
      AND p.is_active = true
  );
$$;

COMMENT ON FUNCTION app_private.can_caller_edit_document(TEXT)
IS 'Verifies caller edit permission internally without exposing user IDs or triggering RLS recursion.';

REVOKE ALL ON FUNCTION app_private.can_caller_edit_document(TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION app_private.can_caller_edit_document(TEXT) TO authenticated;

-- Transitional forward-declaration for request storage routing
-- Fully implemented and hardened with request user isolation in migration 20261110000002
CREATE OR REPLACE FUNCTION app_private.can_user_access_storage_request(p_file_path TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'can_user_access_storage_request'
  ) THEN
    RETURN public.can_user_access_storage_request(p_file_path);
  END IF;
  RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION app_private.can_user_access_storage_request(TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION app_private.can_user_access_storage_request(TEXT) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 1b. Document Ownership & Tenant Immutability Protection Trigger
-- ----------------------------------------------------------------------------
-- Prevents users with edit permission from altering created_by, organization_id,
-- document primary key id, file storage identity (file_path, storage_bucket),
-- or ownership_status. Normal metadata editing (title, description, category,
-- department_id, is_archived) remains fully permitted.
--
-- Security:
--   - Uses session_user (connection identity) combined with an explicit
--     session configuration ('app.maintenance_mode' = 'active') to authorize
--     trusted database migration/maintenance procedures.
--   - Does NOT use current_user, because inside a SECURITY DEFINER function,
--     current_user ALWAYS changes to the function owner (postgres/supabase_admin),
--     which would inadvertently grant every client a full bypass.
--   - API callers (via PostgREST) connect under session_user 'authenticator'
--     and can NEVER satisfy the superuser session check.
CREATE OR REPLACE FUNCTION app_private.enforce_document_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := (SELECT auth.uid());
  v_session_user TEXT := session_user;
  v_is_maintenance BOOLEAN := FALSE;
  v_is_admin BOOLEAN := FALSE;
  v_is_platform_admin BOOLEAN := FALSE;
  v_is_owner BOOLEAN := FALSE;
  v_caller_org TEXT;
  v_current_role TEXT := COALESCE(current_setting('role', true), '');
  v_jwt_role TEXT := COALESCE(current_setting('request.jwt.claim.role', true), '');
BEGIN
  -- 1. Explicitly verify trusted database migration/maintenance operations:
  --   a) Connection MUST be directly established by database superuser / admin (postgres, supabase_admin, or cli_login_*)
  --   b) Caller MUST NOT have an authenticated user identity (auth.uid() is NULL)
  --   c) AND maintenance mode must be explicitly activated in the local session ('app.maintenance_mode' = 'active')
  -- Note: PostgREST API connections ALWAYS run under session_user = 'authenticator',
  -- and authenticated users have a non-null auth.uid(), so unprivileged web callers cannot satisfy this condition.
  IF v_uid IS NULL
     AND (v_session_user IN ('postgres', 'supabase_admin', 'cli_login_postgres') OR v_session_user LIKE 'cli_login_%') 
     AND COALESCE(current_setting('app.maintenance_mode', true), '') = 'active' THEN
    NEW.updated_at := clock_timestamp();
    RETURN NEW;
  END IF;

  -- 2. Fail closed for anonymous or unauthenticated client requests
  -- Anonymous requests (where auth.uid() is NULL or role is 'anon') must NEVER update documents
  IF v_uid IS NULL OR v_current_role = 'anon' OR v_jwt_role = 'anon' THEN
    RAISE EXCEPTION 'Authentication required. Anonymous or unauthenticated document updates are strictly prohibited.';
  END IF;

  -- 3. Document Primary Key (id) is strictly immutable for all users and service-role requests
  IF NEW.id IS DISTINCT FROM OLD.id THEN
    RAISE EXCEPTION 'Document primary key id is immutable.';
  END IF;

  -- 4. Fetch caller profile, organization, and role status
  SELECT 
    p.organization_id::text,
    (r.code IN ('admin', 'company_admin', 'super_admin') OR p.is_primary_admin = true),
    (r.code IN ('platform_admin', 'super_admin') OR public.is_platform_admin())
  INTO v_caller_org, v_is_admin, v_is_platform_admin
  FROM public.profiles p
  LEFT JOIN public.roles r ON p.role_id = r.id
  WHERE p.id = v_uid AND p.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active user profile required to perform document updates.';
  END IF;

  -- 5. Organization ID (Tenant Boundary) Immutability
  -- Normal users (staff, managers, company admins) cannot change organization_id under ANY circumstances:
  --   - NULL to valid: strictly denied for normal users
  --   - Valid to NULL: strictly denied for all users
  --   - One organization to another: strictly denied for normal users
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    -- Only active platform admins via controlled governance may reassign organization
    IF NOT v_is_platform_admin THEN
      RAISE EXCEPTION 'Organization ID is immutable. Modifying organization assignment is strictly prohibited.';
    END IF;

    -- Target organization cannot be null or empty
    IF NEW.organization_id IS NULL OR length(trim(NEW.organization_id)) = 0 THEN
      RAISE EXCEPTION 'Document organization ID cannot be null or empty.';
    END IF;

    -- Target organization must exist and be active
    IF NOT EXISTS (
      SELECT 1 FROM public.organizations o 
      WHERE o.id::text = NEW.organization_id AND o.is_active = true
    ) THEN
      RAISE EXCEPTION 'Target organization does not exist or is inactive.';
    END IF;
  END IF;

  -- 6. Caller Organization Anchor Binding
  -- Non-platform admins must belong to the document's organization
  IF NOT v_is_platform_admin THEN
    IF OLD.organization_id IS NULL OR length(trim(OLD.organization_id)) = 0 THEN
      RAISE EXCEPTION 'Document has an invalid or missing organization ID.';
    END IF;

    IF v_caller_org IS NULL 
       OR length(trim(v_caller_org)) = 0 
       OR v_caller_org IS DISTINCT FROM OLD.organization_id THEN
      RAISE EXCEPTION 'Operation denied: caller does not belong to the document organization.';
    END IF;
  END IF;

  v_is_owner := (OLD.created_by IS NOT NULL AND OLD.created_by = v_uid);

  -- 7. File Path & Storage Identity Protection
  -- Editors with share permission CANNOT alter file_path, file_name, file_size, file_type, or storage_bucket
  IF (NEW.file_path IS DISTINCT FROM OLD.file_path OR
      NEW.file_name IS DISTINCT FROM OLD.file_name OR
      NEW.file_size IS DISTINCT FROM OLD.file_size OR
      NEW.file_type IS DISTINCT FROM OLD.file_type OR
      NEW.storage_bucket IS DISTINCT FROM OLD.storage_bucket) THEN
    -- Only the document owner, an authorized tenant admin, or platform admin may update storage attributes
    IF NOT (v_is_platform_admin OR (v_is_admin AND v_caller_org IS NOT NULL AND v_caller_org = OLD.organization_id) OR v_is_owner) THEN
      RAISE EXCEPTION 'Only the document owner or an authorized organization administrator may update underlying file storage attributes.';
    END IF;

    -- Ensure storage file_path strictly belongs to the document organization (NULL-safe)
    IF NOT v_is_platform_admin AND (split_part(NEW.file_path, '/', 1) IS DISTINCT FROM OLD.organization_id) THEN
      RAISE EXCEPTION 'Storage file path must belong to the document organization.';
    END IF;
  END IF;

  -- 8. Ownership Protection (created_by and created_by_name)
  IF (NEW.created_by IS DISTINCT FROM OLD.created_by OR
      NEW.created_by_name IS DISTINCT FROM OLD.created_by_name) THEN
    -- Only authorized platform admin or active tenant admin belonging to the document organization may resolve/reassign ownership
    IF NOT (v_is_platform_admin OR (v_is_admin AND v_caller_org IS NOT NULL AND v_caller_org = OLD.organization_id)) THEN
      RAISE EXCEPTION 'Only authorized administrators belonging to the document organization may resolve or reassign document ownership.';
    END IF;

    -- Target owner must be an active profile in the same organization
    IF NEW.created_by IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.profiles tp
        WHERE tp.id = NEW.created_by
          AND tp.organization_id::text = OLD.organization_id
          AND tp.is_active = true
      ) THEN
        RAISE EXCEPTION 'Document target owner must be an active profile within the same organization.';
      END IF;
    END IF;
  END IF;

  -- 9. Ownership Status Audit Protection (Harden ownership-status updates)
  IF NEW.ownership_status IS DISTINCT FROM OLD.ownership_status THEN
    -- Require active platform admin OR active company admin belonging to the document organization
    IF NOT (v_is_platform_admin OR (v_is_admin AND v_caller_org IS NOT NULL AND v_caller_org = OLD.organization_id)) THEN
      RAISE EXCEPTION 'Only authorized administrators belonging to the document organization may update document ownership status.';
    END IF;
  END IF;

  -- Always update updated_at timestamp
  NEW.updated_at := clock_timestamp();

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION app_private.enforce_document_immutability()
IS 'Enforces immutability on document primary key, tenant ID, owner, storage path, and status against unauthorized editor tampering.';

REVOKE ALL ON FUNCTION app_private.enforce_document_immutability() FROM public, anon;
GRANT EXECUTE ON FUNCTION app_private.enforce_document_immutability() TO authenticated, service_role;

DROP TRIGGER IF EXISTS trg_enforce_document_immutability ON public.documents;
CREATE TRIGGER trg_enforce_document_immutability
  BEFORE UPDATE ON public.documents
  FOR EACH ROW
  EXECUTE FUNCTION app_private.enforce_document_immutability();


-- ----------------------------------------------------------------------------
-- 2. Auditable Legacy Ownership Resolution (No Blanket Admin Assignment)
-- ----------------------------------------------------------------------------
-- Activate maintenance mode for migration backfill
-- Only effective because this migration executes directly as superuser/maintenance user
SET LOCAL app.maintenance_mode = 'active';

-- Add ownership audit tracking column with safe default of 'legacy_unresolved'
ALTER TABLE public.documents
  ADD COLUMN IF NOT EXISTS ownership_status VARCHAR(50) NOT NULL DEFAULT 'legacy_unresolved'
  CHECK (ownership_status IN ('verified', 'legacy_unresolved', 'reassigned', 'quarantined'));

-- Existing documents with valid created_by are verified
UPDATE public.documents
SET ownership_status = 'verified'
WHERE created_by IS NOT NULL;

-- Tier 1: Backfill from linked action creator if action exists
UPDATE public.documents d
SET created_by = a.created_by,
    created_by_name = COALESCE(p.full_name, d.created_by_name),
    ownership_status = 'verified'
FROM public.actions a
LEFT JOIN public.profiles p ON p.id = a.created_by
WHERE d.created_by IS NULL
  AND d.action_id IS NOT NULL
  AND (a.id::text = d.action_id OR a.action_number = d.action_id)
  AND a.created_by IS NOT NULL
  AND a.organization_id::text = d.organization_id;

-- Tier 2: Backfill from storage.objects owner if storage file exists and owner has an active profile
UPDATE public.documents d
SET created_by = obj.owner,
    created_by_name = p.full_name,
    ownership_status = 'verified'
FROM storage.objects obj
JOIN public.profiles p ON p.id = obj.owner
WHERE d.created_by IS NULL
  AND obj.bucket_id = 'documents'
  AND obj.name = d.file_path
  AND obj.owner IS NOT NULL
  AND p.organization_id::text = d.organization_id
  AND p.is_active = true;

-- Tier 3: Unique profile full_name match ONLY where EXACTLY ONE active profile in org matches
WITH single_matches AS (
  SELECT p.id as profile_id, p.full_name, lower(trim(p.full_name)) as norm_name, p.organization_id::text as org_id
  FROM public.profiles p
  WHERE p.is_active = true
  GROUP BY p.id, p.full_name, lower(trim(p.full_name)), p.organization_id
  HAVING (
    SELECT count(*) 
    FROM public.profiles p2 
    WHERE lower(trim(p2.full_name)) = lower(trim(p.full_name)) 
      AND p2.organization_id = p.organization_id 
      AND p2.is_active = true
  ) = 1
)
UPDATE public.documents d
SET created_by = sm.profile_id,
    created_by_name = sm.full_name,
    ownership_status = 'verified'
FROM single_matches sm
WHERE d.created_by IS NULL
  AND d.created_by_name IS NOT NULL
  AND length(trim(d.created_by_name)) > 0
  AND lower(trim(d.created_by_name)) = sm.norm_name
  AND d.organization_id = sm.org_id;

-- Tier 4: Any documents STILL unresolved remain marked 'legacy_unresolved' (NOT assigned to Admin!)
UPDATE public.documents
SET ownership_status = 'legacy_unresolved'
WHERE created_by IS NULL;

-- Reset maintenance mode immediately following backfill completion
RESET app.maintenance_mode;

-- Administrative audit view for review of unresolved documents
-- Hardened with security_invoker = true and embedded active admin check to prevent staff enumeration
CREATE OR REPLACE VIEW public.admin_unresolved_documents
WITH (security_invoker = true)
AS
SELECT 
  d.id,
  d.title,
  d.category,
  d.created_by_name,
  d.organization_id,
  d.department_id,
  d.file_name,
  d.file_path,
  d.created_at,
  d.ownership_status
FROM public.documents d
WHERE (d.ownership_status = 'legacy_unresolved' OR d.created_by IS NULL)
  AND EXISTS (
    SELECT 1 FROM public.profiles p
    JOIN public.roles r ON p.role_id = r.id
    WHERE p.id = auth.uid()
      AND (r.code IN ('admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = true)
      AND p.organization_id::text = d.organization_id
      AND p.is_active = true
  );

REVOKE ALL ON public.admin_unresolved_documents FROM public, anon;
GRANT SELECT ON public.admin_unresolved_documents TO authenticated;


-- ----------------------------------------------------------------------------
-- 3. Replace public.documents Table RLS Policies
-- ----------------------------------------------------------------------------
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "documents_org_select" ON public.documents;
CREATE POLICY "documents_org_select" ON public.documents
  FOR SELECT USING (
    public.check_user_in_org(organization_id)
    AND (
      -- 1. Owner / Author
      created_by = auth.uid()

      -- 2. Explicit share recipient (via non-recursive app_private helper)
      OR app_private.is_document_shared_with_caller(id)

      -- 3. Genuine Company-Wide Guidelines & Policies (Strictly excludes 'General')
      OR (
        category IN ('HSSE Manuals', 'Policies', 'Policies & Procedures', 'Manuals & Guides')
        AND (
          department_id IS NULL
          OR department_id = public.get_user_department_id(auth.uid())
        )
      )

      -- 4. Linked Action Participant
      OR (
        action_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.actions a
          WHERE (a.id::text = documents.action_id OR a.action_number = documents.action_id)
            AND a.organization_id::text = documents.organization_id
            AND (
              a.assigned_to = auth.uid()
              OR a.created_by = auth.uid()
              OR EXISTS (SELECT 1 FROM public.action_contributors ac WHERE ac.action_id = a.id AND ac.profile_id = auth.uid())
              OR EXISTS (SELECT 1 FROM public.action_assignees aa WHERE aa.action_id = a.id AND aa.profile_id = auth.uid())
              OR (
                a.subtasks IS NOT NULL 
                AND jsonb_typeof(a.subtasks) = 'array'
                AND EXISTS (
                  SELECT 1 FROM jsonb_array_elements(a.subtasks) elem
                  WHERE elem->>'assigned_staff_id' = auth.uid()::text
                     OR (
                       elem->>'assigned_staff_email' IS NOT NULL 
                       AND lower(trim(elem->>'assigned_staff_email')) = lower(trim(auth.jwt()->>'email'))
                     )
                )
              )
              OR (
                public.check_user_is_manager_or_admin(documents.organization_id)
                AND public.is_manager_of_scope(a.department_id, a.site_id)
              )
            )
        )
      )

      -- 5. Company Admin & Platform Admin Governance Oversight
      OR EXISTS (
        SELECT 1 FROM public.profiles p
        JOIN public.roles r ON p.role_id = r.id
        WHERE p.id = auth.uid()
          AND (r.code IN ('admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = true)
          AND p.is_active = true
      )
    )
  );

DROP POLICY IF EXISTS "documents_org_insert" ON public.documents;
CREATE POLICY "documents_org_insert" ON public.documents
  FOR INSERT WITH CHECK (
    public.check_user_in_org(organization_id)
    AND created_by = auth.uid()
  );

DROP POLICY IF EXISTS "documents_org_update" ON public.documents;
CREATE POLICY "documents_org_update" ON public.documents
  FOR UPDATE USING (
    public.check_user_in_org(organization_id)
    AND (
      created_by = auth.uid()
      OR app_private.can_caller_edit_document(id)
      OR EXISTS (
        SELECT 1 FROM public.profiles p
        JOIN public.roles r ON p.role_id = r.id
        WHERE p.id = auth.uid()
          AND (r.code IN ('admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = true)
          AND p.is_active = true
      )
    )
  )
  WITH CHECK (
    public.check_user_in_org(organization_id)
    AND (
      created_by = auth.uid()
      OR app_private.can_caller_edit_document(id)
      OR EXISTS (
        SELECT 1 FROM public.profiles p
        JOIN public.roles r ON p.role_id = r.id
        WHERE p.id = auth.uid()
          AND (r.code IN ('admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = true)
          AND p.is_active = true
      )
    )
  );

DROP POLICY IF EXISTS "documents_org_delete" ON public.documents;
CREATE POLICY "documents_org_delete" ON public.documents
  FOR DELETE USING (
    public.check_user_in_org(organization_id)
    AND (
      created_by = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.profiles p
        JOIN public.roles r ON p.role_id = r.id
        WHERE p.id = auth.uid()
          AND (r.code IN ('admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = true)
          AND p.is_active = true
      )
    )
  );


-- ----------------------------------------------------------------------------
-- 4. Replace public.document_shares Table RLS Policies
-- ----------------------------------------------------------------------------
ALTER TABLE public.document_shares ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "document_shares_select" ON public.document_shares;
CREATE POLICY "document_shares_select" ON public.document_shares
  FOR SELECT USING (
    public.check_user_in_org(organization_id)
    AND (
      -- 1. Recipient can see their own share record
      user_id = auth.uid()
      -- 2. Uploader/Sharer can see shares they initiated
      OR shared_by = auth.uid()
      -- 3. Document Owner can see all shares of their document (via non-recursive helper)
      OR app_private.is_caller_document_owner(document_id)
      -- 4. Company Admin / Platform Admin governance oversight
      OR EXISTS (
        SELECT 1 FROM public.profiles p
        JOIN public.roles r ON p.role_id = r.id
        WHERE p.id = auth.uid()
          AND (r.code IN ('admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = true)
          AND p.is_active = true
      )
    )
  );

DROP POLICY IF EXISTS "document_shares_insert" ON public.document_shares;
CREATE POLICY "document_shares_insert" ON public.document_shares
  FOR INSERT WITH CHECK (
    public.check_user_in_org(organization_id)
    AND shared_by = auth.uid()
    AND (
      -- Only Document Owner or Admin can share
      app_private.is_caller_document_owner(document_id)
      OR EXISTS (
        SELECT 1 FROM public.profiles p
        JOIN public.roles r ON p.role_id = r.id
        WHERE p.id = auth.uid()
          AND (r.code IN ('admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = true)
          AND p.is_active = true
      )
    )
  );

DROP POLICY IF EXISTS "document_shares_update" ON public.document_shares;
CREATE POLICY "document_shares_update" ON public.document_shares
  FOR UPDATE USING (
    public.check_user_in_org(organization_id)
    AND (
      -- Only Document Owner or Admin can modify share permissions
      app_private.is_caller_document_owner(document_id)
      OR EXISTS (
        SELECT 1 FROM public.profiles p
        JOIN public.roles r ON p.role_id = r.id
        WHERE p.id = auth.uid()
          AND (r.code IN ('admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = true)
          AND p.is_active = true
      )
    )
  );

DROP POLICY IF EXISTS "document_shares_delete" ON public.document_shares;
CREATE POLICY "document_shares_delete" ON public.document_shares
  FOR DELETE USING (
    public.check_user_in_org(organization_id)
    AND (
      -- Document Owner, Sharer, or Admin can revoke
      app_private.is_caller_document_owner(document_id)
      OR shared_by = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.profiles p
        JOIN public.roles r ON p.role_id = r.id
        WHERE p.id = auth.uid()
          AND (r.code IN ('admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = true)
          AND p.is_active = true
      )
    )
  );


-- ----------------------------------------------------------------------------
-- 5. Harden Storage Authorization: app_private.can_user_access_storage_document(TEXT)
-- ----------------------------------------------------------------------------
-- Note on "View" vs "Download" Technical Reality in Object Storage:
-- In HTTP/REST object storage (such as Supabase Storage), streaming object bytes 
-- is required both for client-side rendering (preview) and disk persistence (download).
-- Storage RLS therefore authorizes byte read access to callers who own the document, 
-- have an explicit share ('view' or 'edit'), or have administrative oversight.
-- Application UI enforces "View-only" vs "Edit" distinction by hiding download
-- buttons and restricting metadata edits via documents_org_update.
--
-- Security: Defined in app_private to prevent PostgREST RPC exposure.
CREATE OR REPLACE FUNCTION app_private.can_user_access_storage_document(p_file_path TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := (SELECT auth.uid());
  v_org_id TEXT := split_part(p_file_path, '/', 1);
  v_folder TEXT := split_part(p_file_path, '/', 2);
  v_action_ref TEXT := split_part(p_file_path, '/', 3);
  v_doc RECORD;
  v_profile RECORD;
BEGIN
  IF v_uid IS NULL OR v_org_id IS NULL OR length(trim(v_org_id)) = 0 THEN
    RETURN FALSE;
  END IF;

  -- 1. Check user profile & active status
  SELECT p.id, p.organization_id::text as org_id, p.department_id, p.email, p.is_active,
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

  -- Verify user belongs to the target organization (Platform Admins exempt)
  -- Enforce NULL-safe tenant matching
  IF NOT v_profile.is_platform_admin THEN
    IF v_profile.org_id IS NULL 
       OR v_profile.org_id IS DISTINCT FROM v_org_id 
       OR NOT public.check_user_in_org(v_org_id) THEN
      RETURN FALSE;
    END IF;
  END IF;

  -- 2. Request attachments routing
  IF v_folder = 'requests' THEN
    RETURN app_private.can_user_access_storage_request(p_file_path);
  END IF;

  -- 3. Action attachments routing: <org_id>/actions/<action_id>/<file_name>
  IF v_folder = 'actions' AND v_action_ref IS NOT NULL AND v_action_ref != '' THEN
    IF EXISTS (
      SELECT 1 FROM public.actions a
      WHERE (a.id::text = v_action_ref OR a.action_number = v_action_ref)
        AND a.organization_id::text = v_org_id
        AND (
          v_profile.is_platform_admin
          OR (v_profile.is_admin AND v_profile.org_id IS NOT NULL AND v_profile.org_id = v_org_id)
          OR a.assigned_to = v_uid OR a.created_by = v_uid
          OR EXISTS (SELECT 1 FROM public.action_contributors ac WHERE ac.action_id = a.id AND ac.profile_id = v_uid)
          OR EXISTS (SELECT 1 FROM public.action_assignees aa WHERE aa.action_id = a.id AND aa.profile_id = v_uid)
          OR (
            a.subtasks IS NOT NULL AND jsonb_typeof(a.subtasks) = 'array'
            AND EXISTS (
              SELECT 1 FROM jsonb_array_elements(a.subtasks) elem
              WHERE elem->>'assigned_staff_id' = v_uid::text
                 OR (v_profile.email IS NOT NULL AND lower(trim(elem->>'assigned_staff_email')) = lower(trim(v_profile.email)))
            )
          )
          OR (
            v_profile.is_manager AND (
              (a.scope_type = 'organization' AND a.created_by = v_uid)
              OR (COALESCE(a.scope_type, 'specific') = 'specific' AND public.is_manager_of_scope(a.department_id, a.site_id))
              OR (a.scope_type = 'department' AND public.is_manager_of_department_wide(a.department_id))
              OR (a.scope_type = 'site' AND public.is_manager_of_site_wide(a.site_id))
            )
          )
        )
    ) THEN
      RETURN TRUE;
    END IF;
    RETURN FALSE;
  END IF;

  -- 4. Administrative Governance: Platform Admins (system-wide) or Company Admins (strictly within own organization)
  IF v_profile.is_platform_admin THEN
    RETURN TRUE;
  END IF;

  IF v_profile.is_admin AND v_profile.org_id IS NOT NULL AND v_profile.org_id = v_org_id THEN
    RETURN TRUE;
  END IF;

  -- 5. Lookup document metadata
  SELECT * INTO v_doc
  FROM public.documents
  WHERE file_path = p_file_path
    AND (organization_id = v_org_id OR organization_id = v_profile.org_id)
    AND is_archived = FALSE;

  -- Fresh upload handling: allow caller if they are the direct storage object owner
  IF NOT FOUND THEN
    RETURN EXISTS (
      SELECT 1 FROM storage.objects
      WHERE name = p_file_path
        AND bucket_id = 'documents'
        AND (owner = v_uid OR owner_id = v_uid::text)
    );
  END IF;

  -- 6. Document Owner / Author
  IF v_doc.created_by = v_uid THEN
    RETURN TRUE;
  END IF;

  -- 7. Explicit Share Recipient (via non-recursive helper)
  IF app_private.is_document_shared_with_caller(v_doc.id) THEN
    RETURN TRUE;
  END IF;

  -- 8. Linked Action Participant
  IF v_doc.action_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.actions a
    WHERE (a.id::text = v_doc.action_id OR a.action_number = v_doc.action_id)
      AND (a.organization_id::text = v_org_id OR a.organization_id::text = v_profile.org_id)
      AND (
        a.assigned_to = v_uid OR a.created_by = v_uid
        OR EXISTS (SELECT 1 FROM public.action_contributors ac WHERE ac.action_id = a.id AND ac.profile_id = v_uid)
        OR EXISTS (SELECT 1 FROM public.action_assignees aa WHERE aa.action_id = a.id AND aa.profile_id = v_uid)
        OR (v_profile.is_manager AND public.is_manager_of_scope(a.department_id, a.site_id))
      )
  ) THEN
    RETURN TRUE;
  END IF;

  -- 9. Genuine Company-Wide Guidelines & Policies (Strictly EXCLUDES 'General')
  IF v_doc.category IN ('HSSE Manuals', 'Policies', 'Policies & Procedures', 'Manuals & Guides')
     AND (v_doc.department_id IS NULL OR v_doc.department_id = v_profile.department_id) THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION app_private.can_user_access_storage_document(TEXT)
IS 'Internal non-probing helper for storage.objects RLS on documents bucket. Relocated to app_private to prevent PostgREST RPC exposure.';

REVOKE ALL ON FUNCTION app_private.can_user_access_storage_document(TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION app_private.can_user_access_storage_document(TEXT) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 6. Harden storage.objects Policies on 'documents' Bucket
-- ----------------------------------------------------------------------------
-- Drop existing policies that depend on the legacy helper first
DROP POLICY IF EXISTS "documents_storage_select" ON storage.objects;
DROP POLICY IF EXISTS "documents_storage_insert" ON storage.objects;
DROP POLICY IF EXISTS "documents_storage_update" ON storage.objects;
DROP POLICY IF EXISTS "documents_storage_delete" ON storage.objects;

-- Safely drop legacy public helper to close public RPC exposure
DROP FUNCTION IF EXISTS public.can_user_access_storage_document(TEXT);

CREATE POLICY "documents_storage_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND split_part(name, '/', 2) != 'requests'
    AND app_private.can_user_access_storage_document(name)
  );

CREATE POLICY "documents_storage_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'documents'
    AND public.check_user_in_org(split_part(name, '/', 1))
    AND (owner = auth.uid() OR owner_id = auth.uid()::text)
  );

CREATE POLICY "documents_storage_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'documents'
    AND public.check_user_in_org(split_part(name, '/', 1))
    AND (
      owner = auth.uid() 
      OR owner_id = auth.uid()::text
      OR EXISTS (
        SELECT 1 FROM public.profiles p
        JOIN public.roles r ON p.role_id = r.id
        WHERE p.id = auth.uid()
          AND (r.code IN ('admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = true)
          AND p.is_active = true
      )
    )
  );

CREATE POLICY "documents_storage_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'documents'
    AND public.check_user_in_org(split_part(name, '/', 1))
    AND (
      owner = auth.uid() 
      OR owner_id = auth.uid()::text
      OR EXISTS (
        SELECT 1 FROM public.profiles p
        JOIN public.roles r ON p.role_id = r.id
        WHERE p.id = auth.uid()
          AND (r.code IN ('admin', 'company_admin', 'platform_admin') OR p.is_primary_admin = true)
          AND p.is_active = true
      )
    )
  );

COMMIT;
