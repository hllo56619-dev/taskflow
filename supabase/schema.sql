-- TaskFlow: run this entire file in Supabase Dashboard > SQL Editor.
-- Uses only the public/publishable client key plus Row Level Security (RLS).

create extension if not exists pgcrypto;

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 60),
  color text not null default '#64748b',
  position integer not null default 0,
  created_at timestamptz not null default now(),
  unique (user_id, name)
);

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 240),
  notes text not null default '',
  category_id uuid references public.categories(id) on delete set null,
  scheduled_date date,
  due_date date,
  priority text not null default 'normal' check (priority in ('low', 'normal', 'high')),
  is_completed boolean not null default false,
  completed_at timestamptz,
  position double precision not null default 0,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists tasks_user_schedule_idx
  on public.tasks (user_id, scheduled_date, position);
create index if not exists tasks_user_due_idx
  on public.tasks (user_id, due_date);
create index if not exists tasks_user_completed_idx
  on public.tasks (user_id, is_completed);
create index if not exists categories_user_position_idx
  on public.categories (user_id, position, name);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists tasks_set_updated_at on public.tasks;
create trigger tasks_set_updated_at
before update on public.tasks
for each row execute function public.set_updated_at();

alter table public.tasks enable row level security;
alter table public.categories enable row level security;

drop policy if exists "Users can read their own tasks" on public.tasks;
create policy "Users can read their own tasks"
  on public.tasks for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can create their own tasks" on public.tasks;
create policy "Users can create their own tasks"
  on public.tasks for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their own tasks" on public.tasks;
create policy "Users can update their own tasks"
  on public.tasks for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own tasks" on public.tasks;
create policy "Users can delete their own tasks"
  on public.tasks for delete to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can read their own categories" on public.categories;
create policy "Users can read their own categories"
  on public.categories for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can create their own categories" on public.categories;
create policy "Users can create their own categories"
  on public.categories for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their own categories" on public.categories;
create policy "Users can update their own categories"
  on public.categories for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own categories" on public.categories;
create policy "Users can delete their own categories"
  on public.categories for delete to authenticated
  using (auth.uid() = user_id);

-- Enable Realtime for the web dashboard. Android refreshes periodically as a fallback.
do $$
begin
  alter publication supabase_realtime add table public.tasks;
exception when duplicate_object then
  null;
when undefined_object then
  raise notice 'Publication supabase_realtime not found; Realtime can be enabled in the Supabase Dashboard.';
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.categories;
exception when duplicate_object then
  null;
when undefined_object then
  raise notice 'Publication supabase_realtime not found; Realtime can be enabled in the Supabase Dashboard.';
end;
$$;
