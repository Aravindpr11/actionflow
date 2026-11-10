-- ============================================================================
-- Migration: 20261104000001_request_management_and_approval_workflow.sql
-- Description:
--   Complete enterprise Request Management and Multi-level Approval Workflow
--   for ActionFlow Manager Portal and Staff Portal.
--   Supports:
--     1. Requests (PTW, Equipment, Material, Access, Other).
--     2. Multi-level Approvers (Sequential & Parallel).
--     3. Audit trail (request_history).
--     4. Request Attachments & Document Linking.
--     5. Forwarding without duplicate requests.
--     6. Atomic stored procedures for submission, approval, forwarding, completion.
--     7. Strict multi-tenant organization isolation and RLS policies.
-- ============================================================================

-- 1. Sequence for Request Display IDs (REQ-1001, REQ-1002, ...)
CREATE SEQUENCE IF NOT EXISTS public.request_display_id_seq START WITH 1001;

-- 2. Table: public.requests
CREATE TABLE IF NOT EXISTS public.requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  display_id VARCHAR(50) UNIQUE NOT NULL,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  title VARCHAR(255) NOT NULL,
  description TEXT NOT NULL,
  request_type VARCHAR(50) NOT NULL,
  priority VARCHAR(50) NOT NULL DEFAULT 'Medium',
  department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
  department_name VARCHAR(150),
  site_id UUID REFERENCES public.sites(id) ON DELETE SET NULL,
  site_name VARCHAR(150),
  required_by_date DATE NOT NULL,
  required_by_time VARCHAR(20),
  approval_type VARCHAR(50) NOT NULL DEFAULT 'Sequential',
  status VARCHAR(50) NOT NULL DEFAULT 'Pending',
  created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_by_name VARCHAR(150) NOT NULL,
  created_by_role VARCHAR(50) NOT NULL,
  created_by_email VARCHAR(255),
  additional_notes TEXT,
  rejection_reason TEXT,
  rejected_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  rejected_at TIMESTAMPTZ,
  approved_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  completed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_request_type CHECK (
    request_type IN ('Permit to Work (PTW)', 'Equipment', 'Material', 'Access', 'Other')
  ),
  CONSTRAINT chk_request_priority CHECK (
    priority IN ('Low', 'Medium', 'High', 'Critical')
  ),
  CONSTRAINT chk_request_approval_type CHECK (
    approval_type IN ('Sequential', 'Parallel')
  ),
  CONSTRAINT chk_request_status CHECK (
    status IN ('Draft', 'Pending', 'Under Review', 'Approved', 'Rejected', 'Completed')
  )
);

CREATE INDEX IF NOT EXISTS idx_requests_org ON public.requests(organization_id);
CREATE INDEX IF NOT EXISTS idx_requests_created_by ON public.requests(created_by);
CREATE INDEX IF NOT EXISTS idx_requests_status ON public.requests(status);
CREATE INDEX IF NOT EXISTS idx_requests_dept ON public.requests(department_id);
CREATE INDEX IF NOT EXISTS idx_requests_site ON public.requests(site_id);
CREATE INDEX IF NOT EXISTS idx_requests_created_at ON public.requests(created_at DESC);

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_requests_updated_at ON public.requests;
CREATE TRIGGER trg_requests_updated_at
  BEFORE UPDATE ON public.requests
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_updated_at();

-- 3. Table: public.request_approvers
CREATE TABLE IF NOT EXISTS public.request_approvers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES public.requests(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  approver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  approver_name VARCHAR(150) NOT NULL,
  approver_role VARCHAR(50) NOT NULL,
  approver_department VARCHAR(150),
  step_order INT NOT NULL DEFAULT 1,
  status VARCHAR(50) NOT NULL DEFAULT 'Pending',
  decision_comments TEXT,
  decided_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_request_approver UNIQUE (request_id, approver_id),
  CONSTRAINT chk_approver_status CHECK (
    status IN ('Pending', 'Approved', 'Rejected')
  )
);

CREATE INDEX IF NOT EXISTS idx_request_approvers_req ON public.request_approvers(request_id);
CREATE INDEX IF NOT EXISTS idx_request_approvers_user ON public.request_approvers(approver_id);
CREATE INDEX IF NOT EXISTS idx_request_approvers_org ON public.request_approvers(organization_id);

