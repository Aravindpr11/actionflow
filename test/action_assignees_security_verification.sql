-- ============================================================================
-- Verification script: test/action_assignees_security_verification.sql
-- ============================================================================

DO $$
DECLARE
  v_org_a UUID := '00000000-0000-0000-0000-000000000001';
  v_org_b UUID := '00000000-0000-0000-0000-000000000002';
  v_role_staff UUID;
  v_role_manager UUID;
  v_dept_a UUID := gen_random_uuid();
  v_dept_b UUID := gen_random_uuid();
  v_site_a UUID := gen_random_uuid();
  v_site_b UUID := gen_random_uuid();

  v_manager UUID := gen_random_uuid();
  v_staff_a UUID := gen_random_uuid();
  v_staff_b UUID := gen_random_uuid();
  v_staff_inactive UUID := gen_random_uuid();
  v_staff_org_b UUID := gen_random_uuid();

  v_action_id UUID := gen_random_uuid();
  v_test_passed BOOLEAN;
BEGIN
  RAISE NOTICE '=== Starting Action Assignees Security Verification ===';

  -- Ensure organizations exist
  INSERT INTO public.organizations (id, name, code)
  VALUES 
    (v_org_a, 'Org Alpha', 'org-alpha'),
    (v_org_b, 'Org Beta', 'org-beta')
  ON CONFLICT (id) DO NOTHING;

  -- Ensure roles exist
  SELECT id INTO v_role_manager FROM public.roles WHERE code = 'manager' LIMIT 1;
  IF v_role_manager IS NULL THEN
    v_role_manager := gen_random_uuid();
    INSERT INTO public.roles (id, name, code) VALUES (v_role_manager, 'Manager', 'manager');
  END IF;

  SELECT id INTO v_role_staff FROM public.roles WHERE code = 'staff' LIMIT 1;
  IF v_role_staff IS NULL THEN
    v_role_staff := gen_random_uuid();
    INSERT INTO public.roles (id, name, code) VALUES (v_role_staff, 'Staff', 'staff');
  END IF;

  -- Departments and Sites for Org A
  INSERT INTO public.departments (id, organization_id, name, is_active, division)
  VALUES 
    (v_dept_a, v_org_a, 'HSE Alpha ' || v_dept_a::text, true, 'Operations'),
    (v_dept_b, v_org_a, 'Civil Alpha ' || v_dept_b::text, true, 'Operations')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.sites (id, organization_id, name, is_active)
  VALUES 
    (v_site_a, v_org_a, 'Plant A ' || v_site_a::text, true),
    (v_site_b, v_org_a, 'Plant B ' || v_site_b::text, true)
  ON CONFLICT DO NOTHING;

  -- Create auth users
  INSERT INTO auth.users (id, email) VALUES 
    (v_manager, 'mgr.bob.' || v_manager::text || '@alpha.com'),
    (v_staff_a, 'alice.' || v_staff_a::text || '@alpha.com'),
    (v_staff_b, 'brenda.' || v_staff_b::text || '@alpha.com'),
    (v_staff_inactive, 'inactive.' || v_staff_inactive::text || '@alpha.com'),
    (v_staff_org_b, 'beta.' || v_staff_org_b::text || '@beta.com')
  ON CONFLICT (id) DO NOTHING;

  -- Create profiles
  -- Manager in Org A (HSE Alpha, Plant A)
  INSERT INTO public.profiles (id, organization_id, role_id, full_name, email, is_active, status, department_id, site_id, designation)
  VALUES (v_manager, v_org_a, v_role_manager, 'Manager Bob', 'mgr.bob.' || v_manager::text || '@alpha.com', true, 'active', v_dept_a, v_site_a, 'HSE Manager');

  -- Staff A in Org A (HSE Alpha, Plant A)
  INSERT INTO public.profiles (id, organization_id, role_id, full_name, email, is_active, status, department_id, site_id, designation)
  VALUES (v_staff_a, v_org_a, v_role_staff, 'Staff Alice', 'alice.' || v_staff_a::text || '@alpha.com', true, 'active', v_dept_a, v_site_a, 'HSE Officer');

  -- Staff B in Org A (Civil Alpha, Plant B - Cross-Dept and Cross-Site!)
  INSERT INTO public.profiles (id, organization_id, role_id, full_name, email, is_active, status, department_id, site_id, designation)
  VALUES (v_staff_b, v_org_a, v_role_staff, 'Staff Brenda', 'brenda.' || v_staff_b::text || '@alpha.com', true, 'active', v_dept_b, v_site_b, 'Civil Inspector');

  -- Inactive Staff in Org A
  INSERT INTO public.profiles (id, organization_id, role_id, full_name, email, is_active, status, department_id, site_id, designation)
  VALUES (v_staff_inactive, v_org_a, v_role_staff, 'Staff Inactive', 'inactive.' || v_staff_inactive::text || '@alpha.com', false, 'inactive', v_dept_a, v_site_a, 'Former Staff');

  -- Staff in Org B (Cross-organization!)
  INSERT INTO public.profiles (id, organization_id, role_id, full_name, email, is_active, status, designation)
  VALUES (v_staff_org_b, v_org_b, v_role_staff, 'Staff Beta', 'beta.' || v_staff_org_b::text || '@beta.com', true, 'active', 'Beta Staff');

  -- Manager scope for Manager Bob
  INSERT INTO public.manager_scopes (id, manager_profile_id, department_id, site_id)
  VALUES (gen_random_uuid(), v_manager, v_dept_a, v_site_a);

  -- Set auth context to Manager Bob
  PERFORM set_config('request.jwt.claim.sub', v_manager::text, true);

  -- Create action in Org A, Dept A, Site A, Primary Assignee Staff A
  INSERT INTO public.actions (
    id, organization_id, title, action_required, department_id, site_id, assigned_to, created_by, status, target_date
  ) VALUES (
    v_action_id, v_org_a, 'Safety Inspection', 'Check perimeter', v_dept_a, v_site_a, v_staff_a, v_manager, 'Open', CURRENT_DATE + interval '7 days'
  );

  -- TEST 1: Insert primary assignee into action_assignees -> Should SUCCEED
  BEGIN
    INSERT INTO public.action_assignees (
      organization_id, action_id, profile_id, assignment_role, assigned_by
    ) VALUES (
      v_org_a, v_action_id, v_staff_a, 'owner', v_manager
    );
    RAISE NOTICE 'TEST 1 PASSED: Primary assignee inserted successfully.';
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'TEST 1 FAILED: Expected primary assignee insert to succeed, got %', SQLERRM;
  END;

  -- TEST 2: Insert additional user from DIFFERENT department and DIFFERENT site (Staff Brenda) -> Should SUCCEED!
  BEGIN
    INSERT INTO public.action_assignees (
      organization_id, action_id, profile_id, assignment_role, assigned_by
    ) VALUES (
      v_org_a, v_action_id, v_staff_b, 'assignee', v_manager
    );
    RAISE NOTICE 'TEST 2 PASSED: Cross-department/cross-site additional assignee inserted successfully.';
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'TEST 2 FAILED: Expected cross-dept assignee to succeed, got %', SQLERRM;
  END;

  -- TEST 3: Insert INACTIVE user -> Should FAIL with validation error
  v_test_passed := FALSE;
  BEGIN
    INSERT INTO public.action_assignees (
      organization_id, action_id, profile_id, assignment_role, assigned_by
    ) VALUES (
      v_org_a, v_action_id, v_staff_inactive, 'assignee', v_manager
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%inactive or not approved%' THEN
      v_test_passed := TRUE;
      RAISE NOTICE 'TEST 3 PASSED: Inactive user rejected: %', SQLERRM;
    ELSE
      RAISE EXCEPTION 'TEST 3 FAILED: Unexpected error message: %', SQLERRM;
    END IF;
  END;
  IF NOT v_test_passed THEN
    RAISE EXCEPTION 'TEST 3 FAILED: Inactive user insert was NOT rejected!';
  END IF;

  -- TEST 4: Insert CROSS-ORGANIZATION user (Staff Org B) -> Should FAIL with security violation
  v_test_passed := FALSE;
  BEGIN
    INSERT INTO public.action_assignees (
      organization_id, action_id, profile_id, assignment_role, assigned_by
    ) VALUES (
      v_org_a, v_action_id, v_staff_org_b, 'assignee', v_manager
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%does not belong to this organization%' THEN
      v_test_passed := TRUE;
      RAISE NOTICE 'TEST 4 PASSED: Cross-organization user rejected: %', SQLERRM;
    ELSE
      RAISE EXCEPTION 'TEST 4 FAILED: Unexpected error message: %', SQLERRM;
    END IF;
  END;
  IF NOT v_test_passed THEN
    RAISE EXCEPTION 'TEST 4 FAILED: Cross-organization user insert was NOT rejected!';
  END IF;

  -- TEST 5: Duplicate assignee (Staff Brenda again) -> Should FAIL on unique constraint uq_action_assignee
  v_test_passed := FALSE;
  BEGIN
    INSERT INTO public.action_assignees (
      organization_id, action_id, profile_id, assignment_role, assigned_by
    ) VALUES (
      v_org_a, v_action_id, v_staff_b, 'assignee', v_manager
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%duplicate key%' OR SQLERRM LIKE '%uq_action_assignee%' THEN
      v_test_passed := TRUE;
      RAISE NOTICE 'TEST 5 PASSED: Duplicate assignee prevented by unique constraint: %', SQLERRM;
    ELSE
      RAISE EXCEPTION 'TEST 5 FAILED: Unexpected error message: %', SQLERRM;
    END IF;
  END;
  IF NOT v_test_passed THEN
    RAISE EXCEPTION 'TEST 5 FAILED: Duplicate assignee was NOT rejected!';
  END IF;

  -- TEST 6: Primary assignee in actions table STILL enforces manager scope
  v_test_passed := FALSE;
  BEGIN
    -- Try to create action with Staff Brenda (Civil Alpha, Plant B) as PRIMARY assignee
    -- Manager Bob only has scope for HSE Alpha, Plant A!
    INSERT INTO public.actions (
      id, organization_id, title, action_required, department_id, site_id, assigned_to, created_by, status, target_date
    ) VALUES (
      gen_random_uuid(), v_org_a, 'Out of Scope Primary', 'Check', v_dept_a, v_site_a, v_staff_b, v_manager, 'Open', CURRENT_DATE + interval '7 days'
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%outside manager permitted scope%' THEN
      v_test_passed := TRUE;
      RAISE NOTICE 'TEST 6 PASSED: Primary assignee remains strictly scoped to manager permitted scopes: %', SQLERRM;
    ELSE
      RAISE EXCEPTION 'TEST 6 FAILED: Unexpected error message: %', SQLERRM;
    END IF;
  END;
  IF NOT v_test_passed THEN
    RAISE EXCEPTION 'TEST 6 FAILED: Primary assignee out-of-scope was NOT rejected!';
  END IF;

  RAISE NOTICE '=== ALL 6/6 ACTION ASSIGNEES SECURITY TESTS PASSED! ===';
END $$;
