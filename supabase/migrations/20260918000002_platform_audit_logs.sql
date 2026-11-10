-- ============================================================================
-- ActionFlow Platform Governance: Immutable Global Audit Logs
-- Migration: 20260918000002_platform_audit_logs.sql
-- ============================================================================
-- Provides an append-only, immutable audit ledger for platform-level events:
-- - Organization provisioning, updates, and cascade deletions
-- - Company Administrator invitations and assignments
-- - Platform security checks and settings changes
-- - Platform Administrator session and governance events
--
-- Security Model:
-- - strictly restricted to verified Platform Administrators (is_platform_admin())
-- - Company Admins, Managers, and Staff have zero read or write access
-- - No UPDATE or DELETE policies: records are permanent and append-only
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.platform_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  event_type VARCHAR(100) NOT NULL,
  category VARCHAR(50) NOT NULL DEFAULT 'governance',
  severity VARCHAR(20) NOT NULL DEFAULT 'info',
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_email VARCHAR(255),
  organization_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL,
  target_type VARCHAR(50),
  target_id VARCHAR(255),
  description TEXT NOT NULL,
  metadata JSONB DEFAULT '{}'::jsonb
);

COMMENT ON TABLE public.platform_audit_logs IS 'Immutable platform-level audit log for platform administrators.';

CREATE INDEX IF NOT EXISTS idx_platform_audit_logs_created_at ON public.platform_audit_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_platform_audit_logs_category ON public.platform_audit_logs (category);
CREATE INDEX IF NOT EXISTS idx_platform_audit_logs_event_type ON public.platform_audit_logs (event_type);
CREATE INDEX IF NOT EXISTS idx_platform_audit_logs_org ON public.platform_audit_logs (organization_id);

-- Enable Row Level Security
ALTER TABLE public.platform_audit_logs ENABLE ROW LEVEL SECURITY;

-- 1. Read Policy: Platform Admins only
DROP POLICY IF EXISTS "Platform admin read audit logs" ON public.platform_audit_logs;
CREATE POLICY "Platform admin read audit logs"
  ON public.platform_audit_logs FOR SELECT
  TO authenticated
  USING (public.is_platform_admin());

-- 2. Insert Policy: Platform Admins can record audit events
DROP POLICY IF EXISTS "Platform admin insert audit logs" ON public.platform_audit_logs;
CREATE POLICY "Platform admin insert audit logs"
  ON public.platform_audit_logs FOR INSERT
  TO authenticated
  WITH CHECK (public.is_platform_admin());

-- Notice: NO UPDATE or DELETE policies are created. Audit records cannot be modified or deleted.

-- Grant table privileges
GRANT SELECT, INSERT ON public.platform_audit_logs TO authenticated, service_role;

-- Helper RPC for recording audit events safely from Edge Functions or client
CREATE OR REPLACE FUNCTION public.record_platform_audit_event(
  p_event_type VARCHAR(100),
  p_category VARCHAR(50),
  p_severity VARCHAR(20),
  p_description TEXT,
  p_organization_id UUID DEFAULT NULL,
  p_target_type VARCHAR(50) DEFAULT NULL,
  p_target_id VARCHAR(255) DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_new_id UUID;
  v_actor_email VARCHAR(255);
BEGIN
  -- Verify caller is a platform admin
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'ActionFlow Security Violation: Only Platform Administrators may record platform audit events.';
  END IF;

  SELECT email INTO v_actor_email
  FROM auth.users
  WHERE id = auth.uid();

  INSERT INTO public.platform_audit_logs (
    event_type,
    category,
    severity,
    actor_id,
    actor_email,
    organization_id,
    target_type,
    target_id,
    description,
    metadata
  ) VALUES (
    p_event_type,
    COALESCE(p_category, 'governance'),
    COALESCE(p_severity, 'info'),
    auth.uid(),
    v_actor_email,
    p_organization_id,
    p_target_type,
    p_target_id,
    p_description,
    COALESCE(p_metadata, '{}'::jsonb)
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_platform_audit_event TO authenticated, service_role;

