-- ============================================================================
-- ActionFlow Actions System & Manager Scope-Based RLS Migration
-- Migration: 20260921000001_create_actions_system_and_manager_rls.sql
-- ============================================================================
-- 1. Creates public.actions table with sequence-backed action numbers (ACT-1001...)
-- 2. Foreign keys to organizations, departments, sites, teams, and profiles
-- 3. Strict validation trigger enforcing organization match, active department/site,
--    manager scope authority, and valid in-scope active assignee.
-- 4. Multi-tier RLS policies covering SELECT, INSERT, UPDATE, DELETE for:
--    - Platform Admins (global)
--    - Company Admins (organization-wide)
--    - Managers (restricted strictly to organization and permitted manager scopes)
--    - Staff (restricted strictly to organization and self-assignments)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Sequence & Auto-Number Generator
-- ----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS public.actions_seq START WITH 1001;

-- ----------------------------------------------------------------------------
-- 2. Table: public.actions
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  action_number VARCHAR(50) NOT NULL UNIQUE DEFAULT ('ACT-' || nextval('public.actions_seq')::text),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
  site_id UUID NOT NULL REFERENCES public.sites(id) ON DELETE RESTRICT,
  team_id UUID REFERENCES public.teams(id) ON DELETE SET NULL,
  title VARCHAR(255) NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  action_required TEXT NOT NULL DEFAULT '',
  category VARCHAR(100) NOT NULL DEFAULT 'Inspection',
  source VARCHAR(150) NOT NULL DEFAULT 'Direct Action',
  priority VARCHAR(50) NOT NULL DEFAULT 'Medium' CHECK (priority IN ('Low', 'Medium', 'High', 'Critical')),
  status VARCHAR(50) NOT NULL DEFAULT 'Open' CHECK (status IN ('Open', 'In Progress', 'Pending Review', 'Overdue', 'Closed', 'Rejected')),
  percent_complete INTEGER NOT NULL DEFAULT 0 CHECK (percent_complete >= 0 AND percent_complete <= 100),
  target_date DATE NOT NULL,
  date_raised DATE NOT NULL DEFAULT CURRENT_DATE,
  last_follow_up_date DATE,
  next_follow_up_date DATE,
  close_date DATE,
  closed_at TIMESTAMPTZ,
  created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  assigned_to UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  verified_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  subtasks JSONB NOT NULL DEFAULT '[]'::jsonb,
  attachments JSONB NOT NULL DEFAULT '[]'::jsonb,
  history JSONB NOT NULL DEFAULT '[]'::jsonb,
  worker_message_subject TEXT NOT NULL DEFAULT '',
  worker_message TEXT NOT NULL DEFAULT '',
  manager_message TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- 3. Indexes for Performance and RLS Filtering
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_actions_org_id ON public.actions(organization_id);
CREATE INDEX IF NOT EXISTS idx_actions_dept_site ON public.actions(department_id, site_id);
CREATE INDEX IF NOT EXISTS idx_actions_assigned_to ON public.actions(assigned_to);
CREATE INDEX IF NOT EXISTS idx_actions_created_by ON public.actions(created_by);
CREATE INDEX IF NOT EXISTS idx_actions_status ON public.actions(status);
CREATE INDEX IF NOT EXISTS idx_actions_target_date ON public.actions(target_date);
CREATE INDEX IF NOT EXISTS idx_actions_created_at ON public.actions(created_at DESC);

