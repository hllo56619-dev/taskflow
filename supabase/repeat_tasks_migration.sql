-- TaskFlow: add a remaining-completions counter to existing tasks.
-- Run this once in Supabase Dashboard > SQL Editor.
alter table public.tasks
  add column if not exists repeat_enabled boolean not null default false,
  add column if not exists repeat_total integer not null default 1,
  add column if not exists repeat_remaining integer not null default 1;

alter table public.tasks
  drop constraint if exists tasks_repeat_total_check,
  drop constraint if exists tasks_repeat_remaining_check;

alter table public.tasks
  add constraint tasks_repeat_total_check check (repeat_total >= 1),
  add constraint tasks_repeat_remaining_check check (repeat_remaining >= 0);

notify pgrst, 'reload schema';
