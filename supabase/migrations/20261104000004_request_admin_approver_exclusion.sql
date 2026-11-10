-- =============================================================================
-- Migration 20261104000004: Request Management - Enforce Admin Approver Exclusion
-- =============================================================================
-- Ensures designated approvers cannot possess an Admin role, protecting
-- managerial workflow integrity and enforcing strict role boundaries.

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
    -- Reject invalid, inactive, or cross-organization designated approvers
    IF NOT EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = (v_appr->>'approver_id')::UUID
        AND p.organization_id = v_caller_profile.organization_id
        AND p.is_active = TRUE
    ) THEN
      RAISE EXCEPTION 'Designated approver is invalid, inactive, or belongs to a different organization.';
    END IF;

    -- Reject Admin-role designated approvers
    IF EXISTS (
      SELECT 1 FROM public.profiles p
      JOIN public.roles r ON p.role_id = r.id
      WHERE p.id = (v_appr->>'approver_id')::UUID
        AND (LOWER(r.name) LIKE '%admin%' OR LOWER(r.name) = 'admin' OR r.code = 'admin')
    ) THEN
      RAISE EXCEPTION 'Admin-role users cannot be designated as approvers.';
    END IF;

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
        COALESCE((v_att->>'file_size')::BIGINT, 0),
        v_att->>'content_type',
        v_caller_id
      );
    END LOOP;
  END IF;

  -- Initial history event
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
    jsonb_build_object(
      'title', p_title,
      'approval_type', p_approval_type,
      'approvers_count', jsonb_array_length(p_approvers),
      'attachments_count', COALESCE(jsonb_array_length(p_attachments), 0)
    )
  );

  RETURN jsonb_build_object(
    'id', v_new_req_id,
    'display_id', v_display_id,
    'status', 'Pending'
  );
END;
$$;

