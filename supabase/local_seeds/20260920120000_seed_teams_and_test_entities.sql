-- ============================================================================
-- Migration: 20260920120000_seed_teams_and_test_entities.sql
-- Description:
--   Seeds minimum required organizational test entities and teams to satisfy
--   foreign key and consistency constraints expected by historical data repairs
--   in 20260921000005.
-- ============================================================================

-- 1. Ensure auth.users has webonant@gmail.com (id: 878d9145-7764-411f-8d26-f30f01e99e79)
-- required by profiles.id FK (REFERENCES auth.users(id)).
-- Using empty raw_user_meta_data '{}'::jsonb bypasses the interactive signup trigger.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = '878d9145-7764-411f-8d26-f30f01e99e79') THEN
    INSERT INTO auth.users (
      id,
      instance_id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at
    ) VALUES (
      '878d9145-7764-411f-8d26-f30f01e99e79',
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'webonant@gmail.com',
      extensions.crypt('Password123!', extensions.gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      now(),
      now()
    );
  END IF;
END $$;

-- 2. Ensure departments exist with exact UUIDs expected by migration 20260921000005
-- Update HSE / Safety to have id 'f0ad05aa-c85a-40e5-b309-19f1e6629e7a' if seeded with random uuid
DO $$
DECLARE
  v_existing_hse_id UUID;
BEGIN
  SELECT id INTO v_existing_hse_id FROM public.departments WHERE name = 'HSE / Safety';
  IF v_existing_hse_id IS NOT NULL AND v_existing_hse_id != 'f0ad05aa-c85a-40e5-b309-19f1e6629e7a' THEN
    -- Update existing row id
    UPDATE public.departments
    SET id = 'f0ad05aa-c85a-40e5-b309-19f1e6629e7a'
    WHERE id = v_existing_hse_id;
  ELSIF v_existing_hse_id IS NULL THEN
    INSERT INTO public.departments (id, name, code, division)
    VALUES ('f0ad05aa-c85a-40e5-b309-19f1e6629e7a', 'HSE / Safety', 'HSE', 'Operations & HSSE');
  END IF;
END $$;

-- Insert 'test dept'
INSERT INTO public.departments (id, name, code, division)
VALUES ('6000544e-dfe7-4911-b2cc-4c4bebead468', 'test dept', 'TEST-DEPT', 'Operations & HSSE')
ON CONFLICT (id) DO NOTHING;

-- 3. Ensure site 'test site' exists with id '6abf4ba5-e8b7-4076-8c97-80f4a354f94b'
INSERT INTO public.sites (id, name, code)
VALUES ('6abf4ba5-e8b7-4076-8c97-80f4a354f94b', 'test site', 'TEST-SITE')
ON CONFLICT (id) DO NOTHING;

-- 4. Ensure public.profiles has webonant@gmail.com with manager role
DO $$
DECLARE
  v_mgr_role_id UUID;
BEGIN
  SELECT id INTO v_mgr_role_id FROM public.roles WHERE code = 'manager' LIMIT 1;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = '878d9145-7764-411f-8d26-f30f01e99e79') THEN
    INSERT INTO public.profiles (
      id,
      full_name,
      email,
      designation,
      department_id,
      site_id,
      role_id,
      status,
      is_active
    ) VALUES (
      '878d9145-7764-411f-8d26-f30f01e99e79',
      'Operations Manager',
      'webonant@gmail.com',
      'HSE',
      'f0ad05aa-c85a-40e5-b309-19f1e6629e7a',
      '6abf4ba5-e8b7-4076-8c97-80f4a354f94b',
      v_mgr_role_id,
      'active',
      true
    );
  END IF;
END $$;

-- 5. Ensure public.teams has the expected teams for department 'f0ad05aa-c85a-40e5-b309-19f1e6629e7a'
INSERT INTO public.teams (id, department_id, name, code)
VALUES (
  '95c9b84e-c9e9-4838-babc-9f3171e36b9c',
  'f0ad05aa-c85a-40e5-b309-19f1e6629e7a',
  'Safety Inspection Team',
  'SIT'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.teams (id, department_id, name, code)
VALUES (
  '3e5465f5-a305-4356-a183-0abfa642d910',
  'f0ad05aa-c85a-40e5-b309-19f1e6629e7a',
  'HSE Emergency Response Team',
  'ERT'
) ON CONFLICT (id) DO NOTHING;

