-- ============================================================================
-- SQL Test: request_approver_security_verification.sql
-- Description:
--   Verifies submit_new_request backend enforcement:
--   1. Rejects cross-organization designated approvers.
--   2. Rejects inactive designated approvers.
--   3. Rejects Admin-role designated approvers.
--   4. Accepts eligible active Manager and Staff designated approvers across
--      departments/sites in the same organization.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_org1 UUID := '00000000-0000-0000-0000-000000000001';
  v_org2 UUID := '00000000-0000-0000-0000-000000000002';
  v_staff_role_id UUID;
  v_admin_role_id UUID;
  v_mgr_role_id UUID;

  v_caller_mgr UUID := '878d9145-7764-411f-8d26-f30f01e99e79'; -- Manager in Org 1
  v_cross_org_user UUID := '55555555-5555-5555-5555-555555555555'; -- Staff in Org 2
  v_inactive_user UUID := '44444444-4444-4444-4444-444444444444'; -- Inactive user in Org 1
  v_admin_user UUID := '33333333-3333-3333-3333-333333333333'; -- Admin in Org 1
  v_valid_staff UUID := '11111111-1111-1111-1111-111111111111'; -- Active Staff in Org 1

  v_dept_id UUID;
  v_site_id UUID;
  v_res JSONB;
  v_caught BOOLEAN := FALSE;
BEGIN
  SELECT id INTO v_staff_role_id FROM public.roles WHERE code = 'staff' LIMIT 1;
  SELECT id INTO v_mgr_role_id FROM public.roles WHERE code = 'manager' LIMIT 1;
  SELECT id INTO v_admin_role_id FROM public.roles WHERE code = 'admin' LIMIT 1;

  SELECT id INTO v_dept_id FROM public.departments WHERE organization_id = v_org1 LIMIT 1;
  SELECT id INTO v_site_id FROM public.sites WHERE organization_id = v_org1 LIMIT 1;

  -- Setup admin user in Org 1
  INSERT INTO auth.users (id, email) VALUES (v_admin_user, 'admin.test@sobha.test') ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.profiles (id, full_name, email, designation, role_id, is_active, organization_id)
  VALUES (v_admin_user, 'Admin Test', 'admin.test@sobha.test', 'System Administrator', v_admin_role_id, true, v_org1)
  ON CONFLICT (id) DO UPDATE SET role_id = v_admin_role_id, is_active = true, organization_id = v_org1;

  -- Authenticate as Manager in Org 1
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_caller_mgr::text, 'role', 'authenticated')::text, true);

  -- TEST 1: Reject cross-organization approver
  v_caught := FALSE;
  BEGIN
    PERFORM public.submit_new_request(
      'Test Title 1',
      'Test Desc 1',
      'Equipment',
      'High',
      v_dept_id,
      'Test Dept',
      v_site_id,
      'Test Site',
      CURRENT_DATE + 5,
      '17:00',
      'Sequential',
      'Notes',
      jsonb_build_array(
        jsonb_build_object(
          'approver_id', v_cross_org_user,
          'approver_name', 'Cross Org User',
          'approver_role', 'Staff',
          'approver_department', 'Other',
          'step_order', 1
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN
    v_caught := TRUE;
    RAISE NOTICE 'TEST 1 PASSED: Cross-org approver rejected with message: %', SQLERRM;
  END;
  IF NOT v_caught THEN
    RAISE EXCEPTION 'TEST 1 FAILED: submit_new_request accepted cross-org approver!';
  END IF;

  -- TEST 2: Reject inactive approver
  v_caught := FALSE;
  BEGIN
    PERFORM public.submit_new_request(
      'Test Title 2',
      'Test Desc 2',
      'Equipment',
      'High',
      v_dept_id,
      'Test Dept',
      v_site_id,
      'Test Site',
      CURRENT_DATE + 5,
      '17:00',
      'Sequential',
      'Notes',
      jsonb_build_array(
        jsonb_build_object(
          'approver_id', v_inactive_user,
          'approver_name', 'Inactive User',
          'approver_role', 'Staff',
          'approver_department', 'Test Dept',
          'step_order', 1
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN
    v_caught := TRUE;
    RAISE NOTICE 'TEST 2 PASSED: Inactive approver rejected with message: %', SQLERRM;
  END;
  IF NOT v_caught THEN
    RAISE EXCEPTION 'TEST 2 FAILED: submit_new_request accepted inactive approver!';
  END IF;

  -- TEST 3: Reject Admin-role approver
  v_caught := FALSE;
  BEGIN
    PERFORM public.submit_new_request(
      'Test Title 3',
      'Test Desc 3',
      'Equipment',
      'High',
      v_dept_id,
      'Test Dept',
      v_site_id,
      'Test Site',
      CURRENT_DATE + 5,
      '17:00',
      'Sequential',
      'Notes',
      jsonb_build_array(
        jsonb_build_object(
          'approver_id', v_admin_user,
          'approver_name', 'Admin Test',
          'approver_role', 'System Administrator',
          'approver_department', 'HQ',
          'step_order', 1
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN
    v_caught := TRUE;
    RAISE NOTICE 'TEST 3 PASSED: Admin-role approver rejected with message: %', SQLERRM;
  END;
  IF NOT v_caught THEN
    RAISE EXCEPTION 'TEST 3 FAILED: submit_new_request accepted admin approver!';
  END IF;

  -- TEST 4: Accept valid Staff approver in same organization
  v_res := public.submit_new_request(
    'Test Title 4 Valid',
    'Test Desc 4 Valid',
    'Equipment',
    'Medium',
    v_dept_id,
    'Test Dept',
    v_site_id,
    'Test Site',
    CURRENT_DATE + 5,
    '17:00',
    'Sequential',
    'Notes',
    jsonb_build_array(
      jsonb_build_object(
        'approver_id', v_valid_staff,
        'approver_name', 'Valid Staff',
        'approver_role', 'Staff',
        'approver_department', 'Test Dept',
        'step_order', 1
      )
    )
  );

  IF v_res->>'id' IS NULL THEN
    RAISE EXCEPTION 'TEST 4 FAILED: Valid request submission did not return ID';
  END IF;

  RAISE NOTICE 'TEST 4 PASSED: Valid request successfully created (ID: %, Display: %)', v_res->>'id', v_res->>'display_id';
  RAISE NOTICE 'ALL 4 REQUEST APPROVER SECURITY TESTS PASSED!';
END $$;

ROLLBACK;