-- 4. Table: public.request_attachments
CREATE TABLE IF NOT EXISTS public.request_attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES public.requests(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  file_name VARCHAR(255) NOT NULL,
  file_path TEXT NOT NULL,
  file_size INT NOT NULL,
  content_type VARCHAR(100),
  uploaded_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_request_attachments_req ON public.request_attachments(request_id);

-- 5. Table: public.request_forwards
CREATE TABLE IF NOT EXISTS public.request_forwards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES public.requests(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  from_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  from_user_name VARCHAR(150) NOT NULL,
  to_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  to_user_name VARCHAR(150) NOT NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_request_forwards_req ON public.request_forwards(request_id);
CREATE INDEX IF NOT EXISTS idx_request_forwards_to ON public.request_forwards(to_user_id);

-- 6. Table: public.request_history
CREATE TABLE IF NOT EXISTS public.request_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES public.requests(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  actor_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  actor_name VARCHAR(150) NOT NULL,
  actor_role VARCHAR(50) NOT NULL,
  action VARCHAR(50) NOT NULL,
  details TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_request_history_req ON public.request_history(request_id, created_at ASC);

-- 7. Stored Procedure: submit_new_request
CREATE OR REPLACE FUNCTION public.submit_new_request(
  p_title VARCHAR(255),
  p_description TEXT,
  p_request_type VARCHAR(50),
  p_priority VARCHAR(50),
  p_department_id UUID,
  p_department_name VARCHAR(150),
  p_site_id UUID,
  p_site_name VARCHAR(150),
  p_required_by_date DATE,
  p_required_by_time VARCHAR(20),
  p_approval_type VARCHAR(50),
  p_additional_notes TEXT,
  p_approvers JSONB,
  p_attachments JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_profile public.profiles%ROWTYPE;
  v_caller_role VARCHAR(50);
  v_new_req_id UUID;
  v_display_id VARCHAR(50);
  v_appr JSONB;
  v_att JSONB;
  v_step INT := 1;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_caller_profile
  FROM public.profiles
  WHERE id = v_caller_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found for authenticated user.';
  END IF;

  SELECT r.name INTO v_caller_role
  FROM public.roles r
  WHERE r.id = v_caller_profile.role_id;

  -- Generate display ID
  v_display_id := 'REQ-' || LPAD(nextval('public.request_display_id_seq')::text, 4, '0');

  INSERT INTO public.requests (
    display_id,
    organization_id,
    title,
    description,
    request_type,
    priority,
    department_id,
    department_name,
    site_id,
    site_name,
    required_by_date,
    required_by_time,
    approval_type,
    status,
    created_by,
    created_by_name,
    created_by_role,
    created_by_email,
    additional_notes
  ) VALUES (
    v_display_id,
    v_caller_profile.organization_id,
    p_title,
    p_description,
    p_request_type,
    p_priority,
    p_department_id,
    p_department_name,
    p_site_id,
    p_site_name,
    p_required_by_date,
    p_required_by_time,
    p_approval_type,
    'Pending',
    v_caller_id,
    v_caller_profile.full_name,
    COALESCE(v_caller_role, 'Staff'),
    v_caller_profile.email,
    p_additional_notes
  ) RETURNING id INTO v_new_req_id;

  -- Insert approvers
  IF jsonb_array_length(p_approvers) = 0 THEN
    RAISE EXCEPTION 'At least one approver must be designated.';
  END IF;

  FOR v_appr IN SELECT * FROM jsonb_array_elements(p_approvers)
  LOOP
    INSERT INTO public.request_approvers (
      request_id,
      organization_id,
      approver_id,
      approver_name,
      approver_role,
      approver_department,
      step_order,
      status
    ) VALUES (
      v_new_req_id,
      v_caller_profile.organization_id,
      (v_appr->>'approver_id')::UUID,
      v_appr->>'approver_name',
      v_appr->>'approver_role',
      v_appr->>'approver_department',
      COALESCE((v_appr->>'step_order')::INT, v_step),
      'Pending'
    );
    v_step := v_step + 1;
  END LOOP;

  -- Insert attachments if provided
  IF p_attachments IS NOT NULL AND jsonb_array_length(p_attachments) > 0 THEN
    FOR v_att IN SELECT * FROM jsonb_array_elements(p_attachments)
    LOOP
      INSERT INTO public.request_attachments (
        request_id,
        organization_id,
        file_name,
        file_path,
        file_size,
        content_type,
        uploaded_by
      ) VALUES (
        v_new_req_id,
        v_caller_profile.organization_id,
        v_att->>'file_name',
        v_att->>'file_path',
        (v_att->>'file_size')::INT,
        v_att->>'content_type',
        v_caller_id
      );
    END LOOP;
  END IF;

  -- Record submission in history
  INSERT INTO public.request_history (
    request_id,
    organization_id,
    actor_id,
    actor_name,
    actor_role,
    action,
    details
  ) VALUES (
    v_new_req_id,
    v_caller_profile.organization_id,
    v_caller_id,
    v_caller_profile.full_name,
    COALESCE(v_caller_role, 'Staff'),
    'Submitted',
    'Request submitted with ' || jsonb_array_length(p_approvers)::text || ' designated approver(s).'
  );

  RETURN jsonb_build_object(
    'success', true,
    'id', v_new_req_id,
    'display_id', v_display_id
  );
END;
$$;

-- 8. Stored Procedure: record_request_approval_decision
CREATE OR REPLACE FUNCTION public.record_request_approval_decision(
  p_request_id UUID,
  p_decision VARCHAR(50),
  p_comments TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_profile public.profiles%ROWTYPE;
  v_caller_role VARCHAR(50);
  v_req public.requests%ROWTYPE;
  v_appr public.request_approvers%ROWTYPE;
  v_prior_pending INT;
  v_all_approved BOOLEAN;
  v_decision_upper VARCHAR(50);
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  v_decision_upper := INITCAP(TRIM(p_decision));
  IF v_decision_upper NOT IN ('Approved', 'Rejected') THEN
    RAISE EXCEPTION 'Decision must be either Approved or Rejected.';
  END IF;

  IF v_decision_upper = 'Rejected' AND (p_comments IS NULL OR length(trim(p_comments)) = 0) THEN
    RAISE EXCEPTION 'A rejection reason is required.';
  END IF;

  SELECT * INTO v_req FROM public.requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found.';
  END IF;

  IF v_req.status IN ('Approved', 'Rejected', 'Completed') THEN
    RAISE EXCEPTION 'Cannot record decision on a request with status: %', v_req.status;
  END IF;

  -- Caller must be designated approver
  SELECT * INTO v_appr
  FROM public.request_approvers
  WHERE request_id = p_request_id AND approver_id = v_caller_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Access Denied: You are not a designated approver for this request.';
  END IF;

  IF v_appr.status != 'Pending' THEN
    RAISE EXCEPTION 'You have already recorded your decision (%) for this request.', v_appr.status;
  END IF;

  -- If Sequential, verify that all previous steps are Approved
  IF v_req.approval_type = 'Sequential' THEN
    SELECT COUNT(*) INTO v_prior_pending
    FROM public.request_approvers
    WHERE request_id = p_request_id
      AND step_order < v_appr.step_order
      AND status != 'Approved';

    IF v_prior_pending > 0 THEN
      RAISE EXCEPTION 'Sequential approval violation: Previous approval steps are still pending.';
    END IF;
  END IF;

  SELECT * INTO v_caller_profile FROM public.profiles WHERE id = v_caller_id;
  SELECT r.name INTO v_caller_role FROM public.roles r WHERE r.id = v_caller_profile.role_id;

  -- Record decision
  UPDATE public.request_approvers
  SET status = v_decision_upper,
      decision_comments = p_comments,
      decided_at = now()
  WHERE id = v_appr.id;

  IF v_decision_upper = 'Rejected' THEN
    UPDATE public.requests
    SET status = 'Rejected',
        rejection_reason = p_comments,
        rejected_by = v_caller_id,
        rejected_at = now(),
        updated_at = now()
    WHERE id = p_request_id;

    INSERT INTO public.request_history (
      request_id, organization_id, actor_id, actor_name, actor_role, action, details
    ) VALUES (
      p_request_id, v_req.organization_id, v_caller_id, v_caller_profile.full_name,
      COALESCE(v_caller_role, 'Approver'), 'Rejected',
      'Request rejected: ' || p_comments
    );
  ELSE
    -- Approved: Check if all required approvers have approved
    SELECT NOT EXISTS (
      SELECT 1 FROM public.request_approvers
      WHERE request_id = p_request_id AND status != 'Approved'
    ) INTO v_all_approved;

    IF v_all_approved THEN
      UPDATE public.requests
      SET status = 'Approved',
          approved_at = now(),
          updated_at = now()
      WHERE id = p_request_id;

      INSERT INTO public.request_history (
        request_id, organization_id, actor_id, actor_name, actor_role, action, details
      ) VALUES (
        p_request_id, v_req.organization_id, v_caller_id, v_caller_profile.full_name,
        COALESCE(v_caller_role, 'Approver'), 'Approved',
        'Final approval granted.' || CASE WHEN length(trim(p_comments)) > 0 THEN ' Comments: ' || p_comments ELSE '' END
      );
    ELSE
      UPDATE public.requests
      SET status = 'Under Review',
          updated_at = now()
      WHERE id = p_request_id;

      INSERT INTO public.request_history (
        request_id, organization_id, actor_id, actor_name, actor_role, action, details
      ) VALUES (
        p_request_id, v_req.organization_id, v_caller_id, v_caller_profile.full_name,
        COALESCE(v_caller_role, 'Approver'), 'Approved Step',
        'Approval step completed.' || CASE WHEN length(trim(p_comments)) > 0 THEN ' Comments: ' || p_comments ELSE '' END
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'decision', v_decision_upper,
    'request_status', (SELECT status FROM public.requests WHERE id = p_request_id)
  );
END;
$$;

-- 9. Stored Procedure: forward_request
CREATE OR REPLACE FUNCTION public.forward_request(
  p_request_id UUID,
  p_to_user_id UUID,
  p_notes TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_profile public.profiles%ROWTYPE;
  v_caller_role VARCHAR(50);
  v_recipient_profile public.profiles%ROWTYPE;
  v_req public.requests%ROWTYPE;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_req FROM public.requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found.';
  END IF;

  SELECT * INTO v_caller_profile FROM public.profiles WHERE id = v_caller_id;
  SELECT r.name INTO v_caller_role FROM public.roles r WHERE r.id = v_caller_profile.role_id;

  SELECT * INTO v_recipient_profile FROM public.profiles WHERE id = p_to_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recipient user profile not found.';
  END IF;

  IF v_recipient_profile.organization_id != v_req.organization_id THEN
    RAISE EXCEPTION 'Cross-organization forwarding is prohibited.';
  END IF;

  INSERT INTO public.request_forwards (
    request_id,
    organization_id,
    from_user_id,
    from_user_name,
    to_user_id,
    to_user_name,
    notes
  ) VALUES (
    p_request_id,
    v_req.organization_id,
    v_caller_id,
    v_caller_profile.full_name,
    p_to_user_id,
    v_recipient_profile.full_name,
    p_notes
  );

  INSERT INTO public.request_history (
    request_id,
    organization_id,
    actor_id,
    actor_name,
    actor_role,
    action,
    details
  ) VALUES (
    p_request_id,
    v_req.organization_id,
    v_caller_id,
    v_caller_profile.full_name,
    COALESCE(v_caller_role, 'User'),
    'Forwarded',
    'Forwarded to ' || v_recipient_profile.full_name || '.' || CASE WHEN length(trim(p_notes)) > 0 THEN ' Notes: ' || p_notes ELSE '' END
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 10. Stored Procedure: complete_request
CREATE OR REPLACE FUNCTION public.complete_request(
  p_request_id UUID,
  p_notes TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_profile public.profiles%ROWTYPE;
  v_caller_role VARCHAR(50);
  v_req public.requests%ROWTYPE;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_req FROM public.requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found.';
  END IF;

  IF v_req.status != 'Approved' THEN
    RAISE EXCEPTION 'Only Approved requests can be marked as Completed. Current status: %', v_req.status;
  END IF;

  SELECT * INTO v_caller_profile FROM public.profiles WHERE id = v_caller_id;
  SELECT r.name INTO v_caller_role FROM public.roles r WHERE r.id = v_caller_profile.role_id;

  UPDATE public.requests
  SET status = 'Completed',
      completed_at = now(),
      completed_by = v_caller_id,
      updated_at = now()
  WHERE id = p_request_id;

  INSERT INTO public.request_history (
    request_id,
    organization_id,
    actor_id,
    actor_name,
    actor_role,
    action,
    details
  ) VALUES (
    p_request_id,
    v_req.organization_id,
    v_caller_id,
    v_caller_profile.full_name,
    COALESCE(v_caller_role, 'User'),
    'Completed',
    'Work marked as Completed.' || CASE WHEN length(trim(p_notes)) > 0 THEN ' Notes: ' || p_notes ELSE '' END
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 11. Enable Row Level Security (RLS) on all tables
ALTER TABLE public.requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.request_approvers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.request_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.request_forwards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.request_history ENABLE ROW LEVEL SECURITY;

-- 12. RLS Policies for requests
DROP POLICY IF EXISTS "Requests multi-tenant select policy" ON public.requests;
CREATE POLICY "Requests multi-tenant select policy"
  ON public.requests FOR SELECT TO authenticated
  USING (
    organization_id = (SELECT organization_id FROM public.profiles WHERE id = auth.uid())
    AND (
      created_by = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.request_approvers
        WHERE request_id = requests.id AND approver_id = auth.uid()
      )
      OR EXISTS (
        SELECT 1 FROM public.request_forwards
        WHERE request_id = requests.id AND to_user_id = auth.uid()
      )
      OR (
        -- Managers and Admins in the same organization can view operational requests
        EXISTS (
          SELECT 1 FROM public.profiles p
          JOIN public.roles r ON p.role_id = r.id
          WHERE p.id = auth.uid() AND r.code IN ('manager', 'admin')
        )
      )
    )
  );

DROP POLICY IF EXISTS "Requests insert policy" ON public.requests;
CREATE POLICY "Requests insert policy"
  ON public.requests FOR INSERT TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND organization_id = (SELECT organization_id FROM public.profiles WHERE id = auth.uid())
  );

-- 13. RLS Policies for request_approvers
DROP POLICY IF EXISTS "Request approvers select policy" ON public.request_approvers;
CREATE POLICY "Request approvers select policy"
  ON public.request_approvers FOR SELECT TO authenticated
  USING (
    organization_id = (SELECT organization_id FROM public.profiles WHERE id = auth.uid())
  );

-- 14. RLS Policies for request_attachments
DROP POLICY IF EXISTS "Request attachments select policy" ON public.request_attachments;
CREATE POLICY "Request attachments select policy"
  ON public.request_attachments FOR SELECT TO authenticated
  USING (
    organization_id = (SELECT organization_id FROM public.profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "Request attachments insert policy" ON public.request_attachments;
CREATE POLICY "Request attachments insert policy"
  ON public.request_attachments FOR INSERT TO authenticated
  WITH CHECK (
    organization_id = (SELECT organization_id FROM public.profiles WHERE id = auth.uid())
  );

-- 15. RLS Policies for request_forwards
DROP POLICY IF EXISTS "Request forwards select policy" ON public.request_forwards;
CREATE POLICY "Request forwards select policy"
  ON public.request_forwards FOR SELECT TO authenticated
  USING (
    organization_id = (SELECT organization_id FROM public.profiles WHERE id = auth.uid())
  );

-- 16. RLS Policies for request_history
DROP POLICY IF EXISTS "Request history select policy" ON public.request_history;
CREATE POLICY "Request history select policy"
  ON public.request_history FOR SELECT TO authenticated
  USING (
    organization_id = (SELECT organization_id FROM public.profiles WHERE id = auth.uid())
  );

-- 17. Permissions & Grants
GRANT SELECT, INSERT, UPDATE ON public.requests TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.request_approvers TO authenticated;
GRANT SELECT, INSERT ON public.request_attachments TO authenticated;
GRANT SELECT, INSERT ON public.request_forwards TO authenticated;
GRANT SELECT, INSERT ON public.request_history TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.request_display_id_seq TO authenticated;

GRANT EXECUTE ON FUNCTION public.submit_new_request(
  VARCHAR, TEXT, VARCHAR, VARCHAR, UUID, VARCHAR, UUID, VARCHAR, DATE, VARCHAR, VARCHAR, TEXT, JSONB, JSONB
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.record_request_approval_decision(
  UUID, VARCHAR, TEXT
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.forward_request(
  UUID, UUID, TEXT
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.complete_request(
  UUID, TEXT
) TO authenticated;

