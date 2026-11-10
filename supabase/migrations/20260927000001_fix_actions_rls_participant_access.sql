-- ============================================================================
-- Migration: 20260927000001_fix_actions_rls_participant_access.sql
-- Description: Fix Staff Portal RLS access for secondary assignees and contributors.
-- Eliminates recursion, enforces tenant boundaries, and protects immutable junction fields.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Private schema for secure, non-exposed helper functions
-- ----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS app_private;
REVOKE ALL ON SCHEMA app_private FROM public, anon, authenticated;
GRANT USAGE ON SCHEMA app_private TO authenticated;

-- Helper to check if the caller is an assignee or contributor on an action
-- Executes as SECURITY DEFINER to bypass RLS recursion on junction tables
-- Caller identity is derived exclusively from auth.uid() to prevent parameter tampering
CREATE OR REPLACE FUNCTION app_private.is_action_participant(p_action_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.action_assignees
    WHERE action_id = p_action_id AND profile_id = (SELECT auth.uid())
  ) OR EXISTS (
    SELECT 1 FROM public.action_contributors
    WHERE action_id = p_action_id AND profile_id = (SELECT auth.uid())
  );
$$;

REVOKE ALL ON FUNCTION app_private.is_action_participant(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION app_private.is_action_participant(UUID) TO authenticated;

-- Helper to check if the caller can manage assignments/contributors for an action
-- Derived exclusively from auth.uid() to prevent identity spoofing
CREATE OR REPLACE FUNCTION app_private.can_manage_action(p_action_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.actions a
    WHERE a.id = p_action_id
      AND a.organization_id = (SELECT organization_id FROM public.profiles WHERE id = (SELECT auth.uid()) AND is_active = true)
      AND (
        a.created_by = (SELECT auth.uid())
        OR a.assigned_to = (SELECT auth.uid())
        OR (
          EXISTS (
            SELECT 1 FROM public.profiles p
            JOIN public.roles r ON p.role_id = r.id
            WHERE p.id = (SELECT auth.uid()) AND r.code = 'admin' AND p.is_active = true
          )
        )
        OR (
          EXISTS (
            SELECT 1 FROM public.manager_scopes ms
            JOIN public.profiles p ON ms.manager_profile_id = p.id
            WHERE ms.manager_profile_id = (SELECT auth.uid())
              AND ms.department_id = a.department_id
              AND ms.site_id = a.site_id
              AND p.is_active = true
          )
        )
      )
  );
$$;

REVOKE ALL ON FUNCTION app_private.can_manage_action(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION app_private.can_manage_action(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- 2. Update actions SELECT policy for Staff
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Staff select actions" ON public.actions;
CREATE POLICY "Staff select actions" ON public.actions
  FOR SELECT
  TO authenticated
  USING (
    organization_id = public.get_my_organization_id()
    AND (
      assigned_to = (SELECT auth.uid())
      OR created_by = (SELECT auth.uid())
      OR app_private.is_action_participant(id)
    )
  );

-- ----------------------------------------------------------------------------
-- 3. Granular RLS policies for action_assignees
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Select action assignees" ON public.action_assignees;
DROP POLICY IF EXISTS "Manage action assignees" ON public.action_assignees;
DROP POLICY IF EXISTS "Insert action assignees" ON public.action_assignees;
DROP POLICY IF EXISTS "Update action assignees" ON public.action_assignees;
DROP POLICY IF EXISTS "Delete action assignees" ON public.action_assignees;

-- SELECT: Platform admin, same org assignee directly, or anyone with read access to parent action
CREATE POLICY "Select action assignees" ON public.action_assignees
  FOR SELECT
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND (
        profile_id = (SELECT auth.uid())
        OR EXISTS (
          SELECT 1 FROM public.actions a
          WHERE a.id = action_assignees.action_id
            AND a.organization_id = public.get_my_organization_id()
        )
      )
    )
  );

-- INSERT: Platform admin, or same org admin/manager/creator/primary assignee
CREATE POLICY "Insert action assignees" ON public.action_assignees
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND app_private.can_manage_action(action_id)
    )
  );

-- UPDATE: Platform admin, or same org manager/creator/primary, or assignee themselves (controlled by trigger)
CREATE POLICY "Update action assignees" ON public.action_assignees
  FOR UPDATE
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND (
        app_private.can_manage_action(action_id)
        OR profile_id = (SELECT auth.uid())
      )
    )
  )
  WITH CHECK (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND (
        app_private.can_manage_action(action_id)
        OR profile_id = (SELECT auth.uid())
      )
    )
  );

