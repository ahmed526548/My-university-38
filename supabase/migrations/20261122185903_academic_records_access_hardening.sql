create or replace function private.is_rostered_student(p_user_id uuid, p_student_code text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from private.student_roster sr
    where sr.auth_user_id = p_user_id
      and sr.student_code = p_student_code
      and sr.is_active = true
  );
$$;

drop policy if exists "Faculty and admins insert academic records" on public.academic_records;
create policy "Faculty and admins insert academic records"
on public.academic_records for insert to authenticated
with check (
  created_by = (select auth.uid())
  and private.can_manage_academic_subject(subject_code)
  and private.is_rostered_student(student_user_id, student_code)
);

drop policy if exists "Faculty and admins update academic records" on public.academic_records;
create policy "Faculty and admins update academic records"
on public.academic_records for update to authenticated
using (
  (created_by = (select auth.uid()) or private.is_portal_admin())
  and private.can_manage_academic_subject(subject_code)
)
with check (
  (created_by = (select auth.uid()) or private.is_portal_admin())
  and private.can_manage_academic_subject(subject_code)
  and private.is_rostered_student(student_user_id, student_code)
);

drop policy if exists "Faculty and admins delete academic records" on public.academic_records;
create policy "Faculty and admins delete academic records"
on public.academic_records for delete to authenticated
using (
  (created_by = (select auth.uid()) or private.is_portal_admin())
  and private.can_manage_academic_subject(subject_code)
);

revoke all on function private.is_rostered_student(uuid,text) from public, anon;
grant execute on function private.is_rostered_student(uuid,text) to authenticated;
