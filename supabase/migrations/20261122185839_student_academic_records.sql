-- Student academic records: manual grades linked to authenticated student accounts.
create table if not exists public.academic_records (
  id uuid primary key default gen_random_uuid(),
  student_user_id uuid not null references auth.users(id) on delete cascade,
  student_code text not null,
  student_name text not null,
  subject_code text not null references public.subjects(code) on update cascade on delete restrict,
  assessment_name text not null check (char_length(btrim(assessment_name)) between 2 and 160),
  assessment_type text not null default 'other' check (assessment_type in ('quiz','exam','assignment','midterm','final','participation','other')),
  grade numeric(7,2) not null check (grade >= 0),
  max_grade numeric(7,2) not null check (max_grade > 0 and grade <= max_grade),
  term text not null default 'الفصل الدراسي الأول' check (char_length(btrim(term)) between 2 and 80),
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists academic_records_student_idx on public.academic_records(student_user_id, created_at desc);
create index if not exists academic_records_subject_idx on public.academic_records(subject_code, created_at desc);
create index if not exists academic_records_creator_idx on public.academic_records(created_by, created_at desc);
alter table public.academic_records enable row level security;

create or replace function private.can_manage_academic_subject(p_subject_code text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select private.is_portal_admin()
    or exists (
      select 1 from public.faculty_accounts fa
      join public.faculty_directory fd on fd.id = fa.faculty_id
      where fa.user_id = (select auth.uid())
        and fd.is_active = true
        and p_subject_code = any(fd.subject_codes)
    );
$$;

create policy "Students read own academic records"
on public.academic_records for select to authenticated
using (student_user_id = (select auth.uid()));
create policy "Faculty and admins read managed academic records"
on public.academic_records for select to authenticated
using (private.can_manage_academic_subject(subject_code));
create policy "Faculty and admins insert academic records"
on public.academic_records for insert to authenticated
with check (
  created_by = (select auth.uid())
  and private.can_manage_academic_subject(subject_code)
  and exists (
    select 1 from private.student_roster sr
    where sr.auth_user_id = student_user_id
      and sr.student_code = academic_records.student_code
      and sr.is_active = true
  )
);
create policy "Faculty and admins update academic records"
on public.academic_records for update to authenticated
using (
  created_by = (select auth.uid())
  and private.can_manage_academic_subject(subject_code)
)
with check (
  created_by = (select auth.uid())
  and private.can_manage_academic_subject(subject_code)
  and exists (
    select 1 from private.student_roster sr
    where sr.auth_user_id = student_user_id
      and sr.student_code = academic_records.student_code
      and sr.is_active = true
  )
);
create policy "Faculty and admins delete academic records"
on public.academic_records for delete to authenticated
using (
  created_by = (select auth.uid())
  and private.can_manage_academic_subject(subject_code)
);

create or replace function public.faculty_resolve_student(p_student_code text, p_subject_code text)
returns table(student_user_id uuid, student_code text, student_name text, group_name text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if auth.uid() is null or not private.can_manage_academic_subject(p_subject_code) then
    raise exception 'غير مصرح لك بإضافة درجات لهذه المادة';
  end if;
  return query
  select sr.auth_user_id, sr.student_code, sr.full_name, sr.group_name
  from private.student_roster sr
  where sr.student_code = btrim(p_student_code)
    and sr.is_active = true
    and sr.auth_user_id is not null
  limit 1;
end;
$$;

create or replace function public.get_my_quiz_results()
returns table(
  task_id uuid, title text, subject_code text, kind text, doctor_name text,
  score numeric, max_score numeric, submitted_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select a.task_id, t.title, t.subject_code, t.kind, t.doctor_name, a.score, a.max_score, a.submitted_at
  from private.quiz_attempts a
  join public.student_tasks t on t.id = a.task_id
  where a.student_user_id = (select auth.uid())
  order by a.submitted_at desc;
$$;

revoke all on function private.can_manage_academic_subject(text) from public, anon;
grant execute on function private.can_manage_academic_subject(text) to authenticated;
revoke all on function public.faculty_resolve_student(text,text) from public, anon;
grant execute on function public.faculty_resolve_student(text,text) to authenticated;
revoke all on function public.get_my_quiz_results() from public, anon;
grant execute on function public.get_my_quiz_results() to authenticated;
grant select, insert, update, delete on public.academic_records to authenticated;
