-- Supabase foundation for My University portal
-- Run this migration in the Supabase SQL Editor or with the Supabase CLI.

create extension if not exists pgcrypto;

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin')),
  created_at timestamptz not null default now()
);

create or replace function public.has_role(_user_id uuid, _role text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = _user_id and role = _role
  );
$$;

revoke all on function public.has_role(uuid, text) from public;
grant execute on function public.has_role(uuid, text) to authenticated;

create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  name_ar text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.lectures (
  id uuid primary key default gen_random_uuid(),
  subject_code text not null references public.subjects(code) on update cascade on delete cascade,
  title text not null,
  doctor text,
  duration text,
  summary_ar text,
  summary_en text,
  file_path text,
  sort_order integer not null default 0,
  published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.schedule_days (
  id uuid primary key default gen_random_uuid(),
  day_name text not null,
  group_name text not null default 'عام',
  day_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (day_name, group_name)
);

create table if not exists public.schedule_slots (
  id uuid primary key default gen_random_uuid(),
  day_id uuid not null references public.schedule_days(id) on delete cascade,
  start_time time,
  end_time time,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.schedule_items (
  id uuid primary key default gen_random_uuid(),
  slot_id uuid not null references public.schedule_slots(id) on delete cascade,
  subject text not null,
  doctor text,
  hall text,
  created_at timestamptz not null default now()
);

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.portal_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists subjects_set_updated_at on public.subjects;
create trigger subjects_set_updated_at before update on public.subjects
for each row execute function public.set_updated_at();

drop trigger if exists lectures_set_updated_at on public.lectures;
create trigger lectures_set_updated_at before update on public.lectures
for each row execute function public.set_updated_at();

drop trigger if exists announcements_set_updated_at on public.announcements;
create trigger announcements_set_updated_at before update on public.announcements
for each row execute function public.set_updated_at();

alter table public.user_roles enable row level security;
alter table public.subjects enable row level security;
alter table public.lectures enable row level security;
alter table public.schedule_days enable row level security;
alter table public.schedule_slots enable row level security;
alter table public.schedule_items enable row level security;
alter table public.announcements enable row level security;
alter table public.portal_settings enable row level security;

drop policy if exists "Users can read their own role" on public.user_roles;
create policy "Users can read their own role" on public.user_roles
for select to authenticated using (user_id = auth.uid() or public.has_role(auth.uid(), 'admin'));

drop policy if exists "Admins manage roles" on public.user_roles;
create policy "Admins manage roles" on public.user_roles
for all to authenticated using (public.has_role(auth.uid(), 'admin'))
with check (public.has_role(auth.uid(), 'admin'));

-- Public read access; only authenticated admins can change portal content.
drop policy if exists "Public read subjects" on public.subjects;
create policy "Public read subjects" on public.subjects for select to anon, authenticated using (true);
drop policy if exists "Admins manage subjects" on public.subjects;
create policy "Admins manage subjects" on public.subjects for all to authenticated
using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));

drop policy if exists "Public read published lectures" on public.lectures;
create policy "Public read published lectures" on public.lectures for select to anon, authenticated using (published = true or public.has_role(auth.uid(), 'admin'));
drop policy if exists "Admins manage lectures" on public.lectures;
create policy "Admins manage lectures" on public.lectures for all to authenticated
using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));

drop policy if exists "Public read schedule days" on public.schedule_days;
create policy "Public read schedule days" on public.schedule_days for select to anon, authenticated using (true);
drop policy if exists "Admins manage schedule days" on public.schedule_days;
create policy "Admins manage schedule days" on public.schedule_days for all to authenticated
using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));

drop policy if exists "Public read schedule slots" on public.schedule_slots;
create policy "Public read schedule slots" on public.schedule_slots for select to anon, authenticated using (true);
drop policy if exists "Admins manage schedule slots" on public.schedule_slots;
create policy "Admins manage schedule slots" on public.schedule_slots for all to authenticated
using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));

drop policy if exists "Public read schedule items" on public.schedule_items;
create policy "Public read schedule items" on public.schedule_items for select to anon, authenticated using (true);
drop policy if exists "Admins manage schedule items" on public.schedule_items;
create policy "Admins manage schedule items" on public.schedule_items for all to authenticated
using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));

drop policy if exists "Public read published announcements" on public.announcements;
create policy "Public read published announcements" on public.announcements for select to anon, authenticated using (published = true or public.has_role(auth.uid(), 'admin'));
drop policy if exists "Admins manage announcements" on public.announcements;
create policy "Admins manage announcements" on public.announcements for all to authenticated
using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));

drop policy if exists "Public read portal settings" on public.portal_settings;
create policy "Public read portal settings" on public.portal_settings for select to anon, authenticated using (true);
drop policy if exists "Admins manage portal settings" on public.portal_settings;
create policy "Admins manage portal settings" on public.portal_settings for all to authenticated
using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));


-- Explicit table grants; RLS policies above remain the authorization boundary.
grant select on public.subjects, public.lectures, public.schedule_days,
  public.schedule_slots, public.schedule_items, public.announcements,
  public.portal_settings to anon, authenticated;
grant select, insert, update, delete on public.subjects, public.lectures,
  public.schedule_days, public.schedule_slots, public.schedule_items,
  public.announcements, public.portal_settings to authenticated;
grant select, insert, update, delete on public.user_roles to authenticated;

-- Lecture PDFs are public to read; uploads, replacements and deletes require admin role.
insert into storage.buckets (id, name, public)
values ('lecture-files', 'lecture-files', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "Public can read lecture files" on storage.objects;
create policy "Public can read lecture files" on storage.objects
for select to anon, authenticated using (bucket_id = 'lecture-files');

drop policy if exists "Admins upload lecture files" on storage.objects;
create policy "Admins upload lecture files" on storage.objects
for insert to authenticated with check (
  bucket_id = 'lecture-files' and public.has_role(auth.uid(), 'admin')
);

drop policy if exists "Admins update lecture files" on storage.objects;
create policy "Admins update lecture files" on storage.objects
for update to authenticated using (
  bucket_id = 'lecture-files' and public.has_role(auth.uid(), 'admin')
) with check (
  bucket_id = 'lecture-files' and public.has_role(auth.uid(), 'admin')
);

drop policy if exists "Admins delete lecture files" on storage.objects;
create policy "Admins delete lecture files" on storage.objects
for delete to authenticated using (
  bucket_id = 'lecture-files' and public.has_role(auth.uid(), 'admin')
);
