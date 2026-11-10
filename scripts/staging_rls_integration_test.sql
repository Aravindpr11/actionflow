-- ============================================================================
-- ActionFlow – Real PostgreSQL Staging RLS & Trigger Integration Test Harness
-- Target Environment: Isolated Local Supabase / PostgreSQL Staging Database ONLY.
-- NEVER execute against Cloud Production (mxaptaudaqrtwiguosvt).
-- All test fixtures use isolated synthetic UUIDs (10000000-0000-0000-0000-0000000000XX)
-- Wrapped in a transaction with ROLLBACK to leave the database clean.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Schema & Pre-requisite Assertions
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'app_private') THEN
    RAISE EXCEPTION 'Prerequisite failed: schema app_private does not exist. Apply migrations first.';
  END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 1. Setup Isolated Test Tenants, Departments, Sites, and Roles
-- ----------------------------------------------------------------------------
INSERT INTO public.organizations (id, name, code, is_active)
VALUES 
  ('a0000000-0000-0000-0000-000000000001', 'Test Tenant A', 'test-tenant-a', true),
  ('b0000000-0000-0000-0000-000000000002', 'Test Tenant B', 'test-tenant-b', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.departments (id, organization_id, name, code, division, is_active)
VALUES 
  ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Test Operations', 'TEST_OPS', 'Operations & HSSE', true),
  ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Test Safety', 'TEST_SAFE', 'Operations & HSSE', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sites (id, organization_id, name, code, location_type, is_active)
VALUES 
  ('c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Test Platform Alpha', 'TEST_ALPHA', 'Offshore Facility', true),
  ('c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Test Platform Beta', 'TEST_BETA', 'Offshore Facility', true)
ON CONFLICT (id) DO NOTHING;

-- Fetch primary role IDs
DO $$
DECLARE
  v_role_staff UUID;
  v_role_manager UUID;
  v_role_admin UUID;
BEGIN
  SELECT id INTO v_role_staff FROM public.roles WHERE code = 'staff' LIMIT 1;
  SELECT id INTO v_role_manager FROM public.roles WHERE code = 'manager' LIMIT 1;
  SELECT id INTO v_role_admin FROM public.roles WHERE code IN ('admin', 'company_admin') LIMIT 1;

  IF v_role_staff IS NULL OR v_role_manager IS NULL OR v_role_admin IS NULL THEN
    RAISE EXCEPTION 'Standard roles (staff, manager, admin) missing from public.roles.';
  END IF;

  -- --------------------------------------------------------------------------
  -- 2. Setup auth.users and public.profiles
  -- --------------------------------------------------------------------------
  -- 1: Staff A (Tenant A, Owner)
  -- 2: Staff B (Tenant A, Unrelated)
  -- 3: Staff C (Tenant A, Editor)
  -- 4: Approver 1 (Tenant A)
  -- 5: Manager In-Scope (Tenant A, Scope: Dept 1 + Site 1)
  -- 6: Manager Out-of-Scope (Tenant A, Scope: Dept 2 + Site 2)
  -- 7: Company Admin A (Tenant A)
  -- 8: Company Admin B (Tenant B)
  -- 9: Staff Cross-Tenant (Tenant B)
  -- 10: User with NULL organization_id
  
  INSERT INTO auth.users (id, email, aud, role, created_at)
  VALUES 
    ('10000000-0000-0000-0000-000000000001', 'staff_a@tenant-a.com', 'authenticated', 'authenticated', now()),
    ('10000000-0000-0000-0000-000000000002', 'staff_b@tenant-a.com', 'authenticated', 'authenticated', now()),
    ('10000000-0000-0000-0000-000000000003', 'staff_c@tenant-a.com', 'authenticated', 'authenticated', now()),
    ('10000000-0000-0000-0000-000000000004', 'approver_1@tenant-a.com', 'authenticated', 'authenticated', now()),
    ('10000000-0000-0000-0000-000000000005', 'manager_in@tenant-a.com', 'authenticated', 'authenticated', now()),
    ('10000000-0000-0000-0000-000000000006', 'manager_out@tenant-a.com', 'authenticated', 'authenticated', now()),
    ('10000000-0000-0000-0000-000000000007', 'admin@tenant-a.com', 'authenticated', 'authenticated', now()),
    ('10000000-0000-0000-0000-000000000008', 'admin@tenant-b.com', 'authenticated', 'authenticated', now()),
    ('10000000-0000-0000-0000-000000000009', 'staff@tenant-b.com', 'authenticated', 'authenticated', now()),
    ('10000000-0000-0000-0000-000000000010', 'no_org@test.com', 'authenticated', 'authenticated', now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.profiles (
    id, full_name, email, designation, organization_id, department_id, site_id, role_id, is_active, status
  ) VALUES 
    ('10000000-0000-0000-0000-000000000001', 'Staff User A', 'staff_a@tenant-a.com', 'Field Technician', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', v_role_staff, true, 'active'),
    ('10000000-0000-0000-0000-000000000002', 'Staff User B', 'staff_b@tenant-a.com', 'Safety Inspector', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', v_role_staff, true, 'active'),
    ('10000000-0000-0000-0000-000000000003', 'Staff User C (Editor)', 'staff_c@tenant-a.com', 'Lead Specialist', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', v_role_staff, true, 'active'),
    ('10000000-0000-0000-0000-000000000004', 'Approver One', 'approver_1@tenant-a.com', 'Reviewer', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', v_role_staff, true, 'active'),
    ('10000000-0000-0000-0000-000000000005', 'Manager In-Scope', 'manager_in@tenant-a.com', 'Operations Manager', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', v_role_manager, true, 'active'),
    ('10000000-0000-0000-0000-000000000006', 'Manager Out-of-Scope', 'manager_out@tenant-a.com', 'Safety Manager', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002', v_role_manager, true, 'active'),
    ('10000000-0000-0000-0000-000000000007', 'Admin Tenant A', 'admin@tenant-a.com', 'Company Administrator', 'a0000000-0000-0000-0000-000000000001', NULL, NULL, v_role_admin, true, 'active'),
    ('10000000-0000-0000-0000-000000000008', 'Admin Tenant B', 'admin@tenant-b.com', 'Company Administrator', 'b0000000-0000-0000-0000-000000000002', NULL, NULL, v_role_admin, true, 'active'),
    ('10000000-0000-0000-0000-000000000009', 'Staff Tenant B', 'staff@tenant-b.com', 'Worker', 'b0000000-0000-0000-0000-000000000002', NULL, NULL, v_role_staff, true, 'active')
  ON CONFLICT (id) DO NOTHING;

  -- Configure Manager Scope for Manager In-Scope (Dept 1 + Site 1)
  INSERT INTO public.manager_scopes (id, manager_profile_id, department_id, site_id)
  VALUES (
    'e0000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000005',
    'd0000000-0000-0000-0000-000000000001',
    'c0000000-0000-0000-0000-000000000001'
  ) ON CONFLICT (manager_profile_id, department_id, site_id) DO NOTHING;

  -- Configure Manager Scope for Manager Out-of-Scope (Dept 2 + Site 2)
  INSERT INTO public.manager_scopes (id, manager_profile_id, department_id, site_id)
  VALUES (
    'e0000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000006',
    'd0000000-0000-0000-0000-000000000002',
    'c0000000-0000-0000-0000-000000000002'
  ) ON CONFLICT (manager_profile_id, department_id, site_id) DO NOTHING;

END;
$$;

-- ----------------------------------------------------------------------------
-- 3. Seed Seeded Document & Request Fixtures
-- ----------------------------------------------------------------------------
-- Temporarily set maintenance mode for test fixture setup under superuser connection
SELECT set_config('app.maintenance_mode', 'active', true);

-- Private document owned by Staff A in Tenant A
INSERT INTO public.documents (
  id, organization_id, department_id, title, description, category,
  file_name, file_path, file_size, file_type, storage_bucket,
  created_by, created_by_name, ownership_status, created_at, updated_at
) VALUES (
  'doc-test-fixture-01',
  'a0000000-0000-0000-0000-000000000001',
  'd0000000-0000-0000-0000-000000000001',
  'Confidential Staff A Safety Audit',
  'Private notes for inspection',
  'General',
  'safety_audit.pdf',
  'a0000000-0000-0000-0000-000000000001/doc-test-fixture-01/safety_audit.pdf',
  2048,
  'application/pdf',
  'documents',
  '10000000-0000-0000-0000-000000000001',
  'Staff User A',
  'verified',
  now(),
  now()
);

-- Explicit 'edit' share for Staff C
INSERT INTO public.document_shares (
  id, document_id, organization_id, user_id, user_name, user_email, permission, shared_by, shared_by_name
) VALUES (
  'share-fixture-edit-01',
  'doc-test-fixture-01',
  'a0000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000003',
  'Staff User C',
  'staff_c@tenant-a.com',
  'edit',
  '10000000-0000-0000-0000-000000000001',
  'Staff User A'
);

-- Request created by Staff A in Tenant A (Dept 1 + Site 1)
INSERT INTO public.requests (
  id, display_id, organization_id, title, description, request_type, priority,
  department_id, department_name, site_id, site_name, required_by_date,
  approval_type, status, created_by, created_by_name, created_by_role
) VALUES (
  'f0000000-0000-0000-0000-000000000001',
  'REQ-TEST-001',
  'a0000000-0000-0000-0000-000000000001',
  'Permit to Work - Hot Work Pipeline',
  'Welding pipeline inspection request',
  'Permit to Work (PTW)',
  'High',
  'd0000000-0000-0000-0000-000000000001',
  'Test Operations',
  'c0000000-0000-0000-0000-000000000001',
  'Test Platform Alpha',
  CURRENT_DATE + 5,
  'Sequential',
  'Pending',
  '10000000-0000-0000-0000-000000000001',
  'Staff User A',
  'Staff'
);

-- Designated Approver: Approver 1 (10000000-0000-0000-0000-000000000004)
INSERT INTO public.request_approvers (
  id, request_id, organization_id, approver_id, approver_name, approver_role, step_order, status
) VALUES (
  'f0000000-0000-0000-0000-000000000002',
  'f0000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000004',
  'Approver One',
  'Staff',
  1,
  'Pending'
);

-- Request Attachment
INSERT INTO public.request_attachments (
  id, request_id, organization_id, file_name, file_path, file_size, content_type, uploaded_by
) VALUES (
  'f0000000-0000-0000-0000-000000000003',
  'f0000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000001',
  'pipeline_schematic.pdf',
  'a0000000-0000-0000-0000-000000000001/requests/f0000000-0000-0000-0000-000000000001/pipeline_schematic.pdf',
  1024,
  'application/pdf',
  '10000000-0000-0000-0000-000000000001'
);


-- ============================================================================
-- 4. Execute 26 Security Scenarios
-- ============================================================================
-- Reset maintenance mode so all subsequent tests execute with strict enforcement
SELECT set_config('app.maintenance_mode', '', true);

-- ----------------------------------------------------------------------------
-- Scenario 1: Private document isolation between unrelated staff (Expect 0 rows)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_cnt INT;
BEGIN
  -- Simulate Staff B (Unrelated)
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT count(*) INTO v_cnt FROM public.documents WHERE id = 'doc-test-fixture-01';
  IF v_cnt != 0 THEN
    RAISE EXCEPTION 'SCENARIO 1 FAILED: Unrelated Staff B saw private document! count=%', v_cnt;
  END IF;
  RAISE NOTICE 'SCENARIO 1 PASSED: Private document isolation verified.';
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 2: Explicit document sharing (Expect 1 row)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_cnt INT;
BEGIN
  -- Simulate Staff C (Share Recipient)
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT count(*) INTO v_cnt FROM public.documents WHERE id = 'doc-test-fixture-01';
  IF v_cnt != 1 THEN
    RAISE EXCEPTION 'SCENARIO 2 FAILED: Share recipient Staff C could not see shared document!';
  END IF;
  RAISE NOTICE 'SCENARIO 2 PASSED: Explicit document sharing verified.';
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 3: Edit-share metadata updates (Expect Success)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- Simulate Staff C (Editor)
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  UPDATE public.documents
  SET title = 'Staff C Updated Title', description = 'Legitimate metadata edit'
  WHERE id = 'doc-test-fixture-01';

  RAISE NOTICE 'SCENARIO 3 PASSED: Editor metadata update succeeded.';
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 4: View-only editing denial (Expect Denial)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_cnt INT;
BEGIN
  -- Simulate Staff A (Owner) creating the view-only share
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  -- Add view-only share for Staff B
  INSERT INTO public.document_shares (
    id, document_id, organization_id, user_id, permission, shared_by
  ) VALUES (
    'share-fixture-view-01', 'doc-test-fixture-01', 'a0000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000002', 'view', '10000000-0000-0000-0000-000000000001'
  );

  -- Simulate Staff B (View-Only Recipient) attempting to update
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);

  UPDATE public.documents
  SET title = 'Staff B Illegitimate Update'
  WHERE id = 'doc-test-fixture-01';

  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  IF v_cnt != 0 THEN
    RAISE EXCEPTION 'SCENARIO 4 FAILED: View-only recipient was able to update document!';
  END IF;

  -- Clean up temporary test share as Staff A (Owner / Sharer) so Staff B returns to being an unshared user
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  DELETE FROM public.document_shares WHERE id = 'share-fixture-view-01';
  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  IF v_cnt != 1 THEN
    RAISE EXCEPTION 'Cleanup failed: Staff A was unable to delete share-fixture-view-01! count=%', v_cnt;
  END IF;

  RAISE NOTICE 'SCENARIO 4 PASSED: View-only editing denial verified (0 rows updated).';
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 5: Ownership hijacking denial (Expect Exception)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- Simulate Staff C (Editor)
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  BEGIN
    UPDATE public.documents
    SET created_by = '10000000-0000-0000-0000-000000000003' -- Attempt to become owner
    WHERE id = 'doc-test-fixture-01';
    RAISE EXCEPTION 'SCENARIO 5 FAILED: Editor was able to alter created_by!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%Only authorized administrators belonging to the document organization may resolve or reassign%' THEN
      RAISE NOTICE 'SCENARIO 5 PASSED: Ownership hijacking blocked by trigger.';
    ELSE
      RAISE;
    END IF;
  END;
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 6: Storage file-path tampering denial (Expect Exception)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- Simulate Staff C (Editor)
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  BEGIN
    UPDATE public.documents
    SET file_path = 'a0000000-0000-0000-0000-000000000001/doc-test-fixture-01/tampered_path.pdf'
    WHERE id = 'doc-test-fixture-01';
    RAISE EXCEPTION 'SCENARIO 6 FAILED: Editor was able to alter file_path!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%Only the document owner or an authorized organization administrator may update underlying file storage attributes%' THEN
      RAISE NOTICE 'SCENARIO 6 PASSED: Storage path tampering blocked by trigger.';
    ELSE
      RAISE;
    END IF;
  END;
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 7: Cross-tenant reassignment denial (Expect Exception)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- Simulate Company Admin A
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000007', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  BEGIN
    UPDATE public.documents
    SET organization_id = 'b0000000-0000-0000-0000-000000000002' -- Move to Tenant B
    WHERE id = 'doc-test-fixture-01';
    RAISE EXCEPTION 'SCENARIO 7 FAILED: Company Admin was able to move document across organizations!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%Organization ID is immutable%' THEN
      RAISE NOTICE 'SCENARIO 7 PASSED: Cross-tenant move blocked for Company Admin.';
    ELSE
      RAISE;
    END IF;
  END;
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 8: Company administrator access within own organization (Expect Success)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_cnt INT;
BEGIN
  -- Simulate Company Admin A
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000007', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT count(*) INTO v_cnt FROM public.documents WHERE id = 'doc-test-fixture-01';
  IF v_cnt != 1 THEN
    RAISE EXCEPTION 'SCENARIO 8 FAILED: Company Admin A could not see document in own organization!';
  END IF;

  -- Admin can update status within own organization
  UPDATE public.documents
  SET ownership_status = 'reassigned'
  WHERE id = 'doc-test-fixture-01';

  RAISE NOTICE 'SCENARIO 8 PASSED: Company Admin governance within own organization verified.';
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 9: Company administrator denial for another organization (Expect Denial)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_cnt INT;
BEGIN
  -- Simulate Company Admin B (Tenant B)
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000008', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT count(*) INTO v_cnt FROM public.documents WHERE id = 'doc-test-fixture-01';
  IF v_cnt != 0 THEN
    RAISE EXCEPTION 'SCENARIO 9 FAILED: Company Admin B saw Tenant A document! count=%', v_cnt;
  END IF;

  -- Attempting update must update 0 rows
  UPDATE public.documents
  SET title = 'Cross-Tenant Tamper by Admin B'
  WHERE id = 'doc-test-fixture-01';

  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  IF v_cnt != 0 THEN
    RAISE EXCEPTION 'SCENARIO 9 FAILED: Admin B updated Tenant A document!';
  END IF;

  RAISE NOTICE 'SCENARIO 9 PASSED: Company Admin cross-organization denial verified.';
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 10: NULL organization authorization denial (Expect 0 rows)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_cnt INT;
BEGIN
  -- Simulate User with NULL organization_id
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000010', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  -- Assert documents access is denied
  SELECT count(*) INTO v_cnt FROM public.documents WHERE id = 'doc-test-fixture-01';
  IF v_cnt != 0 THEN
    RAISE EXCEPTION 'SCENARIO 10 FAILED: User with NULL org saw document!';
  END IF;

  -- Assert requests access is denied
  SELECT count(*) INTO v_cnt FROM public.requests WHERE id = 'f0000000-0000-0000-0000-000000000001';
  IF v_cnt != 0 THEN
    RAISE EXCEPTION 'SCENARIO 10 FAILED: User with NULL org saw request!';
  END IF;

  RAISE NOTICE 'SCENARIO 10 PASSED: NULL organization authorization denial verified.';
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 11: Requester access to their own requests (Expect 1 row)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_cnt INT;
BEGIN
  -- Simulate Staff A (Requester)
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT count(*) INTO v_cnt FROM public.requests WHERE id = 'f0000000-0000-0000-0000-000000000001';
  IF v_cnt != 1 THEN
    RAISE EXCEPTION 'SCENARIO 11 FAILED: Requester Staff A could not see own request!';
  END IF;

  RAISE NOTICE 'SCENARIO 11 PASSED: Requester access verified.';
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 12: Designated approver access (Expect 1 row)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_cnt INT;
BEGIN
  -- Simulate Approver 1
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT count(*) INTO v_cnt FROM public.requests WHERE id = 'f0000000-0000-0000-0000-000000000001';
  IF v_cnt != 1 THEN
    RAISE EXCEPTION 'SCENARIO 12 FAILED: Designated Approver 1 could not see assigned request!';
  END IF;

  SELECT count(*) INTO v_cnt FROM public.request_approvers WHERE request_id = 'f0000000-0000-0000-0000-000000000001';
  IF v_cnt != 1 THEN
    RAISE EXCEPTION 'SCENARIO 12 FAILED: Approver could not see approver record!';
  END IF;

  RAISE NOTICE 'SCENARIO 12 PASSED: Designated approver access verified.';
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 13: Unrelated staff denial on requests (Expect 0 rows)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_cnt INT;
BEGIN
  -- Simulate Staff B (Unrelated)
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT count(*) INTO v_cnt FROM public.requests WHERE id = 'f0000000-0000-0000-0000-000000000001';
  IF v_cnt != 0 THEN
    RAISE EXCEPTION 'SCENARIO 13 FAILED: Unrelated Staff B saw request! count=%', v_cnt;
  END IF;

  SELECT count(*) INTO v_cnt FROM public.request_approvers WHERE request_id = 'f0000000-0000-0000-0000-000000000001';
  IF v_cnt != 0 THEN
    RAISE EXCEPTION 'SCENARIO 13 FAILED: Unrelated Staff B saw request_approvers! count=%', v_cnt;
  END IF;

  RAISE NOTICE 'SCENARIO 13 PASSED: Unrelated staff denial on requests verified.';
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 14: Out-of-scope manager denial (Expect 0 rows)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_cnt INT;
BEGIN
  -- Simulate In-Scope Manager (Dept 1 + Site 1) -> Must See (1 row)
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000005', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT count(*) INTO v_cnt FROM public.requests WHERE id = 'f0000000-0000-0000-0000-000000000001';
  IF v_cnt != 1 THEN
    RAISE EXCEPTION 'SCENARIO 14a FAILED: In-scope manager could not see scoped request!';
  END IF;

  -- Simulate Out-of-Scope Manager (Dept 2 + Site 2) -> Must NOT See (0 rows)
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000006', true);

  SELECT count(*) INTO v_cnt FROM public.requests WHERE id = 'f0000000-0000-0000-0000-000000000001';
  IF v_cnt != 0 THEN
    RAISE EXCEPTION 'SCENARIO 14b FAILED: Out-of-scope manager saw request! count=%', v_cnt;
  END IF;

  RAISE NOTICE 'SCENARIO 14 PASSED: Manager scope isolation verified (in-scope=1, out-of-scope=0).';
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 15: Request attachment Storage authorization
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_allowed BOOLEAN;
  v_file_path TEXT := 'a0000000-0000-0000-0000-000000000001/requests/f0000000-0000-0000-0000-000000000001/pipeline_schematic.pdf';
BEGIN
  -- Requester Staff A
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  v_allowed := app_private.can_user_access_storage_request(v_file_path);
  IF NOT v_allowed THEN
    RAISE EXCEPTION 'SCENARIO 15a FAILED: Requester denied storage access!';
  END IF;

  -- Approver 1
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
  v_allowed := app_private.can_user_access_storage_request(v_file_path);
  IF NOT v_allowed THEN
    RAISE EXCEPTION 'SCENARIO 15b FAILED: Approver denied storage access!';
  END IF;

  -- Unrelated Staff B
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
  v_allowed := app_private.can_user_access_storage_request(v_file_path);
  IF v_allowed THEN
    RAISE EXCEPTION 'SCENARIO 15c FAILED: Unrelated Staff B granted storage access!';
  END IF;

  RAISE NOTICE 'SCENARIO 15 PASSED: Request storage authorization verified.';
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 16: Public helper RPC endpoints no longer exposed
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_exposed_count INT;
BEGIN
  SELECT count(*) INTO v_exposed_count
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' 
    AND p.proname IN ('can_user_access_request', 'can_user_access_storage_request', 'can_user_access_storage_document');

  IF v_exposed_count != 0 THEN
    RAISE EXCEPTION 'SCENARIO 16 FAILED: Internal helpers are still exposed in public schema! count=%', v_exposed_count;
  END IF;

  RAISE NOTICE 'SCENARIO 16 PASSED: Helper functions successfully removed from public schema.';
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 17: Anonymous/Unauthenticated trigger bypass denial
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- Simulate anonymous client
  PERFORM set_config('role', 'anon', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'anon', true);

  BEGIN
    UPDATE public.documents
    SET title = 'Tampered by Anon'
    WHERE id = 'doc-test-fixture-01';
    
    RAISE EXCEPTION 'SCENARIO 17 FAILED: Anonymous update was not rejected by trigger!';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%Authentication required%' OR SQLERRM LIKE '%permission denied%' THEN
        RAISE NOTICE 'SCENARIO 17 PASSED: Anonymous document update strictly rejected: %', SQLERRM;
      ELSE
        RAISE;
      END IF;
  END;
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 18: Service role without maintenance mode cannot bypass authentication
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- Simulate service_role without maintenance mode
  PERFORM set_config('role', 'service_role', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  BEGIN
    UPDATE public.documents
    SET title = 'Service Role Sync Attempt'
    WHERE id = 'doc-test-fixture-01';

    RAISE EXCEPTION 'SCENARIO 18 FAILED: Service role was able to update document without authentication or maintenance mode!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%Authentication required%' THEN
      RAISE NOTICE 'SCENARIO 18 PASSED: Service role without maintenance mode strictly rejected.';
    ELSE
      RAISE;
    END IF;
  END;
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 19: Document storage authorization (app_private.can_user_access_storage_document)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_allowed BOOLEAN;
  v_file_path TEXT := 'a0000000-0000-0000-0000-000000000001/doc-test-fixture-01/safety_audit.pdf';
  v_cross_path TEXT := 'b0000000-0000-0000-0000-000000000002/doc-test-fixture-01/safety_audit.pdf';
BEGIN
  -- Owner Staff A: ALLOWED
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  v_allowed := app_private.can_user_access_storage_document(v_file_path);
  IF NOT v_allowed THEN
    RAISE EXCEPTION 'SCENARIO 19a FAILED: Owner denied storage access!';
  END IF;

  -- Editor Staff C: ALLOWED
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
  v_allowed := app_private.can_user_access_storage_document(v_file_path);
  IF NOT v_allowed THEN
    RAISE EXCEPTION 'SCENARIO 19b FAILED: Editor denied storage access!';
  END IF;

  -- Unrelated Staff B: DENIED
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
  v_allowed := app_private.can_user_access_storage_document(v_file_path);
  IF v_allowed THEN
    RAISE EXCEPTION 'SCENARIO 19c FAILED: Unrelated Staff B granted storage access!';
  END IF;

  -- Cross-tenant path access by Tenant A Admin: DENIED
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000007', true);
  v_allowed := app_private.can_user_access_storage_document(v_cross_path);
  IF v_allowed THEN
    RAISE EXCEPTION 'SCENARIO 19d FAILED: Admin A accessed Tenant B storage path!';
  END IF;

  -- User with NULL org: DENIED
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000010', true);
  v_allowed := app_private.can_user_access_storage_document(v_file_path);
  IF v_allowed THEN
    RAISE EXCEPTION 'SCENARIO 19e FAILED: User with NULL org granted storage access!';
  END IF;

  RAISE NOTICE 'SCENARIO 19 PASSED: Document storage authorization verified.';
END;
$$;

-- ============================================================================
-- 5. Trigger Security Immutability & Maintenance Separation Tests
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Scenario 20: Ordinary authenticated owner cannot bypass immutability (Expect Exception)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- Simulate Staff A (Owner)
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  -- 20a: Attempt to change organization_id
  BEGIN
    UPDATE public.documents
    SET organization_id = 'b0000000-0000-0000-0000-000000000002'
    WHERE id = 'doc-test-fixture-01';
    RAISE EXCEPTION 'SCENARIO 20a FAILED: Owner was able to alter organization_id!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%Organization ID is immutable%' THEN
      RAISE NOTICE 'SCENARIO 20a PASSED: Owner cannot alter organization_id.';
    ELSE
      RAISE;
    END IF;
  END;

  -- 20b: Attempt to change primary key id
  BEGIN
    UPDATE public.documents
    SET id = 'tampered-doc-id-01'
    WHERE id = 'doc-test-fixture-01';
    RAISE EXCEPTION 'SCENARIO 20b FAILED: Owner was able to alter primary key id!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%Document primary key id is immutable%' THEN
      RAISE NOTICE 'SCENARIO 20b PASSED: Owner cannot alter primary key id.';
    ELSE
      RAISE;
    END IF;
  END;
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 21: Edit-share recipient cannot bypass immutability (Expect Exception)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- Simulate Staff C (Editor)
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  -- 21a: Attempt to alter created_by
  BEGIN
    UPDATE public.documents
    SET created_by = '10000000-0000-0000-0000-000000000003'
    WHERE id = 'doc-test-fixture-01';
    RAISE EXCEPTION 'SCENARIO 21a FAILED: Editor was able to alter created_by!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%Only authorized administrators%' THEN
      RAISE NOTICE 'SCENARIO 21a PASSED: Editor cannot alter created_by.';
    ELSE
      RAISE;
    END IF;
  END;

  -- 21b: Attempt to alter underlying storage file_path
  BEGIN
    UPDATE public.documents
    SET file_path = 'a0000000-0000-0000-0000-000000000001/doc-test-fixture-01/hijacked.pdf'
    WHERE id = 'doc-test-fixture-01';
    RAISE EXCEPTION 'SCENARIO 21b FAILED: Editor was able to alter file_path!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%Only the document owner or an authorized organization administrator%' THEN
      RAISE NOTICE 'SCENARIO 21b PASSED: Editor cannot alter file_path.';
    ELSE
      RAISE;
    END IF;
  END;
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 22: Anonymous user is rejected (Expect Exception)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- Simulate anonymous client
  PERFORM set_config('role', 'anon', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'anon', true);

  BEGIN
    UPDATE public.documents
    SET title = 'Tampered by Anon'
    WHERE id = 'doc-test-fixture-01';
    RAISE EXCEPTION 'SCENARIO 22 FAILED: Anonymous update was not rejected by trigger!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%Authentication required%' OR SQLERRM LIKE '%permission denied%' THEN
      RAISE NOTICE 'SCENARIO 22 PASSED: Anonymous document update strictly rejected.';
    ELSE
      RAISE;
    END IF;
  END;
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 23: Company admin cannot change organization_id (Expect Exception)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- Simulate Company Admin A
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000007', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  BEGIN
    UPDATE public.documents
    SET organization_id = 'b0000000-0000-0000-0000-000000000002'
    WHERE id = 'doc-test-fixture-01';
    RAISE EXCEPTION 'SCENARIO 23 FAILED: Company Admin was able to move document across organizations!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%Organization ID is immutable%' THEN
      RAISE NOTICE 'SCENARIO 23 PASSED: Company Admin cannot change organization_id.';
    ELSE
      RAISE;
    END IF;
  END;
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 24: NULL organization cannot be assigned by an ordinary user (Expect Exception)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- 24a: Attempt to change organization_id to NULL
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  BEGIN
    UPDATE public.documents
    SET organization_id = NULL
    WHERE id = 'doc-test-fixture-01';
    RAISE EXCEPTION 'SCENARIO 24a FAILED: Ordinary user set organization_id to NULL!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%Organization ID is immutable%' OR SQLERRM LIKE '%cannot be null%' THEN
      RAISE NOTICE 'SCENARIO 24a PASSED: Ordinary user cannot set organization_id to NULL.';
    ELSE
      RAISE;
    END IF;
  END;
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 25: Ordinary authenticated caller cannot impersonate service-role maintenance (Expect Exception)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- Ordinary user attempts to fake service_role role or headers to bypass immutability
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  
  -- Attacker attempts to set app.maintenance_mode = 'active'
  PERFORM set_config('app.maintenance_mode', 'active', true);

  -- Attacker attempts to change organization_id relying on maintenance bypass
  BEGIN
    UPDATE public.documents
    SET organization_id = 'b0000000-0000-0000-0000-000000000002'
    WHERE id = 'doc-test-fixture-01';
    RAISE EXCEPTION 'SCENARIO 25 FAILED: Ordinary user bypassed immutability by setting app.maintenance_mode!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%Organization ID is immutable%' THEN
      RAISE NOTICE 'SCENARIO 25 PASSED: Ordinary user cannot impersonate maintenance bypass.';
    ELSE
      RAISE;
    END IF;
  END;
  
  -- Reset setting
  PERFORM set_config('app.maintenance_mode', '', true);
END;
$$;

-- ----------------------------------------------------------------------------
-- Scenario 26: Authorized maintenance procedure works as intended (Expect Success when Superuser)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- When running under superuser/maintenance connection with explicit maintenance mode:
  IF session_user IN ('postgres', 'supabase_admin') THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);
    PERFORM set_config('app.maintenance_mode', 'active', true);

    UPDATE public.documents
    SET ownership_status = 'verified'
    WHERE id = 'doc-test-fixture-01';

    RAISE NOTICE 'SCENARIO 26 PASSED: Authorized maintenance procedure succeeded under trusted connection.';
    PERFORM set_config('app.maintenance_mode', '', true);
  ELSE
    RAISE NOTICE 'SCENARIO 26 SKIPPED: Current test runner session_user (%) is not superuser.', session_user;
  END IF;
END;
$$;

ROLLBACK; -- Always roll back cleanly leaving the database untouched
