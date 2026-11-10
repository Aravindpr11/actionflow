-- ============================================================================
-- Integration Test: Staff Action Creation, Register Isolation & Department Manager Verification
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_org_id UUID := '00000000-0000-0000-0000-000000000001';
  v_staff_a UUID := '9a78ceaa-cc3d-47a2-b1d3-e41d5e90a868'; -- alice@alpha.com (staff in Dept A, site 1)
  v_dept_id UUID := 'd7372e89-b1a7-4fe1-9e3b-c4daae804198';
  v_site_id UUID := '046686d0-33a0-4764-bcc0-2e439c7dfd36';
  v_dept_mgr UUID := '5ea141b5-5737-4053-a92f-e9450e58d5a8'; -- mgr.bob@alpha.com (manager in Dept A)
  v_other_dept_staff UUID := '8dceb191-062e-427a-a14d-4cafef17e7b1'; -- brenda@alpha.com (staff in Dept B)
  v_other_org_staff UUID := '822b3e14-f290-4857-9f84-aec4043d2ac8';  -- beta@beta.com (diff org)
  v_admin_id UUID := 'a7f0b85c-aed5-439e-8dac-083b3f0e7d15';          -- admin
  v_other_site_id UUID := '7c02b698-dc46-4a94-b80e-f486419e941a';
  v_staff_b UUID := gen_random_uuid();                                -- staff B in Dept A, diff site
  v_staff_c UUID := gen_random_uuid();                                -- staff C in Dept A, same site
  v_other_mgr UUID := gen_random_uuid();                              -- manager in Dept B
  v_other_dept_id UUID := 'd6d0524c-c6ee-4996-a104-ddeba6b72f31';    -- Dept B
  v_role_staff UUID;
  v_role_mgr UUID;
  v_action_self UUID;
  v_action_to_b UUID;
  v_action_to_mgr UUID;
  v_action_mgr_to_a UUID;
  v_action_b_to_a UUID;
  v_action_mgr_to_c UUID;
  v_err_caught BOOLEAN;
  v_err_msg TEXT;
  v_cnt INTEGER;
  v_initial_assigned_cnt INTEGER := 0;
  v_initial_created_cnt INTEGER := 0;
  v_rec RECORD;
  v_mgr_found BOOLEAN;
  v_other_mgr_found BOOLEAN;
  v_admin_found BOOLEAN;
