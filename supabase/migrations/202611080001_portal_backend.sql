-- BSNU Portal: secure Supabase foundation
-- Public users can read published content. Only authenticated users listed in
-- portal_admins can create, update, or delete site content.
create extension if not exists pgcrypto;

create table if not exists public.portal_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_portal_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.portal_admins a
    where a.user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_portal_admin() from public;
grant execute on function public.is_portal_admin() to anon, authenticated;

create table if not exists public.lectures (
  id uuid primary key default gen_random_uuid(),
  subject_code text not null,
  title text not null,
  instructor text,
  duration text,
  summary_ar text not null default '',
  summary_en text not null default '',
  file_path text,
  sort_order integer not null default 0,
  is_published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.schedule_days (
  id uuid primary key default gen_random_uuid(),
  day_name text not null unique,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.schedule_entries (
  id uuid primary key default gen_random_uuid(),
  day_id uuid not null references public.schedule_days(id) on delete cascade,
  start_time text not null,
  subject text not null,
  instructor text,
  location text,
  group_name text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  announcement_type text not null default 'info',
  published_at timestamptz not null default now(),
  is_published boolean not null default true
);

alter table public.portal_admins enable row level security;
alter table public.lectures enable row level security;
alter table public.schedule_days enable row level security;
alter table public.schedule_entries enable row level security;
alter table public.announcements enable row level security;

drop policy if exists "Admins can read admin list" on public.portal_admins;
create policy "Admins can read admin list" on public.portal_admins
for select to authenticated using (user_id = (select auth.uid()) or public.is_portal_admin());

drop policy if exists "Published lectures are public" on public.lectures;
create policy "Published lectures are public" on public.lectures
for select to anon, authenticated using (is_published or public.is_portal_admin());
drop policy if exists "Admins manage lectures" on public.lectures;
create policy "Admins manage lectures" on public.lectures
for all to authenticated using (public.is_portal_admin()) with check (public.is_portal_admin());

drop policy if exists "Schedule days are public" on public.schedule_days;
create policy "Schedule days are public" on public.schedule_days
for select to anon, authenticated using (true);
drop policy if exists "Admins manage schedule days" on public.schedule_days;
create policy "Admins manage schedule days" on public.schedule_days
for all to authenticated using (public.is_portal_admin()) with check (public.is_portal_admin());

drop policy if exists "Schedule entries are public" on public.schedule_entries;
create policy "Schedule entries are public" on public.schedule_entries
for select to anon, authenticated using (true);
drop policy if exists "Admins manage schedule entries" on public.schedule_entries;
create policy "Admins manage schedule entries" on public.schedule_entries
for all to authenticated using (public.is_portal_admin()) with check (public.is_portal_admin());

drop policy if exists "Published announcements are public" on public.announcements;
create policy "Published announcements are public" on public.announcements
for select to anon, authenticated using (is_published or public.is_portal_admin());
drop policy if exists "Admins manage announcements" on public.announcements;
create policy "Admins manage announcements" on public.announcements
for all to authenticated using (public.is_portal_admin()) with check (public.is_portal_admin());

-- Public read bucket for lecture documents; writes are restricted to admins.
insert into storage.buckets (id, name, public)
values ('lecture-files', 'lecture-files', true)
on conflict (id) do update set public = true;

drop policy if exists "Public can read lecture files" on storage.objects;
create policy "Public can read lecture files" on storage.objects
for select to anon, authenticated using (bucket_id = 'lecture-files');

drop policy if exists "Admins upload lecture files" on storage.objects;
create policy "Admins upload lecture files" on storage.objects
for insert to authenticated with check (bucket_id = 'lecture-files' and public.is_portal_admin());

drop policy if exists "Admins update lecture files" on storage.objects;
create policy "Admins update lecture files" on storage.objects
for update to authenticated using (bucket_id = 'lecture-files' and public.is_portal_admin())
with check (bucket_id = 'lecture-files' and public.is_portal_admin());

drop policy if exists "Admins delete lecture files" on storage.objects;
create policy "Admins delete lecture files" on storage.objects
for delete to authenticated using (bucket_id = 'lecture-files' and public.is_portal_admin());
