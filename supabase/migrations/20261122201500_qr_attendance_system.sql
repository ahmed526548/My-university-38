-- QR attendance system: sessions use short-lived rotating token hashes.
create table if not exists public.attendance_sessions (
 id uuid primary key default gen_random_uuid(),
 created_by uuid not null references auth.users(id) on delete cascade,
 subject_code text not null references public.subjects(code) on update cascade,
 title text not null,
 group_name text,
 started_at timestamptz not null default now(),
 ends_at timestamptz not null,
 token_hash bytea,
 token_expires_at timestamptz,
 is_active boolean not null default true,
 ended_at timestamptz,
 created_at timestamptz not null default now(),
 constraint attendance_session_duration_check check (ends_at > started_at)
);
create table if not exists public.attendance_records (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.attendance_sessions(id) on delete cascade,
 student_user_id uuid not null references auth.users(id) on delete cascade,
 student_code text not null,
 student_name text not null,
 group_name text,
 attended_at timestamptz not null default now(),
 unique(session_id,student_user_id)
);
create index if not exists attendance_sessions_creator_idx on public.attendance_sessions(created_by,started_at desc);
create index if not exists attendance_sessions_subject_idx on public.attendance_sessions(subject_code,started_at desc);
create index if not exists attendance_records_session_idx on public.attendance_records(session_id,attended_at desc);
create index if not exists attendance_records_student_idx on public.attendance_records(student_user_id,attended_at desc);
alter table public.attendance_sessions enable row level security;
alter table public.attendance_records enable row level security;
revoke all on public.attendance_sessions from anon,public;
revoke all on public.attendance_records from anon,public;
grant select on public.attendance_sessions to authenticated;
grant select on public.attendance_records to authenticated;
drop policy if exists "Faculty read own attendance sessions" on public.attendance_sessions;
create policy "Faculty read own attendance sessions" on public.attendance_sessions for select to authenticated using(created_by=(select auth.uid()) or (select private.is_portal_admin()));
drop policy if exists "Students read own attendance records" on public.attendance_records;
create policy "Students read own attendance records" on public.attendance_records for select to authenticated using(student_user_id=(select auth.uid()));
drop policy if exists "Faculty read attendance for own sessions" on public.attendance_records;
create policy "Faculty read attendance for own sessions" on public.attendance_records for select to authenticated using(exists(select 1 from public.attendance_sessions s where s.id=attendance_records.session_id and (s.created_by=(select auth.uid()) or (select private.is_portal_admin()))));

create or replace function public.faculty_start_attendance(p_subject_code text,p_title text,p_group_name text default null,p_duration_minutes integer default 120)
returns table(session_id uuid,qr_token text,token_expires_at timestamptz,ends_at timestamptz)
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_token text; v_session_id uuid; v_end timestamptz;
begin
 if v_uid is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'يجب تسجيل الدخول بحساب جامعي حقيقي.'; end if;
 if coalesce(length(trim(p_title)),0)<3 or length(trim(p_title))>120 then raise exception 'اكتب اسمًا واضحًا للمحاضرة.'; end if;
 if p_duration_minutes<10 or p_duration_minutes>240 then raise exception 'مدة المحاضرة يجب أن تكون بين 10 و240 دقيقة.'; end if;
 if not exists(select 1 from public.subjects s where s.code=p_subject_code) then raise exception 'المادة المختارة غير موجودة.'; end if;
 if not (select private.is_portal_admin()) and not exists(select 1 from public.faculty_accounts fa join public.faculty_directory fd on fd.id=fa.faculty_id where fa.user_id=v_uid and fd.is_active=true and p_subject_code=any(fd.subject_codes)) then raise exception 'ليس لديك صلاحية تسجيل الحضور لهذه المادة.'; end if;
 if nullif(trim(coalesce(p_group_name,'')),'') is not null and length(trim(p_group_name))>80 then raise exception 'اسم المجموعة أطول من المسموح.'; end if;
 v_token:=encode(extensions.gen_random_bytes(32),'hex'); v_end:=now()+make_interval(mins=>p_duration_minutes);
 insert into public.attendance_sessions(created_by,subject_code,title,group_name,ends_at,token_hash,token_expires_at)
 values(v_uid,p_subject_code,trim(p_title),nullif(trim(coalesce(p_group_name,'')),''),v_end,extensions.digest(v_token,'sha256'),now()+interval '25 seconds') returning id into v_session_id;
 return query select v_session_id,v_token,now()+interval '25 seconds',v_end;
end $$;

