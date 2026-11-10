-- ============================================================================
-- ActionFlow Request Management Database Security & RLS Verification Suite
-- Run against local Docker PostgreSQL: supabase_db_actionflow_local_test
-- ============================================================================

DO $$
DECLARE
  v_org_id UUID := '00000000-0000-0000-0000-000000000001'::UUID;
  v_other_org_id UUID := '00000000-0000-0000-0000-000000000002'::UUID;

  -- Scoped for Operations Manager:
  v_dept_scoped UUID := 'f0ad05aa-c85a-40e5-b309-19f1e6629e7a'::UUID;
  v_site_scoped UUID := '6abf4ba5-e8b7-4076-8c97-80f4a354f94b'::UUID;

  -- Out-of-scope for Operations Manager:
  v_dept_unscoped UUID := 'd348a7f3-faa2-44d4-a200-9adc8966b730'::UUID;
  v_site_unscoped UUID := '68d0dcba-7067-45ce-bd55-2ef3113bd79d'::UUID;

  v_user_requester UUID := '11111111-1111-1111-1111-111111111111'::UUID;
  v_user_approver1 UUID := '22222222-2222-2222-2222-222222222222'::UUID;
  v_user_approver2 UUID := '33333333-3333-3333-3333-333333333333'::UUID;
  v_user_manager   UUID := '878d9145-7764-411f-8d26-f30f01e99e79'::UUID;
  v_user_cross_org UUID := '55555555-5555-5555-5555-555555555555'::UUID;

  v_req_id UUID;
  v_req_unscoped_id UUID;
  v_res JSONB;
  v_status VARCHAR(50);
  v_caught BOOLEAN;
