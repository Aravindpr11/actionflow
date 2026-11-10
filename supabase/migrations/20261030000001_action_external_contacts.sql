-- ============================================================================
-- PROPOSED MIGRATION (Phase 3.3 - Local Draft / Not Applied Remotely)
-- Migration: 20261030000001_action_external_contacts.sql
-- Description: Dedicated relational table for additional external contacts linked
--              to actions. Decouples external non-login recipients from internal
--              profiles in action_assignees.
--
-- Prerequisites:
--   1. public.organizations table must exist.
--   2. public.actions table must exist.
--   3. public.external_action_recipients table must exist.
--   4. public.check_user_in_org(uuid) helper function must exist.
--   5. public.check_user_is_manager_or_admin(uuid) helper function must exist.
--
-- Rollback Instructions:
--   DROP TABLE IF EXISTS public.action_external_contacts CASCADE;
-- ============================================================================

-- Provide UUID overloads for organization checks if only TEXT exists
CREATE OR REPLACE FUNCTION public.check_user_in_org(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT public.check_user_in_org(p_org_id::TEXT);
$$;
GRANT EXECUTE ON FUNCTION public.check_user_in_org(UUID) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.check_user_is_manager_or_admin(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT public.check_user_is_manager_or_admin(p_org_id::TEXT);
$$;
GRANT EXECUTE ON FUNCTION public.check_user_is_manager_or_admin(UUID) TO authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.action_external_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    action_id UUID NOT NULL REFERENCES public.actions(id) ON DELETE CASCADE,
    external_recipient_id UUID NOT NULL REFERENCES public.external_action_recipients(id) ON DELETE CASCADE,
    contact_role TEXT NOT NULL DEFAULT 'additional_contact',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_action_external_contact UNIQUE (action_id, external_recipient_id)
);

-- Indices for performant querying and join resolution
CREATE INDEX IF NOT EXISTS idx_action_ext_contacts_action 
    ON public.action_external_contacts(action_id);
CREATE INDEX IF NOT EXISTS idx_action_ext_contacts_recipient 
    ON public.action_external_contacts(external_recipient_id);
CREATE INDEX IF NOT EXISTS idx_action_ext_contacts_org 
    ON public.action_external_contacts(organization_id);

-- Enable Row Level Security (RLS)
ALTER TABLE public.action_external_contacts ENABLE ROW LEVEL SECURITY;

-- RLS: Read visibility restricted to members of the same organization
DROP POLICY IF EXISTS "action_external_contacts_select" ON public.action_external_contacts;
CREATE POLICY "action_external_contacts_select"
    ON public.action_external_contacts
    FOR SELECT
    USING (public.check_user_in_org(organization_id));

-- RLS: Write permissions restricted to managers/admins of the organization
DROP POLICY IF EXISTS "action_external_contacts_manage" ON public.action_external_contacts;
CREATE POLICY "action_external_contacts_manage"
    ON public.action_external_contacts
    FOR ALL
    USING (public.check_user_is_manager_or_admin(organization_id))
    WITH CHECK (public.check_user_is_manager_or_admin(organization_id));
