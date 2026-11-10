-- =============================================================================
-- Test Suite: test/request_metrics_security_test.sql
-- Description:
--   Comprehensive controlled PostgreSQL regression test suite verifying:
--     1. Manager scope semantics (Department-only, Site-only, Combined).
--     2. Unscoped / unauthorized manager receives 0 counts (no org-wide leak).
--     3. Company Admin receives organization-wide metrics across all scopes.
--     4. Cross-organization tenant boundary isolation.
--     5. Draft status exclusion and complete status integrity:
--        - 'Draft' excluded from total and categories.
--        - 'Pending' counted in under_review (Mgr) and pending_approval (Staff).
--        - 'Under Review' counted in under_review.
--        - 'Approved' counted in approved.
--        - 'Rejected' counted in rejected.
--        - 'Completed' counted in completed.
--        - Mathematical sum check:
--          total = under_review + approved + rejected + completed (Manager).
--          my_submitted_total = pending_approval + under_review + approved + rejected + completed (Staff).
--     6. Signature hardening: Parameterized invocations are completely rejected.
--     7. Staff own-request isolation (privacy preserved).
--     8. Sequential step 2 dependency and parallel concurrent approval.
--     9. High-scale (>1,000 requests) performance without PostgREST limits.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Clean up any leftover test data
-- -----------------------------------------------------------------------------
DELETE FROM public.request_approvers WHERE request_id IN (
  SELECT id FROM public.requests WHERE display_id LIKE 'REQ-T-%' OR display_id LIKE 'REQ-SCALE-%'
);
DELETE FROM public.requests WHERE display_id LIKE 'REQ-T-%' OR display_id LIKE 'REQ-SCALE-%';

-- -----------------------------------------------------------------------------
-- 1. Setup Test Fixtures within Isolated Transaction
-- -----------------------------------------------------------------------------