BEGIN
  RAISE NOTICE '=== 1. Testing submit_new_request RPC (Scoped Request) ===';
  PERFORM set_config('request.jwt.claim.sub', v_user_requester::text, true);

  v_res := public.submit_new_request(
    'Excavation Permit Alpha',
    'Permit required for deep trenching at Scoped Site',
    'Permit to Work (PTW)',
    'High',
    v_dept_scoped,
    'HSE / Safety',
    v_site_scoped,
    'test site',
    '2026-12-15'::DATE,
    '09:00',
    'Sequential',
    'Urgent trenching',
    jsonb_build_array(
      jsonb_build_object('approver_id', v_user_approver1, 'approver_name', 'Maint Staff', 'approver_role', 'Staff', 'approver_department', 'Maintenance', 'step_order', 1),
      jsonb_build_object('approver_id', v_user_approver2, 'approver_name', 'HSE Worker', 'approver_role', 'Staff', 'approver_department', 'HSE', 'step_order', 2)
    ),
    jsonb_build_array(
      jsonb_build_object('file_name', 'plan.pdf', 'file_path', v_org_id::text || '/requests/1730700000_plan.pdf', 'file_size', 2048, 'content_type', 'application/pdf')
    )
  );

  v_req_id := (v_res->>'id')::UUID;
  ASSERT v_req_id IS NOT NULL, 'submit_new_request failed to return id';
  ASSERT (v_res->>'display_id') LIKE 'REQ-%', 'submit_new_request failed to generate REQ- display_id';
  RAISE NOTICE 'Created Request ID: %, Display ID: %', v_req_id, v_res->>'display_id';

  RAISE NOTICE '=== 2. Testing Sequential Step Skipping Guard ===';
  -- Approver 2 tries to approve before Approver 1 has approved
  PERFORM set_config('request.jwt.claim.sub', v_user_approver2::text, true);
  v_caught := FALSE;
  BEGIN
    PERFORM public.record_request_approval_decision(v_req_id, 'Approved', 'Looks good');
  EXCEPTION WHEN OTHERS THEN
    v_caught := TRUE;
    RAISE NOTICE 'Step-skipping correctly blocked: %', SQLERRM;
  END;
  ASSERT v_caught, 'Step skipping was NOT blocked!';

  RAISE NOTICE '=== 3. Testing Unauthorized Approval Call ===';
  -- Cross org user tries to approve
  PERFORM set_config('request.jwt.claim.sub', v_user_cross_org::text, true);
  v_caught := FALSE;
  BEGIN
    PERFORM public.record_request_approval_decision(v_req_id, 'Approved', 'Malicious approval');
  EXCEPTION WHEN OTHERS THEN
    v_caught := TRUE;
    RAISE NOTICE 'Unauthorized approval correctly rejected: %', SQLERRM;
  END;
  ASSERT v_caught, 'Unauthorized approval was NOT rejected!';

  RAISE NOTICE '=== 4. Testing Valid Step 1 Approval ===';
  PERFORM set_config('request.jwt.claim.sub', v_user_approver1::text, true);
  PERFORM public.record_request_approval_decision(v_req_id, 'Approved', 'Step 1 verified');

  SELECT status INTO v_status FROM public.requests WHERE id = v_req_id;
  ASSERT v_status = 'Under Review', 'Status should be Under Review after Step 1';
  RAISE NOTICE 'Status after Step 1: %', v_status;

  RAISE NOTICE '=== 5. Testing Valid Step 2 Approval (Transitions to Approved) ===';
  PERFORM set_config('request.jwt.claim.sub', v_user_approver2::text, true);
  PERFORM public.record_request_approval_decision(v_req_id, 'Approved', 'Step 2 approved');

  SELECT status INTO v_status FROM public.requests WHERE id = v_req_id;
  ASSERT v_status = 'Approved', 'Status should be Approved after Step 2';
  RAISE NOTICE 'Status after Step 2: %', v_status;

  RAISE NOTICE '=== 6. Testing Manager Scope Visibility & Completion ===';
  -- Create an out-of-scope request
  PERFORM set_config('request.jwt.claim.sub', v_user_requester::text, true);
  v_res := public.submit_new_request(
    'Confidential Operations Exemption',
    'Operations request outside manager scope',
    'Equipment',
    'Critical',
    v_dept_unscoped,
    'Operations',
    v_site_unscoped,
    'Platform Alpha',
    '2026-12-20'::DATE,
    '10:00',
    'Sequential',
    'Unscoped notes',
    jsonb_build_array(
      jsonb_build_object('approver_id', v_user_approver1, 'approver_name', 'Maint Staff', 'approver_role', 'Staff', 'approver_department', 'Maintenance', 'step_order', 1)
    ),
    '[]'::jsonb
  );
  v_req_unscoped_id := (v_res->>'id')::UUID;

  -- Test Manager can complete the in-scope approved request
  PERFORM set_config('request.jwt.claim.sub', v_user_manager::text, true);
  PERFORM public.complete_request(v_req_id, 'Manager verified in-scope completed.');
  SELECT status INTO v_status FROM public.requests WHERE id = v_req_id;
  ASSERT v_status = 'Completed', 'Status should be Completed';
  RAISE NOTICE 'Scoped Manager successfully completed request %', v_req_id;

  -- Approve the unscoped request
  PERFORM set_config('request.jwt.claim.sub', v_user_approver1::text, true);
  PERFORM public.record_request_approval_decision(v_req_unscoped_id, 'Approved', 'Approved by lead');

  -- Manager attempts to complete the OUT-OF-SCOPE request (MUST FAIL)
  PERFORM set_config('request.jwt.claim.sub', v_user_manager::text, true);
  v_caught := FALSE;
  BEGIN
    PERFORM public.complete_request(v_req_unscoped_id, 'Unauthorized manager completion');
  EXCEPTION WHEN OTHERS THEN
    v_caught := TRUE;
    RAISE NOTICE 'Out-of-scope manager completion correctly rejected: %', SQLERRM;
  END;
  ASSERT v_caught, 'Out-of-scope manager was NOT rejected from completing request!';

  RAISE NOTICE '=== 7. Testing Forwarding Security ===';
  -- Forward to self must fail
  PERFORM set_config('request.jwt.claim.sub', v_user_requester::text, true);
  v_caught := FALSE;
  BEGIN
    PERFORM public.forward_request(v_req_id, v_user_requester, 'Self forward');
  EXCEPTION WHEN OTHERS THEN
    v_caught := TRUE;
    RAISE NOTICE 'Self-forward correctly rejected: %', SQLERRM;
  END;
  ASSERT v_caught, 'Self-forward was NOT rejected!';

  -- Cross-org forward must fail
  v_caught := FALSE;
  BEGIN
    PERFORM public.forward_request(v_req_id, v_user_cross_org, 'Cross org');
  EXCEPTION WHEN OTHERS THEN
    v_caught := TRUE;
    RAISE NOTICE 'Cross-org forward correctly rejected: %', SQLERRM;
  END;
  ASSERT v_caught, 'Cross-org forward was NOT rejected!';

  -- Authorized forward to v_user_approver2
  PERFORM public.forward_request(v_req_id, v_user_approver2, 'FYI on completed trenching');
  ASSERT EXISTS (SELECT 1 FROM public.request_forwards WHERE request_id = v_req_id AND to_user_id = v_user_approver2), 'Forward record missing';
  RAISE NOTICE 'Forward record successfully inserted.';

  RAISE NOTICE '=== 8. Testing Storage Access Helper (can_user_access_storage_request) ===';
  -- Submitter access
  PERFORM set_config('request.jwt.claim.sub', v_user_requester::text, true);
  ASSERT public.can_user_access_storage_request(v_org_id::text || '/requests/1730700000_plan.pdf'), 'Submitter denied storage access!';

  -- Approver access
  PERFORM set_config('request.jwt.claim.sub', v_user_approver1::text, true);
  ASSERT public.can_user_access_storage_request(v_org_id::text || '/requests/1730700000_plan.pdf'), 'Approver denied storage access!';

  -- Scoped manager access
  PERFORM set_config('request.jwt.claim.sub', v_user_manager::text, true);
  ASSERT public.can_user_access_storage_request(v_org_id::text || '/requests/1730700000_plan.pdf'), 'Scoped manager denied storage access!';

  -- Cross-tenant access MUST be denied
  PERFORM set_config('request.jwt.claim.sub', v_user_cross_org::text, true);
  ASSERT NOT public.can_user_access_storage_request(v_org_id::text || '/requests/1730700000_plan.pdf'), 'Cross-tenant user granted storage access!';

  RAISE NOTICE '=== ALL 8 POSTGRESQL DATABASE SECURITY & RPC SUITE TESTS PASSED! ===';

  -- Cleanup test data
  DELETE FROM public.request_history WHERE request_id IN (v_req_id, v_req_unscoped_id);
  DELETE FROM public.request_forwards WHERE request_id IN (v_req_id, v_req_unscoped_id);
  DELETE FROM public.request_attachments WHERE request_id IN (v_req_id, v_req_unscoped_id);
  DELETE FROM public.request_approvers WHERE request_id IN (v_req_id, v_req_unscoped_id);
  DELETE FROM public.requests WHERE id IN (v_req_id, v_req_unscoped_id);
END $$;
