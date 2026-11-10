-- =============================================================================
-- Migration: 20261104000006_request_dashboard_metrics_hardening.sql
-- Description:
--   Remediates Migration 20261104000005 authorization vulnerabilities in
--   dashboard request metrics aggregation RPCs:
--     1. get_manager_request_metrics:
--        - Drops old signature with client-supplied parameters: (BOOLEAN, UUID[], UUID[]).
--        - Implements hardened zero-parameter signature: public.get_manager_request_metrics().
--        - Derives Company Admin authority strictly from database role/profile records.
--        - Derives Department & Site supervisory scopes strictly from public.manager_scopes.
--        - Eliminates client parameter trust (no scope bypass or spoofing possible).
--     2. get_staff_request_metrics:
--        - Drops old signature with client-supplied parameter: (BOOLEAN).
--        - Implements hardened zero-parameter signature: public.get_staff_request_metrics().
--        - Derives approval authority strictly from public.request_approvers server-side.
--        - Enforces own-request privacy (created_by = auth.uid()).
--     3. Security & Execution Grants:
--        - Explicitly revokes EXECUTE from PUBLIC and anon.
--        - Grants EXECUTE strictly to authenticated.
--        - Search path set to public, auth, pg_temp.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Drop Insecure Previous Signatures (Idempotent)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_manager_request_metrics(BOOLEAN, UUID[], UUID[]);
DROP FUNCTION IF EXISTS public.get_staff_request_metrics(BOOLEAN);