-- ----------------------------------------------------------------------------
-- 4. Server-Side Validation Trigger Function
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_action_before_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_org_id UUID;
  v_is_platform BOOLEAN := false;
  v_is_company_admin BOOLEAN := false;
  v_is_mgr BOOLEAN := false;
  v_dept_active BOOLEAN;
  v_dept_org UUID;
  v_site_active BOOLEAN;
  v_site_org UUID;
  v_assignee_org UUID;
  v_assignee_active BOOLEAN;
  v_assignee_status VARCHAR(50);
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NOT NULL THEN
    v_is_platform := public.is_platform_admin();
    v_is_company_admin := public.is_admin();
    v_is_mgr := public.is_manager();
    v_caller_org_id := public.get_my_organization_id();
  END IF;

  -- A. Enforce Organization Binding
  IF NOT v_is_platform THEN
    IF v_caller_org_id IS NULL THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: User is not linked to an active organization.';
    END IF;
    -- Always force organization_id to caller's authoritative organization
    NEW.organization_id := v_caller_org_id;
  END IF;

  -- B. Auto-bind created_by on INSERT
  IF TG_OP = 'INSERT' THEN
    IF NEW.created_by IS NULL THEN
      NEW.created_by := v_caller_id;
    ELSIF NOT v_is_platform AND NEW.created_by != v_caller_id THEN
      -- Cannot create on behalf of someone else
      NEW.created_by := v_caller_id;
    END IF;
  END IF;

  -- C. Validate Department (must exist, belong to org, and be active)
  SELECT is_active, organization_id INTO v_dept_active, v_dept_org
  FROM public.departments WHERE id = NEW.department_id;
  IF v_dept_org IS NULL OR v_dept_org != NEW.organization_id THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Department does not belong to this organization.';
  END IF;
  IF v_dept_active IS NOT TRUE THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive department.';
  END IF;

  -- D. Validate Site (must exist, belong to org, and be active)
  SELECT is_active, organization_id INTO v_site_active, v_site_org
  FROM public.sites WHERE id = NEW.site_id;
  IF v_site_org IS NULL OR v_site_org != NEW.organization_id THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Site does not belong to this organization.';
  END IF;
  IF v_site_active IS NOT TRUE THEN
    RAISE EXCEPTION 'ActionFlow Validation Error: Cannot associate action with an inactive site.';
  END IF;

  -- E. Manager Scope Enforcement
  IF v_is_mgr AND NOT v_is_company_admin AND NOT v_is_platform THEN
    IF NOT public.is_manager_of_scope(NEW.department_id, NEW.site_id) THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: You do not have manager authority over this department and site scope.';
    END IF;
  END IF;

  -- F. Assignee Validation (if assigned_to is specified)
  IF NEW.assigned_to IS NOT NULL THEN
    SELECT organization_id, is_active, status
    INTO v_assignee_org, v_assignee_active, v_assignee_status
    FROM public.profiles WHERE id = NEW.assigned_to;

    IF v_assignee_org IS NULL OR v_assignee_org != NEW.organization_id THEN
      RAISE EXCEPTION 'ActionFlow Security Violation: Assigned user does not belong to this organization.';
    END IF;
    IF v_assignee_active IS NOT TRUE OR v_assignee_status != 'active' THEN
      RAISE EXCEPTION 'ActionFlow Validation Error: Assigned user is inactive or not approved.';
    END IF;
  END IF;

  -- G. Auto-maintain history log
  IF TG_OP = 'INSERT' THEN
    IF NEW.history IS NULL OR jsonb_array_length(NEW.history) = 0 THEN
      NEW.history := jsonb_build_array(
        jsonb_build_object(
          'timestamp', now(),
          'action', 'Action created',
          'actor_id', v_caller_id,
          'status', NEW.status
        )
      );
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.updated_at := now();
    IF NEW.status IS DISTINCT FROM OLD.status OR NEW.percent_complete IS DISTINCT FROM OLD.percent_complete THEN
      NEW.history := COALESCE(OLD.history, '[]'::jsonb) || jsonb_build_object(
        'timestamp', now(),
        'action', format('Status changed to %s (%s%%)', NEW.status, NEW.percent_complete),
        'actor_id', v_caller_id,
        'old_status', OLD.status,
        'new_status', NEW.status,
        'percent', NEW.percent_complete
      );
    END IF;

    -- If closed
    IF NEW.status = 'Closed' AND OLD.status != 'Closed' THEN
      NEW.close_date := CURRENT_DATE;
      NEW.closed_at := now();
      NEW.verified_by := v_caller_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_action_before_write ON public.actions;
CREATE TRIGGER trg_validate_action_before_write
  BEFORE INSERT OR UPDATE ON public.actions
  FOR EACH ROW EXECUTE FUNCTION public.validate_action_before_write();

-- ----------------------------------------------------------------------------
-- 5. Row Level Security Policies (RLS)
-- ----------------------------------------------------------------------------
ALTER TABLE public.actions ENABLE ROW LEVEL SECURITY;

