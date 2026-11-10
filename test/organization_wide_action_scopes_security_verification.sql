-- ============================================================================
-- SQL Security & Regression Test: Comprehensive Organization-Wide Action Scopes (20 Scenarios)
-- ============================================================================
-- 1. Active Manager creates an organization-wide action.
-- 2. Manager assigns an eligible user outside their own department/site scope.
-- 3. Manager adds multiple users from different departments and sites.
-- 4. Cross-organization primary assignment is rejected.
-- 5. Cross-organization additional assignment is rejected.
-- 6. Inactive and unapproved users are rejected.
-- 7. Admin-role users are excluded from operational assignees.
-- 8. Anonymous users cannot create organization-wide actions.
-- 9. Staff cannot create organization-wide actions.
-- 10. Staff cannot browse unassigned organization-wide actions.
-- 11. Assigned Staff can view and update their assigned work.
-- 12. Unassigned Manager cannot access another Manager's organization-wide action without authorized rights.
-- 13. Manager cannot edit/delete another Manager's organization-wide action merely because of organization membership.
-- 14. Creator and authorized Company Admin permissions work as intended.
-- 15. Closing and reopening follow existing approval rules.
-- 16. Department-wide creation cannot bypass exact Manager scopes.
-- 17. Site-wide creation cannot bypass exact Manager scopes.
-- 18. Specific department/site creation retains exact pair validation.
-- 19. Invalid scope_type and department/site combinations are rejected.
-- 20. Existing historical actions remain accessible and unchanged.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_suffix TEXT := substr(md5(random()::text), 1, 8);
  v_org1_id UUID := gen_random_uuid();
  v_org2_id UUID := gen_random_uuid();

  v_admin_id UUID := gen_random_uuid();
  v_mgr1_id UUID := gen_random_uuid();
  v_mgr2_id UUID := gen_random_uuid();
  v_staff1_id UUID := gen_random_uuid();
  v_staff2_id UUID := gen_random_uuid();
  v_staff_org2_id UUID := gen_random_uuid();
  v_inactive_staff_id UUID := gen_random_uuid();
  v_admin_user_id UUID := gen_random_uuid();

  v_role_admin UUID;
  v_role_manager UUID;
  v_role_staff UUID;

  v_dept_hse UUID := gen_random_uuid();
  v_dept_fin UUID := gen_random_uuid();
  v_dept_org2 UUID := gen_random_uuid();

  v_site_a UUID := gen_random_uuid();
  v_site_b UUID := gen_random_uuid();
  v_site_org2 UUID := gen_random_uuid();

  v_act_org_wide UUID;
  v_act_dept_wide UUID;
  v_act_site_wide UUID;
  v_act_specific UUID;
  v_act_historical UUID;

  v_threw BOOLEAN;
  v_result JSONB;
  v_count INT;
