-- ============================================================================
-- Migration: 20261021000001_documents_system_and_sharing.sql
-- Description:
--   1. Creates documents, document_shares, and document_external_tokens tables.
--   2. Ensures the private 'documents' storage bucket exists in storage.buckets.
--   3. Configures RLS policies for storage objects and tables with strict multi-tenant
--      and organization isolation.
--   4. Adds secure RPCs for document management, internal sharing, and external token
--      generation/verification using SHA-256 hashes.
--   5. Reloads PostgREST schema cache.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Private Storage Bucket Setup
-- ----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('documents', 'documents', false)
ON CONFLICT (id) DO UPDATE SET public = false;

-- ----------------------------------------------------------------------------
-- 2. Documents Table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.documents (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL,
  department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  description TEXT DEFAULT '',
  category TEXT NOT NULL DEFAULT 'General',
  file_name TEXT NOT NULL,
  file_path TEXT NOT NULL,
  file_size BIGINT NOT NULL,
  file_type TEXT NOT NULL,
  storage_bucket TEXT NOT NULL DEFAULT 'documents',
  action_id TEXT,
  action_number TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_by_name TEXT DEFAULT '',
  is_archived BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  shared_internal_count INT NOT NULL DEFAULT 0,
  shared_external_count INT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_documents_org_created
  ON public.documents (organization_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_documents_action
  ON public.documents (action_id)
  WHERE action_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_documents_category
  ON public.documents (organization_id, category);

CREATE INDEX IF NOT EXISTS idx_documents_department
  ON public.documents (department_id)
  WHERE department_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 3. Document Shares Table (Internal Staff / Managers)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.document_shares (
  id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL REFERENCES public.documents(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_name TEXT DEFAULT '',
  user_email TEXT DEFAULT '',
  organization_id TEXT NOT NULL,
  permission TEXT NOT NULL DEFAULT 'view', -- 'view' or 'download'
  shared_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  shared_by_name TEXT DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_document_share_user UNIQUE (document_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_document_shares_doc
  ON public.document_shares (document_id);

CREATE INDEX IF NOT EXISTS idx_document_shares_user
  ON public.document_shares (user_id);

CREATE INDEX IF NOT EXISTS idx_document_shares_org
  ON public.document_shares (organization_id);

-- ----------------------------------------------------------------------------
-- 4. Document External Tokens Table (SHA-256 Hashed Tokens)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.document_external_tokens (
  id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL REFERENCES public.documents(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  recipient_email TEXT NOT NULL,
  recipient_name TEXT DEFAULT '',
  organization_id TEXT NOT NULL,
  permission TEXT NOT NULL DEFAULT 'view', -- 'view' or 'download'
  expires_at TIMESTAMPTZ NOT NULL,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_by_name TEXT DEFAULT '',
  is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  revoked_at TIMESTAMPTZ,
  revoked_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  revocation_reason TEXT,
  access_count INT NOT NULL DEFAULT 0,
  last_accessed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_doc_ext_tokens_hash
  ON public.document_external_tokens (token_hash);

CREATE INDEX IF NOT EXISTS idx_doc_ext_tokens_doc
  ON public.document_external_tokens (document_id);

CREATE INDEX IF NOT EXISTS idx_doc_ext_tokens_expires
  ON public.document_external_tokens (expires_at);

-- ----------------------------------------------------------------------------
-- 5. Enable Row Level Security (RLS)
-- ----------------------------------------------------------------------------
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_external_tokens ENABLE ROW LEVEL SECURITY;

-- Helper function to check if caller belongs to an organization
CREATE OR REPLACE FUNCTION public.check_user_in_org(p_org_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND (organization_id::text = p_org_id OR p_org_id IS NULL)
      AND is_active = TRUE
  );
$$;

-- Helper function to check if caller is manager or company admin
CREATE OR REPLACE FUNCTION public.check_user_is_manager_or_admin(p_org_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    LEFT JOIN public.roles r ON p.role_id = r.id
    WHERE p.id = auth.uid()
      AND (p.organization_id::text = p_org_id OR p_org_id IS NULL)
      AND p.is_active = TRUE
      AND (
        r.code IN ('manager', 'admin')
        OR p.is_primary_admin = TRUE
      )
  );
$$;

-- Documents RLS Policies
DROP POLICY IF EXISTS "documents_org_select" ON public.documents;
CREATE POLICY "documents_org_select" ON public.documents
  FOR SELECT USING (
    -- 1. Managers, company admins, and platform owners have full visibility in the org
    public.check_user_is_manager_or_admin(organization_id)
    -- 2. Author/creator can view their own document
    OR auth.uid() = created_by
    -- 3. Explicitly shared users (internal staff shares)
    OR EXISTS (
      SELECT 1 FROM public.document_shares
      WHERE document_shares.document_id = documents.id
        AND document_shares.user_id = auth.uid()
    )
    -- 4. Organization members with department authorization
    OR (
      public.check_user_in_org(organization_id)
      AND (
        -- Organization-wide documents (no department assigned)
        documents.department_id IS NULL
        -- Same-department access allowed
        OR EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid()
            AND p.department_id = documents.department_id
            AND p.is_active = TRUE
        )
      )
    )
  );

DROP POLICY IF EXISTS "documents_org_insert" ON public.documents;
CREATE POLICY "documents_org_insert" ON public.documents
  FOR INSERT WITH CHECK (
    public.check_user_in_org(organization_id)
  );

DROP POLICY IF EXISTS "documents_org_update" ON public.documents;
CREATE POLICY "documents_org_update" ON public.documents
  FOR UPDATE USING (
    public.check_user_is_manager_or_admin(organization_id)
    OR auth.uid() = created_by
  );

DROP POLICY IF EXISTS "documents_org_delete" ON public.documents;
CREATE POLICY "documents_org_delete" ON public.documents
  FOR DELETE USING (
    public.check_user_is_manager_or_admin(organization_id)
    OR auth.uid() = created_by
  );

-- Document Shares RLS Policies
DROP POLICY IF EXISTS "document_shares_select" ON public.document_shares;
CREATE POLICY "document_shares_select" ON public.document_shares
  FOR SELECT USING (
    public.check_user_in_org(organization_id)
    OR user_id = auth.uid()
  );

DROP POLICY IF EXISTS "document_shares_manage" ON public.document_shares;
DROP POLICY IF EXISTS "document_shares_insert" ON public.document_shares;
CREATE POLICY "document_shares_insert" ON public.document_shares
  FOR INSERT WITH CHECK (
    public.check_user_is_manager_or_admin(organization_id)
    OR EXISTS (
      SELECT 1 FROM public.documents
      WHERE documents.id = document_shares.document_id
        AND documents.created_by = auth.uid()
    )
  );

DROP POLICY IF EXISTS "document_shares_update" ON public.document_shares;
CREATE POLICY "document_shares_update" ON public.document_shares
  FOR UPDATE USING (
    public.check_user_is_manager_or_admin(organization_id)
    OR EXISTS (
      SELECT 1 FROM public.documents
      WHERE documents.id = document_shares.document_id
        AND documents.created_by = auth.uid()
    )
  );

DROP POLICY IF EXISTS "document_shares_delete" ON public.document_shares;
CREATE POLICY "document_shares_delete" ON public.document_shares
  FOR DELETE USING (
    public.check_user_is_manager_or_admin(organization_id)
    OR EXISTS (
      SELECT 1 FROM public.documents
      WHERE documents.id = document_shares.document_id
        AND documents.created_by = auth.uid()
    )
  );

-- Document External Tokens RLS Policies
DROP POLICY IF EXISTS "document_external_tokens_select" ON public.document_external_tokens;
CREATE POLICY "document_external_tokens_select" ON public.document_external_tokens
  FOR SELECT USING (
    public.check_user_is_manager_or_admin(organization_id)
    OR created_by = auth.uid()
  );

DROP POLICY IF EXISTS "document_external_tokens_manage" ON public.document_external_tokens;
CREATE POLICY "document_external_tokens_manage" ON public.document_external_tokens
  FOR ALL USING (
    public.check_user_is_manager_or_admin(organization_id)
    OR created_by = auth.uid()
  );

-- ----------------------------------------------------------------------------
-- 6. Storage Bucket Objects Security Policies
-- ----------------------------------------------------------------------------
-- Policy: Authenticated users can view objects belonging to their organization
DROP POLICY IF EXISTS "documents_storage_select" ON storage.objects;
CREATE POLICY "documents_storage_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND public.check_user_in_org(split_part(name, '/', 1))
  );

-- Policy: Authenticated users can upload objects into their organization prefix
DROP POLICY IF EXISTS "documents_storage_insert" ON storage.objects;
CREATE POLICY "documents_storage_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'documents'
    AND public.check_user_in_org(split_part(name, '/', 1))
  );

-- Policy: Managers or uploaders can delete objects from storage
DROP POLICY IF EXISTS "documents_storage_delete" ON storage.objects;
CREATE POLICY "documents_storage_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'documents'
    AND (
      public.check_user_is_manager_or_admin(split_part(name, '/', 1))
      OR owner = auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- 7. Document External Verification RPC (Anonymous / Token-based)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.verify_document_external_token(
  p_token_hash TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_token public.document_external_tokens%ROWTYPE;
  v_doc public.documents%ROWTYPE;
BEGIN
  -- 1. Locate the token
  SELECT * INTO v_token
  FROM public.document_external_tokens
  WHERE token_hash = p_token_hash;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid document token.');
  END IF;

  -- 2. Check if revoked
  IF v_token.is_revoked THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This document access token has been revoked by the manager.'
    );
  END IF;

  -- 3. Check expiration
  IF v_token.expires_at < now() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This document access token has expired.'
    );
  END IF;

  -- 4. Fetch the document record
  SELECT * INTO v_doc
  FROM public.documents
  WHERE id = v_token.document_id
    AND is_archived = FALSE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'The referenced document is no longer available.'
    );
  END IF;

  -- 5. Record access metric
  UPDATE public.document_external_tokens
  SET access_count = access_count + 1,
      last_accessed_at = now()
  WHERE id = v_token.id;

  RETURN jsonb_build_object(
    'success', true,
    'document', jsonb_build_object(
      'id', v_doc.id,
      'organization_id', v_doc.organization_id,
      'title', v_doc.title,
      'description', v_doc.description,
      'category', v_doc.category,
      'file_name', v_doc.file_name,
      'file_path', v_doc.file_path,
      'file_size', v_doc.file_size,
      'file_type', v_doc.file_type,
      'storage_bucket', v_doc.storage_bucket,
      'action_id', v_doc.action_id,
      'action_number', v_doc.action_number,
      'permission', v_token.permission,
      'recipient_email', v_token.recipient_email,
      'recipient_name', v_token.recipient_name,
      'expires_at', v_token.expires_at
    )
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. PostgREST Schema Cache Reload
-- ----------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';