-- -----------------------------------------------------------------------------
-- 2. Hardened Manager Request Metrics RPC (Zero Client Parameters)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_manager_request_metrics()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_profile public.profiles%ROWTYPE;
  v_org_id UUID;
  v_is_admin BOOLEAN := FALSE;
  v_is_manager BOOLEAN := FALSE;
  v_total INT := 0;
  v_under_review INT := 0;
  v_approved INT := 0;
  v_rejected INT := 0;
  v_completed INT := 0;
  v_pending_my_approval INT := 0;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_caller_profile
  FROM public.profiles
  WHERE id = v_caller_id;

  IF NOT FOUND OR v_caller_profile.is_active IS NOT TRUE THEN
    RAISE EXCEPTION 'Active profile not found for authenticated user.';
  END IF;

  v_org_id := v_caller_profile.organization_id;

  -- Verify administrative or managerial role strictly from trusted database records
  SELECT (r.code IN ('admin', 'company_admin', 'super_admin') OR v_caller_profile.is_primary_admin = TRUE),
         (r.code = 'manager')
  INTO v_is_admin, v_is_manager
  FROM public.roles r
  WHERE r.id = v_caller_profile.role_id;

  IF NOT v_is_admin AND NOT v_is_manager THEN
    RAISE EXCEPTION 'Access Denied: Caller does not possess manager or administrator authority.';
  END IF;

  -- 1. Aggregation of in-scope request counts:
  --    - Company Admin / Platform Admin receives full organization-wide aggregation.
  --    - Scoped Manager receives ONLY requests matching their active public.manager_scopes
  --      validated via public.is_manager_of_scope(r.department_id, r.site_id).
  --    - A manager without matching scopes receives 0 in-scope counts (no company-wide leak).
  --    - Excludes 'Draft' requests (unsubmitted drafts belong solely to the author).
  --    - Guarantees total = under_review + approved + rejected + completed.
  SELECT
    COALESCE(COUNT(*), 0),
    COALESCE(COUNT(*) FILTER (WHERE r.status IN ('Pending', 'Under Review')), 0),
    COALESCE(COUNT(*) FILTER (WHERE r.status = 'Approved'), 0),
    COALESCE(COUNT(*) FILTER (WHERE r.status = 'Rejected'), 0),
    COALESCE(COUNT(*) FILTER (WHERE r.status = 'Completed'), 0)
  INTO
    v_total,
    v_under_review,
    v_approved,
    v_rejected,
    v_completed
  FROM public.requests r
  WHERE r.organization_id = v_org_id
    AND r.status != 'Draft'
    AND (
      v_is_admin = TRUE
      OR (
        v_is_manager = TRUE
        AND public.is_manager_of_scope(r.department_id, r.site_id)
      )
    );

  -- 2. Aggregation of Pending My Approval:
  -- Counts distinct requests awaiting this manager's decision
  -- Respects sequential approval dependency and parallel sign-off
  SELECT COALESCE(COUNT(DISTINCT r.id), 0)
  INTO v_pending_my_approval
  FROM public.requests r
  JOIN public.request_approvers ra ON ra.request_id = r.id AND ra.approver_id = v_caller_id
  WHERE r.organization_id = v_org_id
    AND r.status IN ('Pending', 'Under Review')
    AND ra.status = 'Pending'
    AND (
      r.approval_type = 'Parallel'
      OR NOT EXISTS (
        SELECT 1
        FROM public.request_approvers prev
        WHERE prev.request_id = r.id
          AND prev.step_order < ra.step_order
          AND prev.status != 'Approved'
      )
    );

  RETURN jsonb_build_object(
    'total', v_total,
    'pending_my_approval', v_pending_my_approval,
    'under_review', v_under_review,
    'approved', v_approved,
    'rejected', v_rejected,
    'completed', v_completed
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 3. Hardened Staff Request Metrics RPC (Zero Client Parameters)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_staff_request_metrics()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_profile public.profiles%ROWTYPE;
  v_org_id UUID;
  v_is_designated_approver BOOLEAN := FALSE;
  v_my_submitted_total INT := 0;
  v_pending INT := 0;
  v_under_review INT := 0;
  v_approved INT := 0;
  v_rejected INT := 0;
  v_completed INT := 0;
  v_pending_my_approval INT := NULL;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_caller_profile
  FROM public.profiles
  WHERE id = v_caller_id;

  IF NOT FOUND OR v_caller_profile.is_active IS NOT TRUE THEN
    RAISE EXCEPTION 'Active profile not found for authenticated user.';
  END IF;

  v_org_id := v_caller_profile.organization_id;

  -- 1. Aggregation of Staff caller's own submitted requests strictly
  --    - Excludes unsubmitted 'Draft' requests (only submitted requests count).
  --    - Guarantees my_submitted_total = pending + under_review + approved + rejected + completed.
  SELECT
    COALESCE(COUNT(*), 0),
    COALESCE(COUNT(*) FILTER (WHERE r.status = 'Pending'), 0),
    COALESCE(COUNT(*) FILTER (WHERE r.status = 'Under Review'), 0),
    COALESCE(COUNT(*) FILTER (WHERE r.status = 'Approved'), 0),
    COALESCE(COUNT(*) FILTER (WHERE r.status = 'Rejected'), 0),
    COALESCE(COUNT(*) FILTER (WHERE r.status = 'Completed'), 0)
  INTO
    v_my_submitted_total,
    v_pending,
    v_under_review,
    v_approved,
    v_rejected,
    v_completed
  FROM public.requests r
  WHERE r.organization_id = v_org_id
    AND r.created_by = v_caller_id
    AND r.status != 'Draft';

  -- 2. Derive approval authority from database records:
  -- Only if caller is assigned as an approver in this organization do we calculate pending_my_approval.
  -- Otherwise, it remains NULL so the frontend does NOT display the card.
  SELECT EXISTS (
    SELECT 1 FROM public.request_approvers
    WHERE approver_id = v_caller_id
      AND organization_id = v_org_id
  ) INTO v_is_designated_approver;

  IF v_is_designated_approver THEN
    SELECT COALESCE(COUNT(DISTINCT r.id), 0)
    INTO v_pending_my_approval
    FROM public.requests r
    JOIN public.request_approvers ra ON ra.request_id = r.id AND ra.approver_id = v_caller_id
    WHERE r.organization_id = v_org_id
      AND r.status IN ('Pending', 'Under Review')
      AND ra.status = 'Pending'
      AND (
        r.approval_type = 'Parallel'
        OR NOT EXISTS (
          SELECT 1
          FROM public.request_approvers prev
          WHERE prev.request_id = r.id
            AND prev.step_order < ra.step_order
            AND prev.status != 'Approved'
        )
      );
  END IF;

  RETURN jsonb_build_object(
    'my_submitted_total', v_my_submitted_total,
    'pending_approval', v_pending,
    'under_review', v_under_review,
    'approved', v_approved,
    'rejected', v_rejected,
    'completed', v_completed,
    'pending_my_approval', v_pending_my_approval
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. Permissions & Grants
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.get_manager_request_metrics() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_manager_request_metrics() TO authenticated;

REVOKE ALL ON FUNCTION public.get_staff_request_metrics() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_staff_request_metrics() TO authenticated;

COMMIT;

