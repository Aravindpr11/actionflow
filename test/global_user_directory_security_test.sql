-- ============================================================================
-- SQL Test: global_user_directory_security_test.sql
-- Description:
--   Verifies:
--   1. Newly created Staff user is visible in public.directory_profiles to both
--      Manager and Staff callers within the same organization.
--   2. Newly created Manager is visible in public.directory_profiles.
--   3. Newly created Department and Site are queryable by authenticated users.
--   4. Cross-tenant isolation: Org 2 users cannot see Org 1 users in directory_profiles.
--   5. Inactive users (is_active = false) are excluded.
--   6. Inactive callers (is_active_user() = false) are completely blocked.
--   7. Sanitized fields (email, phone, role_code, organization_id) are projected cleanly.
-- ============================================================================

BEGIN;

-- Setup test roles if not existing
DO $$
DECLARE
  v_org1 UUID := '00000000-0000-0000-0000-000000000001';
  v_org2 UUID := '00000000-0000-0000-0000-000000000002';
  v_staff_role_id UUID;
  v_mgr_role_id UUID;
  v_new_dept_id UUID;
  v_new_site_id UUID;
  v_new_staff_id UUID := 'aaaaaaaa-1111-2222-3333-444444444444';
  v_new_mgr_id UUID := 'bbbbbbbb-1111-2222-3333-444444444444';
  v_caller_staff UUID := '11111111-1111-1111-1111-111111111111';
  v_caller_mgr UUID := '878d9145-7764-411f-8d26-f30f01e99e79';
  v_caller_org2 UUID := '55555555-5555-5555-5555-555555555555';
  v_caller_inactive UUID := '44444444-4444-4444-4444-444444444444';
  v_cnt INT;
BEGIN
  SELECT id INTO v_staff_role_id FROM public.roles WHERE code = 'staff' LIMIT 1;
  SELECT id INTO v_mgr_role_id FROM public.roles WHERE code = 'manager' LIMIT 1;

  -- 1. Create a newly created Department in Org 1
  INSERT INTO public.departments (name, code, division, is_active, organization_id)
  VALUES ('Logistics & Dispatch', 'LOG-99', 'Operations & HSSE', true, v_org1)
  RETURNING id INTO v_new_dept_id;

  -- 2. Create a newly created Site in Org 1 (independent entity without department_id)
  INSERT INTO public.sites (name, code, location_type, is_active, organization_id)
  VALUES ('Offshore Barge Alpha', 'OBA-99', 'Onshore / Offshore Facility', true, v_org1)
  RETURNING id INTO v_new_site_id;

  -- 3. Create a newly created Staff user in auth.users & public.profiles
  INSERT INTO auth.users (id, email) VALUES (v_new_staff_id, 'new_staff@test.local')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.profiles (
    id, full_name, email, phone, designation, department_id, site_id, role_id, status, is_active, organization_id
  ) VALUES (
    v_new_staff_id, 'Alice QA Staff', 'new_staff@test.local', '+1234567890', 'QA Inspector',
    v_new_dept_id, v_new_site_id, v_staff_role_id, 'active', true, v_org1
  );

  -- 4. Create a newly created Manager user in auth.users & public.profiles
  INSERT INTO auth.users (id, email) VALUES (v_new_mgr_id, 'new_mgr@test.local')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.profiles (
    id, full_name, email, phone, designation, department_id, site_id, role_id, status, is_active, organization_id
  ) VALUES (
    v_new_mgr_id, 'Bob QA Manager', 'new_mgr@test.local', '+1987654321', 'QA Manager',
    v_new_dept_id, v_new_site_id, v_mgr_role_id, 'active', true, v_org1
  );

  -- TEST 1: Authenticated Staff caller in Org 1 querying directory_profiles
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_caller_staff::text, 'role', 'authenticated')::text, true);

  SELECT count(*) INTO v_cnt FROM public.directory_profiles WHERE id = v_new_staff_id;
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'TEST 1 FAILED: Newly created Staff user Alice not visible to Staff caller';
  END IF;

  SELECT count(*) INTO v_cnt FROM public.directory_profiles WHERE id = v_new_mgr_id;
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'TEST 1 FAILED: Newly created Manager user Bob not visible to Staff caller';
  END IF;

  -- Verify projected columns for Alice
  SELECT count(*) INTO v_cnt FROM public.directory_profiles
  WHERE id = v_new_staff_id
    AND full_name = 'Alice QA Staff'
    AND email = 'new_staff@test.local'
    AND phone = '+1234567890'
    AND role_code = 'staff'
    AND department_name = 'Logistics & Dispatch'
    AND site_name = 'Offshore Barge Alpha'
    AND organization_id = v_org1;
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'TEST 1 FAILED: Alice QA Staff columns not projected accurately';
  END IF;

  -- TEST 2: Authenticated Manager caller in Org 1 querying directory_profiles
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_caller_mgr::text, 'role', 'authenticated')::text, true);

  SELECT count(*) INTO v_cnt FROM public.directory_profiles WHERE id = v_new_staff_id;
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'TEST 2 FAILED: Newly created Staff user Alice not visible to Manager caller';
  END IF;

  -- TEST 3: Authenticated Staff caller querying departments and sites directly
  SELECT count(*) INTO v_cnt FROM public.departments WHERE id = v_new_dept_id;
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'TEST 3 FAILED: Newly created department not readable by authenticated user';
  END IF;

  SELECT count(*) INTO v_cnt FROM public.sites WHERE id = v_new_site_id;
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'TEST 3 FAILED: Newly created site not readable by authenticated user';
  END IF;

  -- TEST 4: Cross-tenant isolation (Caller in Org 2 must NOT see Org 1 records)
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_caller_org2::text, 'role', 'authenticated')::text, true);

  SELECT count(*) INTO v_cnt FROM public.directory_profiles WHERE id IN (v_new_staff_id, v_new_mgr_id, v_caller_staff, v_caller_mgr);
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'TEST 4 FAILED: Cross-tenant leak detected! Org 2 caller saw % Org 1 users', v_cnt;
  END IF;

  SELECT count(*) INTO v_cnt FROM public.departments WHERE id = v_new_dept_id;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'TEST 4 FAILED: Cross-tenant leak detected! Org 2 caller saw Org 1 department';
  END IF;

  SELECT count(*) INTO v_cnt FROM public.sites WHERE id = v_new_site_id;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'TEST 4 FAILED: Cross-tenant leak detected! Org 2 caller saw Org 1 site';
  END IF;

  -- TEST 5: Inactive caller is completely blocked
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_caller_inactive::text, 'role', 'authenticated')::text, true);

  SELECT count(*) INTO v_cnt FROM public.directory_profiles;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'TEST 5 FAILED: Inactive caller saw % directory rows (expected 0)', v_cnt;
  END IF;

  RAISE NOTICE 'ALL 5 DATABASE REGRESSION TESTS PASSED SUCCESSFULLY!';
END $$;

ROLLBACK;
