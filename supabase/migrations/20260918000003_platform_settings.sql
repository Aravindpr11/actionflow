-- ============================================================================
-- ActionFlow Platform Governance: Platform Settings & Configuration
-- Migration: 20260918000003_platform_settings.sql
-- ============================================================================
-- Manages platform-level configuration parameters with database persistence:
-- - Platform identification and branding defaults
-- - Global session & security policy controls
-- - Audit log retention settings
--
-- Security Model:
-- - Strictly restricted to verified Platform Administrators (is_platform_admin())
-- - Company Admins, Managers, and Staff have zero access
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.platform_settings (
  key VARCHAR(100) PRIMARY KEY,
  category VARCHAR(50) NOT NULL,
  value JSONB NOT NULL,
  description TEXT,
  is_secret BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

COMMENT ON TABLE public.platform_settings IS 'Platform-wide configuration settings managed exclusively by Platform Administrators.';

-- Enable Row Level Security
ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

-- Policy: Platform Admin manage settings
DROP POLICY IF EXISTS "Platform admin manage settings" ON public.platform_settings;
CREATE POLICY "Platform admin manage settings"
  ON public.platform_settings FOR ALL
  TO authenticated
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

-- Grants
GRANT SELECT, INSERT, UPDATE ON public.platform_settings TO authenticated, service_role;

-- Seed default platform settings
INSERT INTO public.platform_settings (key, category, value, description, is_secret)
VALUES
  ('platform_name', 'general', '{"value": "ActionFlow Enterprise"}'::jsonb, 'Public name of the ActionFlow multi-tenant platform', false),
  ('primary_support_email', 'general', '{"value": "platform-support@actionflow.internal"}'::jsonb, 'Global system and support contact email', false),
  ('maintenance_mode', 'general', '{"value": false}'::jsonb, 'Emergency maintenance mode switch', false),
  ('session_timeout_minutes', 'security', '{"value": 60}'::jsonb, 'Idle session timeout in minutes for administrative portals', false),
  ('require_mfa_for_admins', 'security', '{"value": true}'::jsonb, 'Mandatory 2FA enforcement policy for all Company Administrators', false),
  ('allow_cross_tenant_view', 'security', '{"value": false}'::jsonb, 'Strict multi-tenant isolation switch (never allow cross-tenant inspection)', false),
  ('audit_retention_days', 'governance', '{"value": 365}'::jsonb, 'Immutability and retention period in days for global audit logs', false)
ON CONFLICT (key) DO NOTHING;