BEGIN
  SELECT id INTO v_role_staff FROM public.roles WHERE code = 'staff' LIMIT 1;
  SELECT id INTO v_role_mgr FROM public.roles WHERE code = 'manager' LIMIT 1;

  -- 1. Create Staff B in Dept A (different site)
  INSERT INTO auth.users (id, email)
  VALUES (v_staff_b, 'staff_b_colleague@alpha.com')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.profiles (
    id, email, full_name, role_id, organization_id, department_id, site_id, is_active, status, designation
  ) VALUES (
    v_staff_b, 'staff_b_colleague@alpha.com', 'Staff B Colleague',
    v_role_staff, v_org_id, v_dept_id, v_other_site_id, true, 'active', 'HSE Technician'
  ) ON CONFLICT (id) DO UPDATE SET department_id = v_dept_id, site_id = v_other_site_id, is_active = true, status = 'active';

  -- 2. Create Staff C in Dept A (same site as Staff A and Mgr Bob)
  INSERT INTO auth.users (id, email)
  VALUES (v_staff_c, 'staff_c_colleague@alpha.com')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.profiles (
    id, email, full_name, role_id, organization_id, department_id, site_id, is_active, status, designation
  ) VALUES (
    v_staff_c, 'staff_c_colleague@alpha.com', 'Staff C Colleague',
    v_role_staff, v_org_id, v_dept_id, v_site_id, true, 'active', 'Safety Officer'
  ) ON CONFLICT (id) DO UPDATE SET department_id = v_dept_id, site_id = v_site_id, is_active = true, status = 'active';

  -- 3. Create Manager in Dept B (other department)
  INSERT INTO auth.users (id, email)
  VALUES (v_other_mgr, 'mgr_other_dept@alpha.com')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.profiles (
    id, email, full_name, role_id, organization_id, department_id, site_id, is_active, status, designation
  ) VALUES (
    v_other_mgr, 'mgr_other_dept@alpha.com', 'Manager Other Dept',
    v_role_mgr, v_org_id, v_other_dept_id, v_other_site_id, true, 'active', 'Operations Manager'
  ) ON CONFLICT (id) DO UPDATE SET department_id = v_other_dept_id, is_active = true, status = 'active';

  -- Record initial baseline counts for Staff A
  SELECT COUNT(*) INTO v_initial_assigned_cnt FROM public.actions WHERE assigned_to = v_staff_a;
  SELECT COUNT(*) INTO v_initial_created_cnt FROM public.actions WHERE created_by = v_staff_a;

  RAISE NOTICE '=== SETUP COMPLETED (Initial Assigned: %, Initial Created: %) ===', v_initial_assigned_cnt, v_initial_created_cnt;

  -- Authenticate as Staff A
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_staff_a::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  -- TEST 1: Staff A creates action assigned to self -> SUCCESS
  INSERT INTO public.actions (
    title, description, action_required, priority, status, percent_complete,
    target_date, scope_type, department_id, site_id, organization_id, created_by, assigned_to
  ) VALUES (
    'Staff A: Self Assigned', 'Desc 1', 'Req 1', 'Medium', 'Open', 0,
    CURRENT_DATE + 7, 'specific', v_dept_id, v_site_id, v_org_id, v_staff_a, v_staff_a
  ) RETURNING id INTO v_action_self;
  ASSERT v_action_self IS NOT NULL, 'Test 1 Failed';
  RAISE NOTICE 'TEST 1 PASSED: Staff A created action assigned to self.';

  -- TEST 2: Staff A creates action assigned to Staff B (colleague in same dept, diff site) -> SUCCESS
  INSERT INTO public.actions (
    title, description, action_required, priority, status, percent_complete,
    target_date, scope_type, department_id, site_id, organization_id, created_by, assigned_to
  ) VALUES (
    'Staff A: Assigned to Staff B', 'Desc 2', 'Req 2', 'High', 'Open', 0,
    CURRENT_DATE + 7, 'specific', v_dept_id, v_site_id, v_org_id, v_staff_a, v_staff_b
  ) RETURNING id INTO v_action_to_b;
  ASSERT v_action_to_b IS NOT NULL, 'Test 2 Failed';
  RAISE NOTICE 'TEST 2 PASSED: Staff A created action assigned to Staff B in same department.';

  -- TEST 3: Staff A creates action assigned to Department Manager -> SUCCESS
  INSERT INTO public.actions (
    title, description, action_required, priority, status, percent_complete,
    target_date, scope_type, department_id, site_id, organization_id, created_by, assigned_to
  ) VALUES (
    'Staff A: Assigned to Dept Manager', 'Desc 3', 'Req 3', 'Critical', 'Open', 0,
    CURRENT_DATE + 7, 'specific', v_dept_id, v_site_id, v_org_id, v_staff_a, v_dept_mgr
  ) RETURNING id INTO v_action_to_mgr;
  ASSERT v_action_to_mgr IS NOT NULL, 'Test 3 Failed';
  RAISE NOTICE 'TEST 3 PASSED: Staff A created action assigned to Dept Manager.';

  -- TEST 4: Cross-department staff assignment -> MUST BE REJECTED
  v_err_caught := false;
  BEGIN
    INSERT INTO public.actions (
      title, description, action_required, priority, status, percent_complete,
      target_date, scope_type, department_id, site_id, organization_id, created_by, assigned_to
    ) VALUES (
      'Staff A: Cross-dept staff', 'Desc', 'Req', 'Medium', 'Open', 0,
      CURRENT_DATE + 7, 'specific', v_dept_id, v_site_id, v_org_id, v_staff_a, v_other_dept_staff
    );
  EXCEPTION WHEN others THEN
    v_err_caught := true;
    v_err_msg := SQLERRM;
  END;
  ASSERT v_err_caught = true AND v_err_msg LIKE '%ActionFlow Security Violation: Staff can only assign actions to themselves, or active staff or managers in their department.%',
    'Test 4 Failed: Expected Staff assignment violation error but got: ' || COALESCE(v_err_msg, 'none');
  RAISE NOTICE 'TEST 4 PASSED: Cross-department staff assignment correctly rejected.';

  -- TEST 5: Cross-department manager assignment -> MUST BE REJECTED
  v_err_caught := false;
  BEGIN
    INSERT INTO public.actions (
      title, description, action_required, priority, status, percent_complete,
      target_date, scope_type, department_id, site_id, organization_id, created_by, assigned_to
    ) VALUES (
      'Staff A: Cross-dept manager', 'Desc', 'Req', 'Medium', 'Open', 0,
      CURRENT_DATE + 7, 'specific', v_dept_id, v_site_id, v_org_id, v_staff_a, v_other_mgr
    );
  EXCEPTION WHEN others THEN
    v_err_caught := true;
    v_err_msg := SQLERRM;
  END;
  ASSERT v_err_caught = true AND v_err_msg LIKE '%ActionFlow Security Violation: Staff can only assign actions to themselves, or active staff or managers in their department.%',
    'Test 5 Failed: Expected Staff assignment violation error but got: ' || COALESCE(v_err_msg, 'none');
  RAISE NOTICE 'TEST 5 PASSED: Cross-department manager assignment correctly rejected.';

  -- TEST 6: Admin assignee -> MUST BE REJECTED
  v_err_caught := false;
  BEGIN
    INSERT INTO public.actions (
      title, description, action_required, priority, status, percent_complete,
      target_date, scope_type, department_id, site_id, organization_id, created_by, assigned_to
    ) VALUES (
      'Staff A: Admin assignee', 'Desc', 'Req', 'Medium', 'Open', 0,
      CURRENT_DATE + 7, 'specific', v_dept_id, v_site_id, v_org_id, v_staff_a, v_admin_id
    );
  EXCEPTION WHEN others THEN
    v_err_caught := true;
    v_err_msg := SQLERRM;
  END;
  ASSERT v_err_caught = true AND v_err_msg LIKE '%Admin-role users are excluded from operational assignees%',
    'Test 6 Failed: Expected Admin assignee exclusion error but got: ' || COALESCE(v_err_msg, 'none');
  RAISE NOTICE 'TEST 6 PASSED: Admin assignee correctly rejected.';

  -- TEST 7: Cross-organization action -> MUST BE REJECTED
  v_err_caught := false;
  BEGIN
    INSERT INTO public.actions (
      title, description, action_required, priority, status, percent_complete,
      target_date, scope_type, department_id, site_id, organization_id, created_by, assigned_to
    ) VALUES (
      'Staff A: Cross-Org', 'Desc', 'Req', 'Medium', 'Open', 0,
      CURRENT_DATE + 7, 'specific', v_dept_id, v_site_id, '00000000-0000-0000-0000-000000000002', v_staff_a, v_staff_a
    );
  EXCEPTION WHEN others THEN
    v_err_caught := true;
    v_err_msg := SQLERRM;
  END;
  ASSERT v_err_caught = true, 'Test 7 Failed';
  RAISE NOTICE 'TEST 7 PASSED: Cross-organization action correctly rejected.';

  -- TEST 8: Organization-wide scope for Staff -> MUST BE REJECTED
  v_err_caught := false;
  BEGIN
    INSERT INTO public.actions (
      title, description, action_required, priority, status, percent_complete,
      target_date, scope_type, department_id, site_id, organization_id, created_by, assigned_to
    ) VALUES (
      'Staff A: Org scope', 'Desc', 'Req', 'Medium', 'Open', 0,
      CURRENT_DATE + 7, 'organization', NULL, NULL, v_org_id, v_staff_a, v_staff_a
    );
  EXCEPTION WHEN others THEN
    v_err_caught := true;
    v_err_msg := SQLERRM;
  END;
  ASSERT v_err_caught = true, 'Test 8 Failed';
  RAISE NOTICE 'TEST 8 PASSED: Organization-wide scope correctly rejected for Staff.';

  -- TEST 9: Unauthorized site for Staff -> MUST BE REJECTED
  v_err_caught := false;
  BEGIN
    INSERT INTO public.actions (
      title, description, action_required, priority, status, percent_complete,
      target_date, scope_type, department_id, site_id, organization_id, created_by, assigned_to
    ) VALUES (
      'Staff A: Unauthorized site', 'Desc', 'Req', 'Medium', 'Open', 0,
      CURRENT_DATE + 7, 'specific', v_dept_id, v_other_site_id, v_org_id, v_staff_a, v_staff_a
    );
  EXCEPTION WHEN others THEN
    v_err_caught := true;
    v_err_msg := SQLERRM;
  END;
  ASSERT v_err_caught = true, 'Test 9 Failed';
  RAISE NOTICE 'TEST 9 PASSED: Unauthorized site correctly rejected for Staff.';

  -- Authenticate as Department Manager to create Manager-to-Staff actions
  PERFORM set_config('request.jwt.claim.sub', v_dept_mgr::text, true);

  -- TEST 10: Manager creates action assigned to Staff A -> SUCCESS
  INSERT INTO public.actions (
    title, description, action_required, priority, status, percent_complete,
    target_date, scope_type, department_id, site_id, organization_id, created_by, assigned_to
  ) VALUES (
    'Manager: Assigned to Staff A', 'Desc M1', 'Req M1', 'High', 'Open', 0,
    CURRENT_DATE + 7, 'specific', v_dept_id, v_site_id, v_org_id, v_dept_mgr, v_staff_a
  ) RETURNING id INTO v_action_mgr_to_a;
  ASSERT v_action_mgr_to_a IS NOT NULL, 'Test 10 Failed';
  RAISE NOTICE 'TEST 10 PASSED: Manager created action assigned to Staff A.';

  -- TEST 10b: Manager creates action assigned to Staff C (same dept & site) -> SUCCESS
  INSERT INTO public.actions (
    title, description, action_required, priority, status, percent_complete,
    target_date, scope_type, department_id, site_id, organization_id, created_by, assigned_to
  ) VALUES (
    'Manager: Assigned to Staff C', 'Desc M2', 'Req M2', 'Medium', 'Open', 0,
    CURRENT_DATE + 7, 'specific', v_dept_id, v_site_id, v_org_id, v_dept_mgr, v_staff_c
  ) RETURNING id INTO v_action_mgr_to_c;
  ASSERT v_action_mgr_to_c IS NOT NULL, 'Test 10b Failed';
  RAISE NOTICE 'TEST 10b PASSED: Manager created action assigned to Staff C.';

  -- Authenticate as Staff B to create Staff B to Staff A action
  PERFORM set_config('request.jwt.claim.sub', v_staff_b::text, true);

  -- Staff B has site v_other_site_id
  INSERT INTO public.actions (
    title, description, action_required, priority, status, percent_complete,
    target_date, scope_type, department_id, site_id, organization_id, created_by, assigned_to
  ) VALUES (
    'Staff B: Assigned to Staff A', 'Desc B1', 'Req B1', 'Low', 'Open', 0,
    CURRENT_DATE + 7, 'specific', v_dept_id, v_other_site_id, v_org_id, v_staff_b, v_staff_a
  ) RETURNING id INTO v_action_b_to_a;
  ASSERT v_action_b_to_a IS NOT NULL, 'Test 11 Failed';
  RAISE NOTICE 'TEST 11 PASSED: Staff B created action assigned to Staff A.';

  -- Authenticate back as Staff A for Action Register vs My Actions verification
  PERFORM set_config('request.jwt.claim.sub', v_staff_a::text, true);

  -- TEST 12: Staff Action Register Query: created_by = v_staff_a
  -- Must return v_action_self, v_action_to_b, v_action_to_mgr (all 3 actions created by Staff A)
  -- Must NOT return v_action_mgr_to_a, v_action_b_to_a, v_action_mgr_to_c
  SELECT COUNT(*) INTO v_cnt FROM public.actions
  WHERE organization_id = v_org_id AND created_by = v_staff_a;
  ASSERT v_cnt = v_initial_created_cnt + 3, 'Test 12 Failed: Expected ' || (v_initial_created_cnt + 3) || ' actions in Staff A Register, got ' || v_cnt;

  SELECT COUNT(*) INTO v_cnt FROM public.actions
  WHERE id = v_action_to_b AND created_by = v_staff_a;
  ASSERT v_cnt = 1, 'Test 12b Failed: Staff A to Staff B action should be in Register';

  SELECT COUNT(*) INTO v_cnt FROM public.actions
  WHERE id = v_action_mgr_to_a AND created_by = v_staff_a;
  ASSERT v_cnt = 0, 'Test 12c Failed: Manager-created action must NOT be in Staff A Register';

  SELECT COUNT(*) INTO v_cnt FROM public.actions
  WHERE id = v_action_b_to_a AND created_by = v_staff_a;
  ASSERT v_cnt = 0, 'Test 12d Failed: Staff B-created action must NOT be in Staff A Register';
  RAISE NOTICE 'TEST 12 PASSED: Staff Action Register strictly isolates created actions.';

  -- TEST 13: Staff My Actions Query: assigned_to = v_staff_a (or secondary in action_assignees)
  -- Must return v_action_self, v_action_mgr_to_a, v_action_b_to_a (all 3 actions assigned to Staff A)
  -- Must NOT return v_action_to_b (assigned to B), v_action_to_mgr (assigned to Mgr), v_action_mgr_to_c
  SELECT COUNT(*) INTO v_cnt FROM public.actions
  WHERE organization_id = v_org_id AND assigned_to = v_staff_a;
  ASSERT v_cnt = v_initial_assigned_cnt + 3, 'Test 13 Failed: Expected ' || (v_initial_assigned_cnt + 3) || ' assigned actions in Staff A My Actions, got ' || v_cnt;

  SELECT COUNT(*) INTO v_cnt FROM public.actions
  WHERE id = v_action_to_b AND assigned_to = v_staff_a;
  ASSERT v_cnt = 0, 'Test 13b Failed: Staff A to Staff B action must NOT be in Staff A My Actions';

  SELECT COUNT(*) INTO v_cnt FROM public.actions
  WHERE id = v_action_to_mgr AND assigned_to = v_staff_a;
  ASSERT v_cnt = 0, 'Test 13c Failed: Staff A to Mgr action must NOT be in Staff A My Actions';

  SELECT COUNT(*) INTO v_cnt FROM public.actions
  WHERE id = v_action_mgr_to_c AND assigned_to = v_staff_a;
  ASSERT v_cnt = 0, 'Test 13d Failed: Action assigned to other must NOT appear in Staff A My Actions';
  RAISE NOTICE 'TEST 13 PASSED: Staff My Actions strictly isolates assigned actions.';

  -- TEST 14: Department Manager Resolution via get_department_managers RPC
  v_mgr_found := false;
  v_other_mgr_found := false;
  v_admin_found := false;
  FOR v_rec IN SELECT * FROM public.get_department_managers(v_dept_id) LOOP
    IF v_rec.manager_id = v_dept_mgr THEN
      v_mgr_found := true;
    END IF;
    IF v_rec.manager_id = v_other_mgr THEN
      v_other_mgr_found := true;
    END IF;
    IF v_rec.manager_id = v_admin_id THEN
      v_admin_found := true;
    END IF;
  END LOOP;

  ASSERT v_mgr_found = true, 'Test 14 Failed: Eligible Department Manager Bob was not returned by RPC';
  ASSERT v_other_mgr_found = false, 'Test 14 Failed: Other department Manager was incorrectly returned';
  ASSERT v_admin_found = false, 'Test 14 Failed: Administrator was incorrectly returned';
  RAISE NOTICE 'TEST 14 PASSED: get_department_managers correctly resolves Dept Manager and excludes other depts/admin.';

  RAISE NOTICE '=== ALL 14 LOCAL DATABASE TESTS PASSED WITH 100%% SECURITY COMPLIANCE ===';
END $$;

ROLLBACK;
