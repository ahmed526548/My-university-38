-- Explicitly deny anonymous Supabase sessions access to academic records and quiz results.
create or replace function private.can_manage_academic_subject(p_subject_code text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
    and (
      private.is_portal_admin()
      or exists (
        select 1 from public.faculty_accounts fa
        join public.faculty_directory fd on fd.id = fa.faculty_id
        where fa.user_id = (select auth.uid())
          and fd.is_active = true
          and p_subject_code = any(fd.subject_codes)
      )
    );
$$;

drop policy if exists "Students read own academic records" on public.academic_records;
create policy "Students read own academic records"
on public.academic_records for select to authenticated
using (
  coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  and student_user_id = (select auth.uid())
);

create or replace function public.get_my_quiz_results()
returns table(task_id uuid,title text,subject_code text,kind text,doctor_name text,score numeric,max_score numeric,submitted_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  select a.task_id,t.title,t.subject_code,t.kind,t.doctor_name,a.score,a.max_score,a.submitted_at
  from private.quiz_attempts a join public.student_tasks t on t.id=a.task_id
  where a.student_user_id=(select auth.uid())
    and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean,false)=false
  order by a.submitted_at desc;
$$;

revoke all on function private.can_manage_academic_subject(text) from public, anon;
grant execute on function private.can_manage_academic_subject(text) to authenticated;
revoke all on function public.get_my_quiz_results() from public, anon;
grant execute on function public.get_my_quiz_results() to authenticated;
