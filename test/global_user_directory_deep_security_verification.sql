-- ============================================================================
-- SQL Verification: global_user_directory_deep_security_verification.sql
-- Description:
--   Comprehensive database security verification for public.directory_profiles:
--   1. Security barrier and ownership check
--   2. Permission grants verification (authenticated = SELECT only; anon = NONE)
--   3. Authenticated Staff caller visibility (can see newly created Staff & Manager in same org)
--   4. Authenticated Manager caller visibility (can see newly created Staff & Manager in same org)
--   5. Cross-tenant isolation (Org 2 caller cannot see Org 1 records under any filter)
--   6. Inactive user filtering (is_active = false rows are never returned)
--   7. Inactive caller restriction (is_active_user() = false returns 0 rows)
--   8. Anonymous role permission denied verification
-- ============================================================================

BEGIN;

-- 1. Security Barrier and Owner Check
DO $$
DECLARE
  v_reloptions TEXT[];
  v_owner NAME;
BEGIN
  SELECT reloptions, relowner::regrole::NAME INTO v_reloptions, v_owner
  FROM pg_class
  WHERE relname = 'directory_profiles';

  IF NOT ('security_barrier=true' = ANY(v_reloptions)) THEN
    RAISE EXCEPTION 'CHECK 1 FAILED: directory_profiles is missing security_barrier=true';
  END IF;

  IF v_owner <> 'postgres' AND v_owner <> 'supabase_admin' THEN
    RAISE EXCEPTION 'CHECK 1 FAILED: Unexpected view owner: %', v_owner;
  END IF;

  RAISE NOTICE 'CHECK 1 PASSED: security_barrier=true and valid owner confirmed.';
END $$;

-- 2. Privilege Grants Verification
DO $$
DECLARE
  v_anon_grants INT;
  v_auth_non_select INT;
  v_auth_select INT;
BEGIN
  SELECT count(*) INTO v_anon_grants
  FROM information_schema.role_table_grants
  WHERE table_name = 'directory_profiles' AND grantee = 'anon';

  IF v_anon_grants > 0 THEN
    RAISE EXCEPTION 'CHECK 2 FAILED: anon role has % privileges on directory_profiles (expected 0)', v_anon_grants;
  END IF;

  SELECT count(*) INTO v_auth_select
  FROM information_schema.role_table_grants
  WHERE table_name = 'directory_profiles' AND grantee = 'authenticated' AND privilege_type = 'SELECT';

  IF v_auth_select <> 1 THEN
    RAISE EXCEPTION 'CHECK 2 FAILED: authenticated role is missing SELECT privilege';
  END IF;

  SELECT count(*) INTO v_auth_non_select
  FROM information_schema.role_table_grants
  WHERE table_name = 'directory_profiles' AND grantee = 'authenticated' AND privilege_type <> 'SELECT';

  IF v_auth_non_select > 0 THEN
    RAISE EXCEPTION 'CHECK 2 FAILED: authenticated role has unauthorized write privileges (%)', v_auth_non_select;
  END IF;

  RAISE NOTICE 'CHECK 2 PASSED: Privilege grants strictly hardened (authenticated=SELECT only, anon=0).';
END $$;

-- 3. Live Functional and Security Assertions
DO $$
DECLARE
  v_org1 UUID := '00000000-0000-0000-0000-000000000001';
  v_org2 UUID := '00000000-0000-0000-0000-000000000002';
  v_staff_role_id UUID;
  v_mgr_role_id UUID;
  v_new_dept_id UUID;
  v_new_site_id UUID;
  v_new_staff_id UUID := '12345678-aaaa-bbbb-cccc-000000000001';
  v_new_mgr_id UUID := '12345678-aaaa-bbbb-cccc-000000000002';
  v_inactive_user_id UUID := '12345678-aaaa-bbbb-cccc-000000000003';
  v_caller_staff UUID := '11111111-1111-1111-1111-111111111111';
  v_caller_mgr UUID := '878d9145-7764-411f-8d26-f30f01e99e79';
  v_caller_org2 UUID := '55555555-5555-5555-5555-555555555555';
  v_caller_inactive UUID := '44444444-4444-4444-4444-444444444444';
  v_cnt INT;
