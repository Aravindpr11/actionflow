-- Migration: 20261025000001_create_calendar_tasks.sql
-- Description: Create dedicated calendar_tasks table for private, personal calendar items.
-- Strict Privacy Rules:
-- 1. auth.uid() = user_id for SELECT, INSERT, UPDATE, DELETE.
-- 2. Zero manager/admin bypass (managers cannot view other users' private personal calendar tasks).
-- 3. Isolated from official actions table and reports.

CREATE TABLE IF NOT EXISTS public.calendar_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    start_date TIMESTAMPTZ,
    due_date TIMESTAMPTZ NOT NULL,
    priority TEXT NOT NULL DEFAULT 'Medium' CHECK (priority IN ('Low', 'Medium', 'High', 'Critical')),
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Enable Row Level Security
ALTER TABLE public.calendar_tasks ENABLE ROW LEVEL SECURITY;

-- 1. SELECT: Users can only see their own personal tasks
DROP POLICY IF EXISTS "Users can view their own calendar tasks" ON public.calendar_tasks;
CREATE POLICY "Users can view their own calendar tasks"
    ON public.calendar_tasks FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

-- 2. INSERT: Users can only insert tasks for themselves
DROP POLICY IF EXISTS "Users can insert their own calendar tasks" ON public.calendar_tasks;
CREATE POLICY "Users can insert their own calendar tasks"
    ON public.calendar_tasks FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- 3. UPDATE: Users can only update their own tasks
DROP POLICY IF EXISTS "Users can update their own calendar tasks" ON public.calendar_tasks;
CREATE POLICY "Users can update their own calendar tasks"
    ON public.calendar_tasks FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 4. DELETE: Users can only delete their own tasks
DROP POLICY IF EXISTS "Users can delete their own calendar tasks" ON public.calendar_tasks;
CREATE POLICY "Users can delete their own calendar tasks"
    ON public.calendar_tasks FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- Index for efficient user-scoped queries and date ordering
CREATE INDEX IF NOT EXISTS idx_calendar_tasks_user_due_date 
    ON public.calendar_tasks(user_id, due_date ASC);

-- Permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON public.calendar_tasks TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.calendar_tasks TO service_role;