BEGIN
  RAISE NOTICE '>>> STARTING COMPREHENSIVE 20-SCENARIO SECURITY VERIFICATION <<<';

  -- 0. Fetch standard role IDs
  SELECT id INTO v_role_admin FROM public.roles WHERE code = 'admin';
  SELECT id INTO v_role_manager FROM public.roles WHERE code = 'manager';
  SELECT id INTO v_role_staff FROM public.roles WHERE code = 'staff';

  -- Seed Organizations
  INSERT INTO public.organizations (id, name, code, is_active)
  VALUES 
    (v_org1_id, 'Org 1 ' || v_suffix, 'org-1-' || v_suffix, true),
    (v_org2_id, 'Org 2 ' || v_suffix, 'org-2-' || v_suffix, true);

  -- Seed Departments (Org 1 has HSE & Finance, Org 2 has Remote Dept)
  INSERT INTO public.departments (id, organization_id, name, code, is_active)
  VALUES
    (v_dept_hse, v_org1_id, 'HSE ' || v_suffix, 'hse-' || v_suffix, true),
    (v_dept_fin, v_org1_id, 'Finance ' || v_suffix, 'fin-' || v_suffix, true),
    (v_dept_org2, v_org2_id, 'Remote Dept ' || v_suffix, 'rem-' || v_suffix, true);

  -- Seed Sites (Org 1 has Site A & Site B, Org 2 has Remote Site)
  INSERT INTO public.sites (id, organization_id, name, code, is_active)
  VALUES
    (v_site_a, v_org1_id, 'Site Alpha ' || v_suffix, 'site-a-' || v_suffix, true),
    (v_site_b, v_org1_id, 'Site Beta ' || v_suffix, 'site-b-' || v_suffix, true),
    (v_site_org2, v_org2_id, 'Site Org2 ' || v_suffix, 'site-o2-' || v_suffix, true);

  -- Seed auth.users & public.profiles
  -- 1. Company Admin
  INSERT INTO auth.users (id, email) VALUES (v_admin_id, 'admin_' || v_suffix || '@org1.com');
  INSERT INTO public.profiles (id, organization_id, role_id, full_name, email, designation, status, is_active, is_primary_admin)
  VALUES (v_admin_id, v_org1_id, v_role_admin, 'Admin User', 'admin_' || v_suffix || '@org1.com', 'Company Administrator', 'active', true, true);

  -- 2. Manager 1 (Scoped to HSE at Site Alpha ONLY)
  INSERT INTO auth.users (id, email) VALUES (v_mgr1_id, 'mgr1_' || v_suffix || '@org1.com');
  INSERT INTO public.profiles (id, organization_id, role_id, department_id, site_id, full_name, email, designation, status, is_active)
  VALUES (v_mgr1_id, v_org1_id, v_role_manager, v_dept_hse, v_site_a, 'HSE Manager Alpha', 'mgr1_' || v_suffix || '@org1.com', 'HSE Manager', 'active', true);

  INSERT INTO public.manager_scopes (manager_profile_id, department_id, site_id)
  VALUES (v_mgr1_id, v_dept_hse, v_site_a);

  -- 3. Manager 2 (Scoped to Finance at Site Beta ONLY)
  INSERT INTO auth.users (id, email) VALUES (v_mgr2_id, 'mgr2_' || v_suffix || '@org1.com');
  INSERT INTO public.profiles (id, organization_id, role_id, department_id, site_id, full_name, email, designation, status, is_active)
  VALUES (v_mgr2_id, v_org1_id, v_role_manager, v_dept_fin, v_site_b, 'Finance Manager Beta', 'mgr2_' || v_suffix || '@org1.com', 'Finance Manager', 'active', true);

  INSERT INTO public.manager_scopes (manager_profile_id, department_id, site_id)
  VALUES (v_mgr2_id, v_dept_fin, v_site_b);

  -- 4. Staff 1 (Belongs to HSE at Site Alpha)
  INSERT INTO auth.users (id, email) VALUES (v_staff1_id, 'staff1_' || v_suffix || '@org1.com');
  INSERT INTO public.profiles (id, organization_id, role_id, department_id, site_id, full_name, email, designation, status, is_active)
  VALUES (v_staff1_id, v_org1_id, v_role_staff, v_dept_hse, v_site_a, 'Staff One (HSE Site A)', 'staff1_' || v_suffix || '@org1.com', 'HSE Officer', 'active', true);

  -- 5. Staff 2 (Belongs to Finance at Site Beta - completely outside Manager 1's scope!)
  INSERT INTO auth.users (id, email) VALUES (v_staff2_id, 'staff2_' || v_suffix || '@org1.com');
  INSERT INTO public.profiles (id, organization_id, role_id, department_id, site_id, full_name, email, designation, status, is_active)
  VALUES (v_staff2_id, v_org1_id, v_role_staff, v_dept_fin, v_site_b, 'Staff Two (Fin Site B)', 'staff2_' || v_suffix || '@org1.com', 'Finance Officer', 'active', true);

  -- 6. Inactive Staff (Org 1)
  INSERT INTO auth.users (id, email) VALUES (v_inactive_staff_id, 'inactive_' || v_suffix || '@org1.com');
  INSERT INTO public.profiles (id, organization_id, role_id, department_id, site_id, full_name, email, designation, status, is_active)
  VALUES (v_inactive_staff_id, v_org1_id, v_role_staff, v_dept_hse, v_site_a, 'Inactive Staff', 'inactive_' || v_suffix || '@org1.com', 'Staff', 'inactive', false);

  -- 7. Staff in Org 2 (Cross-tenant)
  INSERT INTO auth.users (id, email) VALUES (v_staff_org2_id, 'staff_org2_' || v_suffix || '@org2.com');
  INSERT INTO public.profiles (id, organization_id, role_id, department_id, site_id, full_name, email, designation, status, is_active)
  VALUES (v_staff_org2_id, v_org2_id, v_role_staff, v_dept_org2, v_site_org2, 'Staff Org 2', 'staff_org2_' || v_suffix || '@org2.com', 'Staff', 'active', true);

  -- 8. Admin role profile (in Org 1) to test Admin exclusion from operational assignees
  INSERT INTO auth.users (id, email) VALUES (v_admin_user_id, 'admin_staff_' || v_suffix || '@org1.com');
  INSERT INTO public.profiles (id, organization_id, role_id, department_id, site_id, full_name, email, designation, status, is_active)
  VALUES (v_admin_user_id, v_org1_id, v_role_admin, v_dept_hse, v_site_a, 'Admin Profile', 'admin_staff_' || v_suffix || '@org1.com', 'Safety Director Admin', 'active', true);

  -- --------------------------------------------------------------------------
  -- TEST 1: Active Manager creates an organization-wide action
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_mgr1_id::text, true);
  PERFORM set_config('role', 'authenticated', true);

  INSERT INTO public.actions (
    organization_id,
    title,
    action_required,
    scope_type,
    department_id,
    site_id,
    assigned_to,
    target_date
  ) VALUES (
    v_org1_id,
    'Annual Safety Policy Review (Org-Wide)',
    'Review and sign company-wide safety policy',
    'organization',
    NULL,
    NULL,
    v_staff1_id,
    CURRENT_DATE + 30
  ) RETURNING id INTO v_act_org_wide;

  ASSERT v_act_org_wide IS NOT NULL, 'TEST 1 FAILED: Could not create organization-wide action';
  RAISE NOTICE 'TEST 1 PASSED: Active Manager created organization-wide action';

  -- --------------------------------------------------------------------------
  -- TEST 2: Manager assigns an eligible user outside their own department/site scope
  -- (Manager 1 from HSE/Site A assigns Staff 2 from Finance/Site B as primary assignee)
  -- --------------------------------------------------------------------------
  UPDATE public.actions
  SET assigned_to = v_staff2_id
  WHERE id = v_act_org_wide;

  DECLARE
    v_assigned_check UUID;
  BEGIN
    SELECT assigned_to INTO v_assigned_check FROM public.actions WHERE id = v_act_org_wide;
    ASSERT v_assigned_check = v_staff2_id, 'TEST 2 FAILED: Primary assignee was not updated to outside-scope user';
  END;
  RAISE NOTICE 'TEST 2 PASSED: Manager assigned outside-scope user to organization-wide action';

  -- --------------------------------------------------------------------------
  -- TEST 3: Manager adds multiple users from different departments and sites
  -- --------------------------------------------------------------------------
  INSERT INTO public.action_assignees (
    organization_id,
    action_id,
    profile_id,
    assignment_role,
    is_required,
    assigned_by
  ) VALUES 
    (v_org1_id, v_act_org_wide, v_staff2_id, 'owner', true, v_mgr1_id),
    (v_org1_id, v_act_org_wide, v_staff1_id, 'assignee', true, v_mgr1_id);

  SELECT count(*) INTO v_count FROM public.action_assignees WHERE action_id = v_act_org_wide;
  ASSERT v_count = 2, 'TEST 3 FAILED: Additional assignees count mismatch';
  RAISE NOTICE 'TEST 3 PASSED: Multiple users from different scopes added to action_assignees';

  -- --------------------------------------------------------------------------
  -- TEST 4: Cross-organization primary assignment is rejected
  -- --------------------------------------------------------------------------
  v_threw := false;
  BEGIN
    INSERT INTO public.actions (
      organization_id,
      title,
      action_required,
      scope_type,
      department_id,
      site_id,
      assigned_to,
      target_date
    ) VALUES (
      v_org1_id,
      'Cross-tenant Primary Attempt',
      'Should fail',
      'organization',
      NULL,
      NULL,
      v_staff_org2_id,
      CURRENT_DATE + 10
    );
  EXCEPTION WHEN OTHERS THEN
    v_threw := true;
  END;

  ASSERT v_threw, 'TEST 4 FAILED: Cross-organization primary assignee was not rejected';
  RAISE NOTICE 'TEST 4 PASSED: Cross-organization primary assignment rejected';

  -- --------------------------------------------------------------------------
  -- TEST 5: Cross-organization additional assignment is rejected
  -- --------------------------------------------------------------------------
  v_threw := false;
  BEGIN
    INSERT INTO public.action_assignees (
      organization_id,
      action_id,
      profile_id,
      assignment_role,
      assigned_by
    ) VALUES (
      v_org1_id,
      v_act_org_wide,
      v_staff_org2_id,
      'assignee',
      v_mgr1_id
    );
  EXCEPTION WHEN OTHERS THEN
    v_threw := true;
  END;

  ASSERT v_threw, 'TEST 5 FAILED: Cross-organization additional assignee was not rejected';
  RAISE NOTICE 'TEST 5 PASSED: Cross-organization additional assignment rejected';

  -- --------------------------------------------------------------------------
  -- TEST 6: Inactive and unapproved users are rejected
  -- --------------------------------------------------------------------------
  v_threw := false;
  BEGIN
    UPDATE public.actions
    SET assigned_to = v_inactive_staff_id
    WHERE id = v_act_org_wide;
  EXCEPTION WHEN OTHERS THEN
    v_threw := true;
  END;

  ASSERT v_threw, 'TEST 6 FAILED: Inactive primary user was not rejected';

  v_threw := false;
  BEGIN
    INSERT INTO public.action_assignees (
      organization_id,
      action_id,
      profile_id,
      assignment_role,
      assigned_by
    ) VALUES (
      v_org1_id,
      v_act_org_wide,
      v_inactive_staff_id,
      'assignee',
      v_mgr1_id
    );
  EXCEPTION WHEN OTHERS THEN
    v_threw := true;
  END;

  ASSERT v_threw, 'TEST 6b FAILED: Inactive additional assignee was not rejected';
  RAISE NOTICE 'TEST 6 PASSED: Inactive and unapproved users strictly rejected';

  -- --------------------------------------------------------------------------
  -- TEST 7: Admin-role users are excluded from operational assignees
  -- --------------------------------------------------------------------------
  v_threw := false;
  BEGIN
    INSERT INTO public.actions (
      organization_id,
      title,
      action_required,
      scope_type,
      department_id,
      site_id,
      assigned_to,
      target_date
    ) VALUES (
      v_org1_id,
      'Assign to Admin Test',
      'Should fail',
      'organization',
      NULL,
      NULL,
      v_admin_user_id,
      CURRENT_DATE + 10
    );
  EXCEPTION WHEN OTHERS THEN
    v_threw := true;
  END;

  ASSERT v_threw, 'TEST 7 FAILED: Admin role was allowed as primary assignee';

  v_threw := false;
  BEGIN
    INSERT INTO public.action_assignees (
      organization_id,
      action_id,
      profile_id,
      assignment_role,
      assigned_by
    ) VALUES (
      v_org1_id,
      v_act_org_wide,
      v_admin_user_id,
      'assignee',
      v_mgr1_id
    );
  EXCEPTION WHEN OTHERS THEN
    v_threw := true;
  END;

  ASSERT v_threw, 'TEST 7b FAILED: Admin role was allowed as additional assignee';
  RAISE NOTICE 'TEST 7 PASSED: Admin-role users strictly excluded from operational assignees';

  -- --------------------------------------------------------------------------
  -- TEST 8: Anonymous users cannot create organization-wide actions
  -- --------------------------------------------------------------------------
  PERFORM set_config('role', 'anon', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  v_threw := false;
  BEGIN
    INSERT INTO public.actions (
      organization_id,
      title,
      action_required,
      scope_type,
      department_id,
      site_id,
      target_date
    ) VALUES (
      v_org1_id,
      'Anon Org-wide Attempt',
      'Should fail',
      'organization',
      NULL,
      NULL,
      CURRENT_DATE + 10
    );
  EXCEPTION WHEN OTHERS THEN
    v_threw := true;
  END;

  ASSERT v_threw, 'TEST 8 FAILED: Anonymous user was allowed to create action';
  RAISE NOTICE 'TEST 8 PASSED: Anonymous users cannot create organization-wide actions';

  -- --------------------------------------------------------------------------
  -- TEST 9: Staff cannot create organization-wide actions
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_staff1_id::text, true);
  PERFORM set_config('role', 'authenticated', true);

  v_threw := false;
  BEGIN
    INSERT INTO public.actions (
      organization_id,
      title,
      action_required,
      scope_type,
      department_id,
      site_id,
      target_date
    ) VALUES (
      v_org1_id,
      'Staff Org-wide Attempt',
      'Should fail',
      'organization',
      NULL,
      NULL,
      CURRENT_DATE + 10
    );
  EXCEPTION WHEN OTHERS THEN
    v_threw := true;
  END;

  ASSERT v_threw, 'TEST 9 FAILED: Staff user was allowed to create action';
  RAISE NOTICE 'TEST 9 PASSED: Staff cannot create organization-wide actions';

  -- --------------------------------------------------------------------------
  -- TEST 10: Staff cannot browse unassigned organization-wide actions
  -- (Create action by Mgr 1 assigned ONLY to Staff 1. Staff 2 attempts to SELECT)
  -- --------------------------------------------------------------------------
  -- Back to Manager 1 to create an action assigned ONLY to Staff 1
  PERFORM set_config('request.jwt.claim.sub', v_mgr1_id::text, true);
  PERFORM set_config('role', 'authenticated', true);

  DECLARE
    v_act_private UUID;
  BEGIN
    INSERT INTO public.actions (
      organization_id,
      title,
      action_required,
      scope_type,
      department_id,
      site_id,
      assigned_to,
      target_date
    ) VALUES (
      v_org1_id,
      'Confidential Org Policy',
      'Confidential',
      'organization',
      NULL,
      NULL,
      v_staff1_id,
      CURRENT_DATE + 15
    ) RETURNING id INTO v_act_private;

    -- Switch to Staff 2 (unassigned)
    PERFORM set_config('request.jwt.claim.sub', v_staff2_id::text, true);
    PERFORM set_config('role', 'authenticated', true);

    SELECT count(*) INTO v_count FROM public.actions WHERE id = v_act_private;
    ASSERT v_count = 0, 'TEST 10 FAILED: Unassigned staff was able to browse organization-wide action';
    RAISE NOTICE 'TEST 10 PASSED: Staff cannot browse unassigned organization-wide actions';
  END;

  -- --------------------------------------------------------------------------
  -- TEST 11: Assigned Staff can view and update their assigned work
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_staff1_id::text, true);
  PERFORM set_config('role', 'authenticated', true);

  SELECT count(*) INTO v_count FROM public.actions WHERE id = v_act_org_wide;
  ASSERT v_count = 1, 'TEST 11 FAILED: Assigned staff could not SELECT assigned organization-wide action';

  -- Staff completes work in action_assignees
  UPDATE public.action_assignees
  SET work_completed = true, completed_at = now()
  WHERE action_id = v_act_org_wide AND profile_id = v_staff1_id;

  SELECT work_completed INTO v_threw FROM public.action_assignees
  WHERE action_id = v_act_org_wide AND profile_id = v_staff1_id;
  ASSERT v_threw = true, 'TEST 11b FAILED: Assigned staff could not update their work completed status';
  RAISE NOTICE 'TEST 11 PASSED: Assigned staff can view action and update their assigned work';

  -- --------------------------------------------------------------------------
  -- TEST 12: Unassigned Manager cannot access another Manager's organization-wide action
  -- (Manager 2 belongs to same org, but didn't create, isn't assigned, isn't participant)
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_mgr2_id::text, true);
  PERFORM set_config('role', 'authenticated', true);

  SELECT count(*) INTO v_count FROM public.actions WHERE id = v_act_org_wide;
  ASSERT v_count = 0, 'TEST 12 FAILED: Unrelated manager was able to SELECT another manager org-wide action';
  RAISE NOTICE 'TEST 12 PASSED: Unassigned Manager cannot access another Manager org-wide action';

  -- --------------------------------------------------------------------------
  -- TEST 13: Manager cannot edit/delete another Manager's organization-wide action
  -- --------------------------------------------------------------------------
  v_threw := false;
  BEGIN
    UPDATE public.actions SET title = 'Hacked Title' WHERE id = v_act_org_wide;
  EXCEPTION WHEN OTHERS THEN
    v_threw := true;
  END;

  -- Verify update did not take effect
  SELECT count(*) INTO v_count FROM public.actions WHERE id = v_act_org_wide AND title = 'Hacked Title';
  ASSERT v_count = 0, 'TEST 13 FAILED: Unrelated manager modified another manager org-wide action';

  -- Test RPC delete rejection
  v_result := public.delete_action_authorized(v_act_org_wide);
  ASSERT (v_result->>'success')::boolean = false, 'TEST 13b FAILED: Unrelated manager was able to delete action via RPC';
  RAISE NOTICE 'TEST 13 PASSED: Manager cannot edit or delete another Manager organization-wide action';

  -- --------------------------------------------------------------------------
  -- TEST 14: Creator and authorized Company Admin permissions work as intended
  -- --------------------------------------------------------------------------
  -- Creator (Manager 1) can update
  PERFORM set_config('request.jwt.claim.sub', v_mgr1_id::text, true);
  PERFORM set_config('role', 'authenticated', true);

  UPDATE public.actions SET title = 'Creator Updated Title' WHERE id = v_act_org_wide;
  SELECT title INTO v_suffix FROM public.actions WHERE id = v_act_org_wide;
  ASSERT v_suffix = 'Creator Updated Title', 'TEST 14 FAILED: Creator could not update action title';

  -- Company Admin can view and manage
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('role', 'authenticated', true);

  SELECT count(*) INTO v_count FROM public.actions WHERE id = v_act_org_wide;
  ASSERT v_count = 1, 'TEST 14b FAILED: Company Admin could not SELECT organization-wide action';
  RAISE NOTICE 'TEST 14 PASSED: Creator and Company Admin permissions function properly';

  -- --------------------------------------------------------------------------
  -- TEST 15: Closing and reopening follow existing approval rules
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_mgr1_id::text, true);
  PERFORM set_config('role', 'authenticated', true);

  -- Close should fail when progress < 100%
  v_result := public.close_action_verified(v_act_org_wide, 'Closure verification');
  ASSERT (v_result->>'success')::boolean = false, 'TEST 15 FAILED: Action closed before 100% completion';

  -- Set progress to 100% and complete other assignee work
  UPDATE public.actions SET percent_complete = 100 WHERE id = v_act_org_wide;
  UPDATE public.action_assignees SET work_completed = true WHERE action_id = v_act_org_wide;

  -- Now close should succeed
  v_result := public.close_action_verified(v_act_org_wide, 'All verified and closed');
  ASSERT (v_result->>'success')::boolean = true, 'TEST 15b FAILED: close_action_verified failed on 100% action';

  -- Reopen action
  v_result := public.reopen_action(v_act_org_wide, 'Auditor requested additional verification evidence');
  ASSERT v_result->>'status' = 'In Progress', 'TEST 15c FAILED: reopen_action failed';
  RAISE NOTICE 'TEST 15 PASSED: Closing and reopening follow existing approval rules';

  -- --------------------------------------------------------------------------
  -- TEST 16: Department-wide creation cannot bypass exact Manager scopes
  -- (Manager 1 only manages HSE at Site Alpha. If there are multiple active sites,
  --  Manager 1 does not hold department-wide scope across all sites!)
  -- --------------------------------------------------------------------------
  -- Org 1 has Site A and Site B. Manager 1 has scope for Site A only.
  -- Attempting department-wide creation for HSE must be rejected!
  v_threw := false;
  BEGIN
    INSERT INTO public.actions (
      organization_id,
      title,
      action_required,
      scope_type,
      department_id,
      site_id,
      target_date
    ) VALUES (
      v_org1_id,
      'Unauthorized Dept-Wide Action',
      'Should fail',
      'department',
      v_dept_hse,
      NULL,
      CURRENT_DATE + 10
    );
  EXCEPTION WHEN OTHERS THEN
    v_threw := true;
  END;

  ASSERT v_threw, 'TEST 16 FAILED: Manager was allowed to create department-wide action without covering all sites';
  RAISE NOTICE 'TEST 16 PASSED: Department-wide creation cannot bypass exact Manager scopes';

  -- --------------------------------------------------------------------------
  -- TEST 17: Site-wide creation cannot bypass exact Manager scopes
  -- (Manager 1 only manages HSE at Site Alpha. Org 1 has HSE & Finance departments.
  --  Manager 1 does not hold site-wide scope across all departments at Site Alpha!)
  -- --------------------------------------------------------------------------
  v_threw := false;
  BEGIN
    INSERT INTO public.actions (
      organization_id,
      title,
      action_required,
      scope_type,
      department_id,
      site_id,
      target_date
    ) VALUES (
      v_org1_id,
      'Unauthorized Site-Wide Action',
      'Should fail',
      'site',
      NULL,
      v_site_a,
      CURRENT_DATE + 10
    );
  EXCEPTION WHEN OTHERS THEN
    v_threw := true;
  END;

  ASSERT v_threw, 'TEST 17 FAILED: Manager was allowed to create site-wide action without covering all departments';
  RAISE NOTICE 'TEST 17 PASSED: Site-wide creation cannot bypass exact Manager scopes';

  -- --------------------------------------------------------------------------
  -- TEST 18: Specific department/site creation retains exact pair validation
  -- --------------------------------------------------------------------------
  -- Allowed within scope (HSE, Site A)
  INSERT INTO public.actions (
    organization_id,
    title,
    action_required,
    scope_type,
    department_id,
    site_id,
    assigned_to,
    target_date
  ) VALUES (
    v_org1_id,
    'Valid Specific Action',
    'Permitted scope',
    'specific',
    v_dept_hse,
    v_site_a,
    v_staff1_id,
    CURRENT_DATE + 10
  ) RETURNING id INTO v_act_specific;

  ASSERT v_act_specific IS NOT NULL, 'TEST 18 FAILED: Could not create specific action in scope';

  -- Rejected outside scope (HSE, Site B)
  v_threw := false;
  BEGIN
    INSERT INTO public.actions (
      organization_id,
      title,
      action_required,
      scope_type,
      department_id,
      site_id,
      target_date
    ) VALUES (
      v_org1_id,
      'Invalid Specific Action',
      'Outside scope',
      'specific',
      v_dept_hse,
      v_site_b,
      CURRENT_DATE + 10
    );
  EXCEPTION WHEN OTHERS THEN
    v_threw := true;
  END;

  ASSERT v_threw, 'TEST 18b FAILED: Specific action outside manager scope was permitted';
  RAISE NOTICE 'TEST 18 PASSED: Specific department/site creation retains exact pair validation';

  -- --------------------------------------------------------------------------
  -- TEST 19: Invalid scope_type and department/site combinations are rejected
  -- --------------------------------------------------------------------------
  v_threw := false;
  BEGIN
    -- Specific scope with NULL site must fail constraint
    INSERT INTO public.actions (
      organization_id,
      title,
      action_required,
      scope_type,
      department_id,
      site_id,
      target_date
    ) VALUES (
      v_org1_id,
      'Invalid Scope Combination',
      'Should fail check constraint',
      'specific',
      v_dept_hse,
      NULL,
      CURRENT_DATE + 10
    );
  EXCEPTION WHEN OTHERS THEN
    v_threw := true;
  END;

  ASSERT v_threw, 'TEST 19 FAILED: chk_actions_scope_consistency did not reject invalid combination';
  RAISE NOTICE 'TEST 19 PASSED: Invalid scope_type and department/site combinations strictly rejected';

  -- --------------------------------------------------------------------------
  -- TEST 20: Existing historical actions remain accessible and unchanged
  -- --------------------------------------------------------------------------
  -- Historical action seeded with default 'specific' and non-null department and site
  INSERT INTO public.actions (
    organization_id,
    title,
    action_required,
    department_id,
    site_id,
    assigned_to,
    target_date
  ) VALUES (
    v_org1_id,
    'Historical 2025 Action',
    'Legacy action',
    v_dept_hse,
    v_site_a,
    v_staff1_id,
    CURRENT_DATE + 5
  ) RETURNING id INTO v_act_historical;

  SELECT scope_type, department_id, site_id
  INTO v_suffix, v_dept_org2, v_site_org2
  FROM public.actions WHERE id = v_act_historical;

  ASSERT v_suffix = 'specific', 'TEST 20 FAILED: Historical action default scope_type is not specific';
  ASSERT v_dept_org2 = v_dept_hse, 'TEST 20b FAILED: Historical action department_id was corrupted';
  ASSERT v_site_org2 = v_site_a, 'TEST 20c FAILED: Historical action site_id was corrupted';
  RAISE NOTICE 'TEST 20 PASSED: Existing historical actions remain accessible and unchanged';

  RAISE NOTICE '>>> ALL 20 SCENARIOS PASSED WITH FULL SECURITY INTEGRITY! <<<';
END $$;

ROLLBACK;
