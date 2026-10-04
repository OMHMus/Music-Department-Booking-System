-- =====================================================================
-- GCSE / A Level pupils: 4 sessions a week + unlimited computer bookings
-- =====================================================================
-- STATUS: applied to the live database on 4 Oct 2026 (via Supabase connector)
--         and tested in rolled-back transactions: 4 rooms then 5th blocked,
--         unlimited computers, pupil cannot change own course, staff can.
--
-- * New column profiles.exam_course: NULL (none), 'gcse' or 'a_level'.
--   Only staff can set or change it (enforced by practice_protect_profile).
-- * Weekly limits (Monday to Sunday):
--     - other pupils: 3 sessions, Music Tech computer bookings included
--     - GCSE / A Level: 4 practice-space sessions, and Music Tech computer
--       bookings don't count and aren't limited (validate_booking still
--       requires a purpose for computer bookings, e.g. "coursework")
-- * Staff remain unlimited.
-- * Replaces practice_check_booking from 20261004_weekly_limit.sql and
--   practice_protect_profile from 20261004_harden_bookings.sql.
-- =====================================================================

alter table public.profiles
  add column if not exists exam_course text;

do $$ begin
  alter table public.profiles add constraint profiles_exam_course_check
    check (exam_course in ('gcse', 'a_level'));
exception when duplicate_object then null; end $$;

comment on column public.profiles.exam_course is
  'GCSE or A Level music pupil (gcse / a_level), set by staff. Gives 4 sessions a week and unlimited Music Tech computer bookings.';


create or replace function public.practice_check_booking()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  today     date := (now() at time zone 'Europe/London')::date;
  now_local time := (now() at time zone 'Europe/London')::time;
  starts    time := case new.session when 'break' then time '11:05' else time '12:25' end;
  wk_start  date := date_trunc('week', new.booking_date)::date;
  exam      boolean;
  lim       int;
  used      int;
begin
  if auth.uid() is null or public.practice_is_staff() then return new; end if;

  if new.booking_date < today or (new.booking_date = today and now_local >= starts) then
    raise exception 'That session has already started. Choose a later slot.';
  end if;

  select exam_course is not null into exam from public.profiles where id = new.user_id;
  exam := coalesce(exam, false);

  -- GCSE / A Level: computer bookings are unlimited and don't count
  if exam and new.resource_id = 'computers' then return new; end if;

  lim := case when exam then 4 else 3 end;

  perform pg_advisory_xact_lock(hashtext('weekly|' || new.user_id::text));
  select count(*) into used from public.bookings
   where user_id = new.user_id
     and booking_date between wk_start and wk_start + 6
     and (not exam or resource_id <> 'computers');
  if used >= lim then
    raise exception 'You have already booked % sessions in the week of %. The limit is % a week.',
      used, to_char(wk_start, 'FMDD FMMonth'), lim;
  end if;

  return new;
end $$;


create or replace function public.practice_protect_profile()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.practice_is_staff() then
    return new;  -- staff, sign-up trigger and SQL editor are allowed
  end if;
  if tg_op = 'INSERT' then
    if new.role is distinct from 'pupil' or coalesce(new.approved, false) or new.exam_course is not null then
      raise exception 'Only staff can set roles, approvals or exam courses.' using errcode = 'P0001';
    end if;
  elsif new.role is distinct from old.role
     or new.approved is distinct from old.approved
     or new.rejected is distinct from old.rejected
     or new.exam_course is distinct from old.exam_course then
    raise exception 'Only staff can change roles, approvals or exam courses.' using errcode = 'P0001';
  end if;
  return new;
end $$;