create or replace function public.faculty_rotate_attendance_token(p_session_id uuid)
returns table(qr_token text,token_expires_at timestamptz)
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_token text; v_session public.attendance_sessions%rowtype;
begin
 if v_uid is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'يجب تسجيل الدخول بحساب جامعي حقيقي.'; end if;
 select * into v_session from public.attendance_sessions s where s.id=p_session_id and (s.created_by=v_uid or (select private.is_portal_admin())) for update;
 if not found then raise exception 'المحاضرة غير موجودة أو لا تملك صلاحية إدارتها.'; end if;
 if not v_session.is_active or v_session.ends_at<=now() then raise exception 'جلسة الحضور انتهت بالفعل.'; end if;
 v_token:=encode(extensions.gen_random_bytes(32),'hex');
 update public.attendance_sessions set token_hash=extensions.digest(v_token,'sha256'),token_expires_at=now()+interval '25 seconds' where id=p_session_id;
 return query select v_token,now()+interval '25 seconds';
end $$;

create or replace function public.faculty_end_attendance(p_session_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid());
begin
 if v_uid is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'يجب تسجيل الدخول بحساب جامعي حقيقي.'; end if;
 update public.attendance_sessions set is_active=false,ended_at=now(),token_hash=null,token_expires_at=null where id=p_session_id and (created_by=v_uid or (select private.is_portal_admin()));
 if not found then raise exception 'الجلسة غير موجودة أو لا تملك صلاحية إنهائها.'; end if; return true;
end $$;

create or replace function public.student_checkin_attendance(p_session_id uuid,p_token text)
returns table(session_title text,subject_code text,attended_at timestamptz,student_name text,student_code text)
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_student record; v_session public.attendance_sessions%rowtype; v_attended timestamptz;
begin
 if v_uid is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'سجل الدخول بحساب الطالب أولاً.'; end if;
 if p_token is null or length(p_token)<32 or length(p_token)>128 then raise exception 'رمز الحضور غير صالح.'; end if;
 select sr.student_code,sr.full_name,sr.group_name into v_student from private.student_roster sr where sr.auth_user_id=v_uid and sr.is_active=true limit 1;
 if not found then raise exception 'هذا الحساب غير مربوط بسجل طالب نشط.'; end if;
 select * into v_session from public.attendance_sessions s where s.id=p_session_id and s.is_active=true and s.ends_at>now() and s.token_expires_at>now() and s.token_hash=extensions.digest(p_token,'sha256') for update;
 if not found then raise exception 'رمز QR انتهت صلاحيته أو تم تغييره. امسح الرمز الظاهر حاليًا.'; end if;
 if v_session.group_name is not null and v_session.group_name<>v_student.group_name then raise exception 'هذه المحاضرة مخصصة لمجموعة أخرى.'; end if;
 insert into public.attendance_records(session_id,student_user_id,student_code,student_name,group_name) values(p_session_id,v_uid,v_student.student_code,v_student.full_name,v_student.group_name) on conflict(session_id,student_user_id) do nothing returning attendance_records.attended_at into v_attended;
 if v_attended is null then raise exception 'تم تسجيل حضورك بالفعل في هذه المحاضرة.'; end if;
 return query select v_session.title,v_session.subject_code,v_attended,v_student.full_name,v_student.student_code;
end $$;

create or replace function public.student_my_attendance()
returns table(attendance_id uuid,session_id uuid,session_title text,subject_code text,group_name text,attended_at timestamptz,session_started_at timestamptz,session_ended_at timestamptz)
language sql stable security definer set search_path=''
as $$
 select ar.id,s.id,s.title,s.subject_code,s.group_name,ar.attended_at,s.started_at,coalesce(s.ended_at,s.ends_at)
 from public.attendance_records ar join public.attendance_sessions s on s.id=ar.session_id
 where ar.student_user_id=(select auth.uid()) and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
 order by ar.attended_at desc limit 200;
$$;
revoke all on function public.faculty_start_attendance(text,text,text,integer) from public,anon;
revoke all on function public.faculty_rotate_attendance_token(uuid) from public,anon;
revoke all on function public.faculty_end_attendance(uuid) from public,anon;
revoke all on function public.student_checkin_attendance(uuid,text) from public,anon;
revoke all on function public.student_my_attendance() from public,anon;
grant execute on function public.faculty_start_attendance(text,text,text,integer) to authenticated;
grant execute on function public.faculty_rotate_attendance_token(uuid) to authenticated;
grant execute on function public.faculty_end_attendance(uuid) to authenticated;
grant execute on function public.student_checkin_attendance(uuid,text) to authenticated;
grant execute on function public.student_my_attendance() to authenticated;