-- A. SELECT Policies
DROP POLICY IF EXISTS "Platform admin select actions" ON public.actions;
CREATE POLICY "Platform admin select actions"
  ON public.actions FOR SELECT TO authenticated
  USING (public.is_platform_admin());

DROP POLICY IF EXISTS "Company admin select actions" ON public.actions;
CREATE POLICY "Company admin select actions"
  ON public.actions FOR SELECT TO authenticated
  USING (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  );

DROP POLICY IF EXISTS "Manager select actions" ON public.actions;
CREATE POLICY "Manager select actions"
  ON public.actions FOR SELECT TO authenticated
  USING (
    public.is_manager()
    AND organization_id = public.get_my_organization_id()
    AND (
      public.is_manager_of_scope(department_id, site_id)
      OR created_by = auth.uid()
      OR assigned_to = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Staff select actions" ON public.actions;
CREATE POLICY "Staff select actions"
  ON public.actions FOR SELECT TO authenticated
  USING (
    organization_id = public.get_my_organization_id()
    AND (assigned_to = auth.uid() OR created_by = auth.uid())
  );

-- B. INSERT Policies
DROP POLICY IF EXISTS "Platform admin insert actions" ON public.actions;
CREATE POLICY "Platform admin insert actions"
  ON public.actions FOR INSERT TO authenticated
  WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "Company admin insert actions" ON public.actions;
CREATE POLICY "Company admin insert actions"
  ON public.actions FOR INSERT TO authenticated
  WITH CHECK (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  );

DROP POLICY IF EXISTS "Manager insert actions" ON public.actions;
CREATE POLICY "Manager insert actions"
  ON public.actions FOR INSERT TO authenticated
  WITH CHECK (
    public.is_manager()
    AND organization_id = public.get_my_organization_id()
    AND created_by = auth.uid()
    AND public.is_manager_of_scope(department_id, site_id)
  );

-- C. UPDATE Policies
DROP POLICY IF EXISTS "Platform admin update actions" ON public.actions;
CREATE POLICY "Platform admin update actions"
  ON public.actions FOR UPDATE TO authenticated
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "Company admin update actions" ON public.actions;
CREATE POLICY "Company admin update actions"
  ON public.actions FOR UPDATE TO authenticated
  USING (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  )
  WITH CHECK (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  );

DROP POLICY IF EXISTS "Manager update actions" ON public.actions;
CREATE POLICY "Manager update actions"
  ON public.actions FOR UPDATE TO authenticated
  USING (
    public.is_manager()
    AND organization_id = public.get_my_organization_id()
    AND (
      public.is_manager_of_scope(department_id, site_id)
      OR created_by = auth.uid()
    )
  )
  WITH CHECK (
    public.is_manager()
    AND organization_id = public.get_my_organization_id()
    AND public.is_manager_of_scope(department_id, site_id)
  );

DROP POLICY IF EXISTS "Staff update actions" ON public.actions;
CREATE POLICY "Staff update actions"
  ON public.actions FOR UPDATE TO authenticated
  USING (
    organization_id = public.get_my_organization_id()
    AND assigned_to = auth.uid()
  )
  WITH CHECK (
    organization_id = public.get_my_organization_id()
    AND assigned_to = auth.uid()
  );

-- D. DELETE Policies
DROP POLICY IF EXISTS "Platform admin delete actions" ON public.actions;
CREATE POLICY "Platform admin delete actions"
  ON public.actions FOR DELETE TO authenticated
  USING (public.is_platform_admin());

DROP POLICY IF EXISTS "Company admin delete actions" ON public.actions;
CREATE POLICY "Company admin delete actions"
  ON public.actions FOR DELETE TO authenticated
  USING (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  );

DROP POLICY IF EXISTS "Manager delete actions" ON public.actions;
CREATE POLICY "Manager delete actions"
  ON public.actions FOR DELETE TO authenticated
  USING (
    public.is_manager()
    AND organization_id = public.get_my_organization_id()
    AND created_by = auth.uid()
    AND public.is_manager_of_scope(department_id, site_id)
  );

-- ----------------------------------------------------------------------------
-- 6. Table & Sequence Grants
-- ----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON public.actions TO authenticated;
GRANT ALL ON public.actions TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.actions_seq TO authenticated;
GRANT ALL ON SEQUENCE public.actions_seq TO service_role;