-- 1.1 Create Company Admin in auth.users and profiles
INSERT INTO auth.users (id, email, is_sso_user)
VALUES ('99999999-9999-9999-9999-999999999999', 'admin@sobha.test', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (
  id, email, full_name, designation, organization_id, role_id, is_active, is_primary_admin
) VALUES (
  '99999999-9999-9999-9999-999999999999', 'admin@sobha.test', 'Sobha Company Admin', 'Company Administrator',
  '00000000-0000-0000-0000-000000000001', 'bfd9348a-5266-46c2-b08e-63e83850d6f0', true, true
) ON CONFLICT (id) DO UPDATE
SET role_id = EXCLUDED.role_id,
    is_primary_admin = true,
    organization_id = EXCLUDED.organization_id,
    is_active = true,
    full_name = EXCLUDED.full_name,
    designation = EXCLUDED.designation;

-- 1.2 Create an Unscoped Manager (manager role, but 0 entries in manager_scopes)
INSERT INTO auth.users (id, email, is_sso_user)
VALUES ('77777777-7777-7777-7777-777777777777', 'unscoped_mgr@sobha.test', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (
  id, email, full_name, designation, organization_id, role_id, is_active, is_primary_admin
) VALUES (
  '77777777-7777-7777-7777-777777777777', 'unscoped_mgr@sobha.test', 'Unscoped Manager', 'Assistant Manager',
  '00000000-0000-0000-0000-000000000001', '6b266919-040d-4228-a2ce-61309d5978ad', true, false
) ON CONFLICT (id) DO UPDATE
SET role_id = EXCLUDED.role_id,
    is_primary_admin = false,
    organization_id = EXCLUDED.organization_id,
    is_active = true;

DELETE FROM public.manager_scopes WHERE manager_profile_id = '77777777-7777-7777-7777-777777777777';

-- 1.3 Department and Site UUIDs for Org 1:
-- HSE Dept: f0ad05aa-c85a-40e5-b309-19f1e6629e7a
-- Operations Dept: d348a7f3-faa2-44d4-a200-9adc8966b730
-- Sobha Hartland Site: 6abf4ba5-e8b7-4076-8c97-80f4a354f94b
-- Platform Alpha Site: 68d0dcba-7067-45ce-bd55-2ef3113bd79d
-- Note: Scoped Manager 878d9145-7764-411f-8d26-f30f01e99e79 HAS scope for (HSE, Sobha Hartland),
-- but does NOT have scope for (HSE, Platform Alpha) or (Operations, Sobha Hartland).

-- 1.4 Test Requests for Scope Semantics:
-- Scope Match: (HSE, Sobha Hartland) -> Status: Pending
INSERT INTO public.requests (
  id, display_id, organization_id, title, description, request_type, priority,
  department_id, site_id, required_by_date, approval_type, status,
  created_by, created_by_name, created_by_role
) VALUES (
  'c0000000-0000-0000-0000-000000000001', 'REQ-T-SCOPE-MATCH', '00000000-0000-0000-0000-000000000001',
  'Permitted In Scope Request', 'Matches manager dept and site', 'Equipment', 'Medium',
  'f0ad05aa-c85a-40e5-b309-19f1e6629e7a', '6abf4ba5-e8b7-4076-8c97-80f4a354f94b',
  CURRENT_DATE, 'Sequential', 'Pending',
  '11111111-1111-1111-1111-111111111111', 'HSE Officer', 'Staff'
);

-- Dept Match, Site Mismatch: (HSE, Platform Alpha) -> Status: Pending
INSERT INTO public.requests (
  id, display_id, organization_id, title, description, request_type, priority,
  department_id, site_id, required_by_date, approval_type, status,
  created_by, created_by_name, created_by_role
) VALUES (
  'c0000000-0000-0000-0000-000000000002', 'REQ-T-DEPT-ONLY', '00000000-0000-0000-0000-000000000001',
  'Dept Match Site Mismatch', 'Same department but unmanaged site', 'Equipment', 'High',
  'f0ad05aa-c85a-40e5-b309-19f1e6629e7a', '68d0dcba-7067-45ce-bd55-2ef3113bd79d',
  CURRENT_DATE, 'Sequential', 'Pending',
  '11111111-1111-1111-1111-111111111111', 'HSE Officer', 'Staff'
);

-- Site Match, Dept Mismatch: (Operations, Sobha Hartland) -> Status: Pending
INSERT INTO public.requests (
  id, display_id, organization_id, title, description, request_type, priority,
  department_id, site_id, required_by_date, approval_type, status,
  created_by, created_by_name, created_by_role
) VALUES (
  'c0000000-0000-0000-0000-000000000003', 'REQ-T-SITE-ONLY', '00000000-0000-0000-0000-000000000001',
  'Site Match Dept Mismatch', 'Same site but unmanaged department', 'Material', 'Medium',
  'd348a7f3-faa2-44d4-a200-9adc8966b730', '6abf4ba5-e8b7-4076-8c97-80f4a354f94b',
  CURRENT_DATE, 'Sequential', 'Pending',
  '22222222-2222-2222-2222-222222222222', 'Maint Staff', 'Staff'
);

-- Both Mismatch: (Operations, Platform Alpha) -> Status: Pending
INSERT INTO public.requests (
  id, display_id, organization_id, title, description, request_type, priority,
  department_id, site_id, required_by_date, approval_type, status,
  created_by, created_by_name, created_by_role
) VALUES (
  'c0000000-0000-0000-0000-000000000004', 'REQ-T-BOTH-MISMATCH', '00000000-0000-0000-0000-000000000001',
  'Both Dept and Site Mismatch', 'Unmanaged dept and site', 'Access', 'Low',
  'd348a7f3-faa2-44d4-a200-9adc8966b730', '68d0dcba-7067-45ce-bd55-2ef3113bd79d',
  CURRENT_DATE, 'Sequential', 'Pending',
  '22222222-2222-2222-2222-222222222222', 'Maint Staff', 'Staff'
);

-- 1.5 Test Requests for Every Persisted Status (All in permitted scope HSE + Sobha Hartland):
-- Status: Draft (MUST BE EXCLUDED FROM MANAGER AND STAFF SUBMITTED METRICS)
INSERT INTO public.requests (
  id, display_id, organization_id, title, description, request_type, priority,
  department_id, site_id, required_by_date, approval_type, status,
  created_by, created_by_name, created_by_role
) VALUES (
  'c0000000-0000-0000-0000-000000000010', 'REQ-T-STAT-DRAFT', '00000000-0000-0000-0000-000000000001',
  'Draft HSE Request', 'Unsubmitted draft', 'Equipment', 'Low',
  'f0ad05aa-c85a-40e5-b309-19f1e6629e7a', '6abf4ba5-e8b7-4076-8c97-80f4a354f94b',
  CURRENT_DATE, 'Sequential', 'Draft',
  '11111111-1111-1111-1111-111111111111', 'HSE Officer', 'Staff'
);

-- Status: Under Review
INSERT INTO public.requests (
  id, display_id, organization_id, title, description, request_type, priority,
  department_id, site_id, required_by_date, approval_type, status,
  created_by, created_by_name, created_by_role
) VALUES (
  'c0000000-0000-0000-0000-000000000011', 'REQ-T-STAT-REVIEW', '00000000-0000-0000-0000-000000000001',
  'Under Review HSE Request', 'Active review', 'Permit to Work (PTW)', 'High',
  'f0ad05aa-c85a-40e5-b309-19f1e6629e7a', '6abf4ba5-e8b7-4076-8c97-80f4a354f94b',
  CURRENT_DATE, 'Sequential', 'Under Review',
  '11111111-1111-1111-1111-111111111111', 'HSE Officer', 'Staff'
);

-- Status: Approved
INSERT INTO public.requests (
  id, display_id, organization_id, title, description, request_type, priority,
  department_id, site_id, required_by_date, approval_type, status,
  created_by, created_by_name, created_by_role
) VALUES (
  'c0000000-0000-0000-0000-000000000012', 'REQ-T-STAT-APPR', '00000000-0000-0000-0000-000000000001',
  'Approved HSE Request', 'Ready for fulfillment', 'Material', 'Medium',
  'f0ad05aa-c85a-40e5-b309-19f1e6629e7a', '6abf4ba5-e8b7-4076-8c97-80f4a354f94b',
  CURRENT_DATE, 'Sequential', 'Approved',
  '11111111-1111-1111-1111-111111111111', 'HSE Officer', 'Staff'
);

-- Status: Rejected
INSERT INTO public.requests (
  id, display_id, organization_id, title, description, request_type, priority,
  department_id, site_id, required_by_date, approval_type, status,
  created_by, created_by_name, created_by_role
) VALUES (
  'c0000000-0000-0000-0000-000000000013', 'REQ-T-STAT-REJ', '00000000-0000-0000-0000-000000000001',
  'Rejected HSE Request', 'Declined', 'Equipment', 'Low',
  'f0ad05aa-c85a-40e5-b309-19f1e6629e7a', '6abf4ba5-e8b7-4076-8c97-80f4a354f94b',
  CURRENT_DATE, 'Sequential', 'Rejected',
  '11111111-1111-1111-1111-111111111111', 'HSE Officer', 'Staff'
);

-- Status: Completed
INSERT INTO public.requests (
  id, display_id, organization_id, title, description, request_type, priority,
  department_id, site_id, required_by_date, approval_type, status,
  created_by, created_by_name, created_by_role
) VALUES (
  'c0000000-0000-0000-0000-000000000014', 'REQ-T-STAT-COMPL', '00000000-0000-0000-0000-000000000001',
  'Completed HSE Request', 'Fulfilled and closed', 'Equipment', 'Medium',
  'f0ad05aa-c85a-40e5-b309-19f1e6629e7a', '6abf4ba5-e8b7-4076-8c97-80f4a354f94b',
  CURRENT_DATE, 'Sequential', 'Completed',
  '11111111-1111-1111-1111-111111111111', 'HSE Officer', 'Staff'
);

-- 1.6 Approval Workflow Requests (Sequential & Parallel)
-- Sequential Request:
INSERT INTO public.requests (
  id, display_id, organization_id, title, description, request_type, priority,
  department_id, site_id, required_by_date, approval_type, status,
  created_by, created_by_name, created_by_role
) VALUES (
  'c0000000-0000-0000-0000-000000000020', 'REQ-T-WF-SEQ', '00000000-0000-0000-0000-000000000001',
  'Sequential Approval Request', 'Step order dependency test', 'Permit to Work (PTW)', 'High',
  'f0ad05aa-c85a-40e5-b309-19f1e6629e7a', '6abf4ba5-e8b7-4076-8c97-80f4a354f94b',
  CURRENT_DATE, 'Sequential', 'Pending',
  '11111111-1111-1111-1111-111111111111', 'HSE Officer', 'Staff'
);

INSERT INTO public.request_approvers (
  request_id, organization_id, approver_id, approver_name, approver_role, step_order, status
) VALUES 
  ('c0000000-0000-0000-0000-000000000020', '00000000-0000-0000-0000-000000000001', '878d9145-7764-411f-8d26-f30f01e99e79', 'Operations Manager', 'Manager', 1, 'Pending'),
  ('c0000000-0000-0000-0000-000000000020', '00000000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'HSE Worker', 'Staff', 2, 'Pending');

-- Parallel Request:
INSERT INTO public.requests (
  id, display_id, organization_id, title, description, request_type, priority,
  department_id, site_id, required_by_date, approval_type, status,
  created_by, created_by_name, created_by_role
) VALUES (
  'c0000000-0000-0000-0000-000000000021', 'REQ-T-WF-PAR', '00000000-0000-0000-0000-000000000001',
  'Parallel Approval Request', 'Concurrent review test', 'Material', 'Medium',
  'f0ad05aa-c85a-40e5-b309-19f1e6629e7a', '6abf4ba5-e8b7-4076-8c97-80f4a354f94b',
  CURRENT_DATE, 'Parallel', 'Pending',
  '11111111-1111-1111-1111-111111111111', 'HSE Officer', 'Staff'
);

INSERT INTO public.request_approvers (
  request_id, organization_id, approver_id, approver_name, approver_role, step_order, status
) VALUES 
  ('c0000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000001', '878d9145-7764-411f-8d26-f30f01e99e79', 'Operations Manager', 'Manager', 1, 'Pending'),
  ('c0000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'HSE Worker', 'Staff', 2, 'Pending');

-- 1.7 Request in Different Organization (Org 2):
INSERT INTO public.requests (
  id, display_id, organization_id, title, description, request_type, priority,
  department_id, site_id, required_by_date, approval_type, status,
  created_by, created_by_name, created_by_role
) VALUES (
  'c0000000-0000-0000-0000-000000000030', 'REQ-T-ORG2', '00000000-0000-0000-0000-000000000002',
  'Org 2 Foreign Request', 'Foreign tenant isolation', 'Other', 'Low',
  NULL, NULL,
  CURRENT_DATE, 'Sequential', 'Pending',
  '55555555-5555-5555-5555-555555555555', 'Other Org Staff', 'Staff'
);

-- 1.8 Scale Test: 1,100 additional approved requests created by HSE Officer
INSERT INTO public.requests (
  display_id, organization_id, title, description, request_type, priority,
  department_id, site_id, required_by_date, approval_type, status,
  created_by, created_by_name, created_by_role
)
SELECT
  'REQ-SCALE-' || i, '00000000-0000-0000-0000-000000000001',
  'Scale Test Request ' || i, 'Load test item', 'Equipment', 'Low',
  'f0ad05aa-c85a-40e5-b309-19f1e6629e7a', '6abf4ba5-e8b7-4076-8c97-80f4a354f94b',
  CURRENT_DATE, 'Sequential', 'Approved',
  '11111111-1111-1111-1111-111111111111', 'HSE Officer', 'Staff'
FROM generate_series(1, 1100) i;

-- -----------------------------------------------------------------------------
-- EXECUTE TEST SUITE
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- TEST SUITE PART 1: Manager Scope Semantics & Draft Exclusion
-- -----------------------------------------------------------------------------

-- In-scope non-draft requests for Scoped Operations Manager:
-- 1. REQ-T-SCOPE-MATCH (Pending) -> 1
-- 2. REQ-T-STAT-REVIEW (Under Review) -> 1
-- 3. REQ-T-STAT-APPR (Approved) -> 1
-- 4. REQ-T-STAT-REJ (Rejected) -> 1
-- 5. REQ-T-STAT-COMPL (Completed) -> 1
-- 6. REQ-T-WF-SEQ (Pending) -> 1
-- 7. REQ-T-WF-PAR (Pending) -> 1
-- 8. REQ-SCALE-1..1100 (Approved) -> 1100
-- Total in scope non-draft = 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1100 = 1107 requests.
--
-- Requests NOT in scope for this manager:
-- - REQ-T-STAT-DRAFT (Draft, even though dept+site matches) -> EXCLUDED (status = Draft)
-- - REQ-T-DEPT-ONLY (Dept matches, site does NOT) -> EXCLUDED
-- - REQ-T-SITE-ONLY (Site matches, dept does NOT) -> EXCLUDED
-- - REQ-T-BOTH-MISMATCH (Neither matches) -> EXCLUDED
-- - REQ-T-ORG2 (Org 2) -> EXCLUDED

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '878d9145-7764-411f-8d26-f30f01e99e79';

-- TEST 1A: Manager In-Scope Total & Breakdown
SELECT 'TEST 1A: Scoped manager in-scope total (excludes drafts and unmanaged scopes)' as test_case,
       (public.get_manager_request_metrics()->>'total')::int = 1107 as pass,
       public.get_manager_request_metrics() as raw_output;

-- TEST 1B: Manager Status Breakdown Reconciles Exactly to Total
SELECT 'TEST 1B: Manager categories sum up exactly to total' as test_case,
       ((public.get_manager_request_metrics()->>'under_review')::int +
        (public.get_manager_request_metrics()->>'approved')::int +
        (public.get_manager_request_metrics()->>'rejected')::int +
        (public.get_manager_request_metrics()->>'completed')::int) =
        (public.get_manager_request_metrics()->>'total')::int as pass,
       (public.get_manager_request_metrics()->>'under_review')::int as under_review_count,
       (public.get_manager_request_metrics()->>'approved')::int as approved_count,
       (public.get_manager_request_metrics()->>'rejected')::int as rejected_count,
       (public.get_manager_request_metrics()->>'completed')::int as completed_count,
       (public.get_manager_request_metrics()->>'total')::int as total_count;

-- -----------------------------------------------------------------------------
-- TEST SUITE PART 2: Unscoped Manager (Zero Scopes Assigned)
-- -----------------------------------------------------------------------------
-- Unscoped manager must get 0 for all counts; must NEVER default to org-wide access!
SET LOCAL "request.jwt.claim.sub" = '77777777-7777-7777-7777-777777777777';

SELECT 'TEST 2: Unscoped manager receives 0 counts (no company-wide leak)' as test_case,
       (public.get_manager_request_metrics()->>'total')::int = 0 AND
       (public.get_manager_request_metrics()->>'under_review')::int = 0 AND
       (public.get_manager_request_metrics()->>'approved')::int = 0 AND
       (public.get_manager_request_metrics()->>'rejected')::int = 0 AND
       (public.get_manager_request_metrics()->>'completed')::int = 0 as pass,
       public.get_manager_request_metrics() as unscoped_mgr_output;

-- -----------------------------------------------------------------------------
-- TEST SUITE PART 3: Company Admin Organization-Wide Aggregation
-- -----------------------------------------------------------------------------
-- Company Admin sees all non-draft requests in Org 1:
-- 1107 (manager in-scope) + 3 (REQ-T-DEPT-ONLY, REQ-T-SITE-ONLY, REQ-T-BOTH-MISMATCH) = 1110 non-draft requests.
-- Draft request (REQ-T-STAT-DRAFT) remains excluded from operational total.
SET LOCAL "request.jwt.claim.sub" = '99999999-9999-9999-9999-999999999999';

SELECT 'TEST 3A: Company Admin receives organization-wide metrics across all departments/sites' as test_case,
       (public.get_manager_request_metrics()->>'total')::int = 1110 as pass,
       (public.get_manager_request_metrics()->>'total')::int as admin_total_count;

SELECT 'TEST 3B: Company Admin categories sum up exactly to total' as test_case,
       ((public.get_manager_request_metrics()->>'under_review')::int +
        (public.get_manager_request_metrics()->>'approved')::int +
        (public.get_manager_request_metrics()->>'rejected')::int +
        (public.get_manager_request_metrics()->>'completed')::int) =
        (public.get_manager_request_metrics()->>'total')::int as pass,
       (public.get_manager_request_metrics()->>'total')::int as total_count;

-- -----------------------------------------------------------------------------
-- TEST SUITE PART 4: Parameter Manipulation Prevention (Signature Hardening)
-- -----------------------------------------------------------------------------
-- Parameterized calls MUST fail with undefined_function
DO $$
BEGIN
  BEGIN
    EXECUTE 'SELECT public.get_manager_request_metrics(true, NULL, NULL)';
    RAISE EXCEPTION 'TEST 4A FAILED: Parameterized manager function still callable!';
  EXCEPTION WHEN undefined_function THEN
    RAISE NOTICE 'TEST 4A PASSED: Parameterized manager function does not exist.';
  END;
END;
$$;

DO $$
BEGIN
  BEGIN
    EXECUTE 'SELECT public.get_staff_request_metrics(true)';
    RAISE EXCEPTION 'TEST 4B FAILED: Parameterized staff function still callable!';
  EXCEPTION WHEN undefined_function THEN
    RAISE NOTICE 'TEST 4B PASSED: Parameterized staff function does not exist.';
  END;
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST SUITE PART 5: Staff Metrics, Draft Exclusion & Own-Request Isolation
-- -----------------------------------------------------------------------------
-- HSE Officer created:
-- - REQ-T-STAT-DRAFT (Draft) -> EXCLUDED from submitted total
-- - REQ-T-SCOPE-MATCH (Pending) -> 1
-- - REQ-T-DEPT-ONLY (Pending) -> 1
-- - REQ-T-STAT-REVIEW (Under Review) -> 1
-- - REQ-T-STAT-APPR (Approved) -> 1
-- - REQ-T-STAT-REJ (Rejected) -> 1
-- - REQ-T-STAT-COMPL (Completed) -> 1
-- - REQ-T-WF-SEQ (Pending) -> 1
-- - REQ-T-WF-PAR (Pending) -> 1
-- - REQ-SCALE-1..1100 (Approved) -> 1100
-- Total submitted non-draft = 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1100 = 1108 requests.
SET LOCAL "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';

SELECT 'TEST 5A: Staff my_submitted_total excludes draft and includes all submitted' as test_case,
       (public.get_staff_request_metrics()->>'my_submitted_total')::int = 1108 as pass,
       public.get_staff_request_metrics() as officer_output;

SELECT 'TEST 5B: Staff categories sum up exactly to my_submitted_total' as test_case,
       ((public.get_staff_request_metrics()->>'pending_approval')::int +
        (public.get_staff_request_metrics()->>'under_review')::int +
        (public.get_staff_request_metrics()->>'approved')::int +
        (public.get_staff_request_metrics()->>'rejected')::int +
        (public.get_staff_request_metrics()->>'completed')::int) =
        (public.get_staff_request_metrics()->>'my_submitted_total')::int as pass,
       (public.get_staff_request_metrics()->>'pending_approval')::int as pending_count,
       (public.get_staff_request_metrics()->>'under_review')::int as under_review_count,
       (public.get_staff_request_metrics()->>'approved')::int as approved_count,
       (public.get_staff_request_metrics()->>'rejected')::int as rejected_count,
       (public.get_staff_request_metrics()->>'completed')::int as completed_count,
       (public.get_staff_request_metrics()->>'my_submitted_total')::int as total_count;

-- Staff own-request isolation: HSE Worker created 0 requests
SET LOCAL "request.jwt.claim.sub" = '33333333-3333-3333-3333-333333333333';
SELECT 'TEST 5C: Staff own-request isolation (Worker cannot see Officer requests)' as test_case,
       (public.get_staff_request_metrics()->>'my_submitted_total')::int = 0 as pass,
       (public.get_staff_request_metrics()->>'my_submitted_total')::int as worker_count;

-- -----------------------------------------------------------------------------
-- TEST SUITE PART 6: Sequential & Parallel Approval Rules
-- -----------------------------------------------------------------------------
-- Worker (33333333-3333-3333-3333-333333333333) is approver:
-- - REQ-T-WF-SEQ: Step 2 (Step 1 is Pending). Step 2 is BLOCKED.
-- - REQ-T-WF-PAR: Step 2 (Parallel). Step 2 is IMMEDIATELY AVAILABLE.
-- Therefore pending_my_approval must be exactly 1!
SELECT 'TEST 6A: Sequential step 2 blocked before step 1 approves' as test_case,
       (public.get_staff_request_metrics()->>'pending_my_approval')::int = 1 as pass,
       (public.get_staff_request_metrics()->>'pending_my_approval')::int as pending_count;

-- Reset role to approve Step 1 on sequential request
RESET ROLE;
UPDATE public.request_approvers SET status = 'Approved'
WHERE request_id = 'c0000000-0000-0000-0000-000000000020' AND approver_id = '878d9145-7764-411f-8d26-f30f01e99e79';
UPDATE public.requests SET status = 'Under Review'
WHERE id = 'c0000000-0000-0000-0000-000000000020';

-- Switch back to Worker: Step 2 must now be UNBLOCKED!
-- pending_my_approval must now be exactly 2 (both sequential and parallel)!
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '33333333-3333-3333-3333-333333333333';
SELECT 'TEST 6B: Sequential step 2 unblocked after step 1 approves' as test_case,
       (public.get_staff_request_metrics()->>'pending_my_approval')::int = 2 as pass,
       (public.get_staff_request_metrics()->>'pending_my_approval')::int as pending_unblocked_count;

-- -----------------------------------------------------------------------------
-- TEST SUITE PART 7: Cross-Organization Tenant Boundary Isolation
-- -----------------------------------------------------------------------------
-- Switch to Other Org Staff in Org 2
SET LOCAL "request.jwt.claim.sub" = '55555555-5555-5555-5555-555555555555';
SELECT 'TEST 7: Tenant boundary isolation (cannot view cross-org requests)' as test_case,
       (public.get_staff_request_metrics()->>'my_submitted_total')::int = 1 as pass,
       public.get_staff_request_metrics() as org2_output;

-- -----------------------------------------------------------------------------
-- TEST SUITE PART 8: Scale Test (>1,000 requests aggregate performance)
-- -----------------------------------------------------------------------------
-- Verify that aggregating 1,100+ requests succeeds instantly without truncation.
SET LOCAL "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';
SELECT 'TEST 8: Scale aggregation >1,000 rows without truncation' as test_case,
       (public.get_staff_request_metrics()->>'my_submitted_total')::int > 1000 as pass,
       (public.get_staff_request_metrics()->>'my_submitted_total')::int as scale_count;

ROLLBACK;