-- DELETE: Platform admin, or same org admin/manager/creator/primary assignee
CREATE POLICY "Delete action assignees" ON public.action_assignees
  FOR DELETE
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND app_private.can_manage_action(action_id)
    )
  );

-- ----------------------------------------------------------------------------
-- 4. Granular RLS policies for action_contributors
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Select action contributors" ON public.action_contributors;
DROP POLICY IF EXISTS "Manage action contributors" ON public.action_contributors;
DROP POLICY IF EXISTS "Insert action contributors" ON public.action_contributors;
DROP POLICY IF EXISTS "Update action contributors" ON public.action_contributors;
DROP POLICY IF EXISTS "Delete action contributors" ON public.action_contributors;

-- SELECT: Platform admin, same org contributor directly, creator/adder directly, or anyone with read access to parent action
CREATE POLICY "Select action contributors" ON public.action_contributors
  FOR SELECT
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND (
        profile_id = (SELECT auth.uid())
        OR added_by = (SELECT auth.uid())
        OR EXISTS (
          SELECT 1 FROM public.actions a
          WHERE a.id = action_contributors.action_id
            AND a.organization_id = public.get_my_organization_id()
        )
      )
    )
  );

-- INSERT: Platform admin, or same org admin/manager/creator/primary assignee
CREATE POLICY "Insert action contributors" ON public.action_contributors
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND app_private.can_manage_action(action_id)
    )
  );

-- UPDATE: Platform admin, or same org admin/manager/creator/primary, or original adder
CREATE POLICY "Update action contributors" ON public.action_contributors
  FOR UPDATE
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND (
        app_private.can_manage_action(action_id)
        OR added_by = (SELECT auth.uid())
      )
    )
  )
  WITH CHECK (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND (
        app_private.can_manage_action(action_id)
        OR added_by = (SELECT auth.uid())
      )
    )
  );

-- DELETE: Platform admin, or same org admin/manager/creator/primary, or original adder
CREATE POLICY "Delete action contributors" ON public.action_contributors
  FOR DELETE
  TO authenticated
  USING (
    public.is_platform_admin()
    OR (
      organization_id = public.get_my_organization_id()
      AND (
        app_private.can_manage_action(action_id)
        OR added_by = (SELECT auth.uid())
      )
    )
  );

-- ----------------------------------------------------------------------------
-- 5. Immutability triggers for junction tables
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_action_assignees_immutable_check()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.id != NEW.id OR
     OLD.organization_id != NEW.organization_id OR
     OLD.action_id != NEW.action_id OR
     OLD.profile_id != NEW.profile_id OR
     OLD.assigned_by != NEW.assigned_by OR
     OLD.created_at != NEW.created_at THEN
    RAISE EXCEPTION 'Cannot modify immutable assignment fields (id, organization_id, action_id, profile_id, assigned_by, created_at)';
  END IF;

  IF NOT (public.is_admin() OR public.is_platform_admin() OR app_private.can_manage_action(OLD.action_id)) THEN
    IF OLD.assignment_role != NEW.assignment_role OR OLD.is_required != NEW.is_required THEN
      RAISE EXCEPTION 'Assignees cannot modify assignment_role or is_required';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_action_assignees_immutable ON public.action_assignees;
CREATE TRIGGER trg_action_assignees_immutable
  BEFORE UPDATE ON public.action_assignees
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_action_assignees_immutable_check();

CREATE OR REPLACE FUNCTION public.fn_action_contributors_immutable_check()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.id != NEW.id OR
     OLD.organization_id != NEW.organization_id OR
     OLD.action_id != NEW.action_id OR
     OLD.profile_id != NEW.profile_id OR
     OLD.added_by != NEW.added_by OR
     OLD.created_at != NEW.created_at THEN
    RAISE EXCEPTION 'Cannot modify immutable contributor fields (id, organization_id, action_id, profile_id, added_by, created_at)';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_action_contributors_immutable ON public.action_contributors;
CREATE TRIGGER trg_action_contributors_immutable
  BEFORE UPDATE ON public.action_contributors
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_action_contributors_immutable_check();

-- ----------------------------------------------------------------------------
-- 6. Table Grants
-- ----------------------------------------------------------------------------
-- Grant DELETE on junction tables to authenticated so RLS policies can govern deletions
GRANT DELETE ON public.action_assignees TO authenticated;
GRANT DELETE ON public.action_contributors TO authenticated;

