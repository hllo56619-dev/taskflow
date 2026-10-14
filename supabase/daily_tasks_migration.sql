-- Run once in Supabase Dashboard > SQL Editor for an existing TaskFlow project.
alter table public.tasks
  add column if not exists is_daily boolean not null default false,
  add column if not exists daily_completed_on date;
