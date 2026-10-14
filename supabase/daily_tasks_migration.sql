-- Run once in Supabase Dashboard > SQL Editor for an existing TaskFlow project.
alter table public.tasks
  add column if not exists is_daily boolean not null default false,
  add column if not exists daily_completed_on date;

-- Refresh PostgREST's schema cache so the API sees the new columns immediately.
notify pgrst, 'reload schema';