BEGIN
  SELECT id INTO v_staff_role_id FROM public.roles WHERE code = 'staff' LIMIT 1;
  SELECT id INTO v_mgr_role_id FROM public.roles WHERE code = 'manager' LIMIT 1;

  -- Create new department & site in Org 1
  INSERT INTO public.departments (name, code, division, is_active, organization_id)
  VALUES ('Environmental Engineering', 'ENV-01', 'HSSE Operations', true, v_org1)
  RETURNING id INTO v_new_dept_id;

  INSERT INTO public.sites (name, code, location_type, is_active, organization_id)
  VALUES ('Coastal Terminal South', 'CTS-01', 'Terminal Facility', true, v_org1)
  RETURNING id INTO v_new_site_id;

  -- Create active Staff in Org 1
  INSERT INTO auth.users (id, email) VALUES (v_new_staff_id, 'staff.env@test.local') ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.profiles (
    id, full_name, email, phone, designation, department_id, site_id, role_id, status, is_active, organization_id
  ) VALUES (
    v_new_staff_id, 'Evelyn Staff', 'staff.env@test.local', '+1 555-0201', 'Environmental Officer',
    v_new_dept_id, v_new_site_id, v_staff_role_id, 'active', true, v_org1
  );

  -- Create active Manager in Org 1
  INSERT INTO auth.users (id, email) VALUES (v_new_mgr_id, 'mgr.env@test.local') ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.profiles (
    id, full_name, email, phone, designation, department_id, site_id, role_id, status, is_active, organization_id
  ) VALUES (
    v_new_mgr_id, 'Marcus Manager', 'mgr.env@test.local', '+1 555-0202', 'Environmental Director',
    v_new_dept_id, v_new_site_id, v_mgr_role_id, 'active', true, v_org1
  );

  -- Create inactive user in Org 1
  INSERT INTO auth.users (id, email) VALUES (v_inactive_user_id, 'inactive.user@test.local') ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.profiles (
    id, full_name, email, phone, designation, department_id, site_id, role_id, status, is_active, organization_id
  ) VALUES (
    v_inactive_user_id, 'Inactive Person', 'inactive.user@test.local', '+1 555-0203', 'Ex-Worker',
    v_new_dept_id, v_new_site_id, v_staff_role_id, 'inactive', false, v_org1
  );

  -- SUBTEST 3: Authenticated Staff caller queries directory_profiles
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_caller_staff::text, 'role', 'authenticated')::text, true);

  SELECT count(*) INTO v_cnt FROM public.directory_profiles WHERE id = v_new_staff_id;
  IF v_cnt <> 1 THEN RAISE EXCEPTION 'SUBTEST 3 FAILED: Newly created Staff not visible to Staff caller'; END IF;

  SELECT count(*) INTO v_cnt FROM public.directory_profiles WHERE id = v_new_mgr_id;
  IF v_cnt <> 1 THEN RAISE EXCEPTION 'SUBTEST 3 FAILED: Newly created Manager not visible to Staff caller'; END IF;

  -- Verify inactive user is excluded
  SELECT count(*) INTO v_cnt FROM public.directory_profiles WHERE id = v_inactive_user_id;
  IF v_cnt <> 0 THEN RAISE EXCEPTION 'SUBTEST 3 FAILED: Inactive user returned in directory'; END IF;

  RAISE NOTICE 'CHECK 3 PASSED: Authenticated Staff caller accurately retrieves active colleagues and filters inactive users.';

  -- SUBTEST 4: Authenticated Manager caller queries directory_profiles
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_caller_mgr::text, 'role', 'authenticated')::text, true);

  SELECT count(*) INTO v_cnt FROM public.directory_profiles WHERE id = v_new_staff_id;
  IF v_cnt <> 1 THEN RAISE EXCEPTION 'SUBTEST 4 FAILED: Newly created Staff not visible to Manager caller'; END IF;

  SELECT count(*) INTO v_cnt FROM public.directory_profiles WHERE id = v_new_mgr_id;
  IF v_cnt <> 1 THEN RAISE EXCEPTION 'SUBTEST 4 FAILED: Newly created Manager not visible to Manager caller'; END IF;

  RAISE NOTICE 'CHECK 4 PASSED: Authenticated Manager caller accurately retrieves active colleagues.';

  -- SUBTEST 5: Cross-tenant isolation check (Org 2 caller attempting to query Org 1 records)
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_caller_org2::text, 'role', 'authenticated')::text, true);

  SELECT count(*) INTO v_cnt FROM public.directory_profiles WHERE id IN (v_new_staff_id, v_new_mgr_id);
  IF v_cnt <> 0 THEN RAISE EXCEPTION 'SUBTEST 5 FAILED: Cross-tenant leak! Org 2 caller saw % Org 1 rows', v_cnt; END IF;

  -- Attempt deliberate filter targeting Org 1
  SELECT count(*) INTO v_cnt FROM public.directory_profiles WHERE organization_id = v_org1;
  IF v_cnt <> 0 THEN RAISE EXCEPTION 'SUBTEST 5 FAILED: Cross-tenant filter injection returned % rows', v_cnt; END IF;

  RAISE NOTICE 'CHECK 5 PASSED: Cross-tenant isolation is strictly enforced. 0 rows returned across tenant boundaries.';

  -- SUBTEST 6: Inactive caller restriction
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_caller_inactive::text, 'role', 'authenticated')::text, true);

  SELECT count(*) INTO v_cnt FROM public.directory_profiles;
  IF v_cnt <> 0 THEN RAISE EXCEPTION 'SUBTEST 6 FAILED: Inactive caller saw % rows (expected 0)', v_cnt; END IF;

  RAISE NOTICE 'CHECK 6 PASSED: Inactive caller is completely blocked (0 rows).';
END $$;

ROLLBACK;

