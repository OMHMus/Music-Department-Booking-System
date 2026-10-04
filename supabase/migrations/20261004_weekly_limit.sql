-- =====================================================================
-- Weekly limit: pupils can book at most 3 sessions per school week
-- =====================================================================
-- STATUS: applied to the live database on 4 Oct 2026 (via Supabase connector)
--         SUPERSEDED for practice_check_booking by 20261004_exam_students.sql
--         and tested in a rolled-back transaction: 3 allowed, 4th blocked.
--
-- * A "week" is Monday to Sunday (bookings are weekdays only).
-- * Every booking counts as one session, including a Music Tech booking
--   for several computers and a booking made for a band (it counts for
--   the pupil who made it).
-- * Bookings already used earlier in the week still count, so cancelling
--   one that has happened can't free up another (pupils can only cancel
--   future bookings anyway).
-- * Staff are not limited.
--
-- Extends practice_check_booking (from 20261004_tidy_booking_rules.sql),
-- keeping its "session already started" rule unchanged.
-- =====================================================================

create or replace function public.practice_check_booking()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  weekly_limit constant int := 3;
  today     date := (now() at time zone 'Europe/London')::date;
  now_local time := (now() at time zone 'Europe/London')::time;
  starts    time := case new.session when 'break' then time '11:05' else time '12:25' end;
  wk_start  date := date_trunc('week', new.booking_date)::date;
  used      int;
begin
  if auth.uid() is null or public.practice_is_staff() then return new; end if;

  if new.booking_date < today or (new.booking_date = today and now_local >= starts) then
    raise exception 'That session has already started. Choose a later slot.';
  end if;

  -- One pupil's bookings are checked one at a time, so two quick clicks
  -- can't both squeeze in as the third booking
  perform pg_advisory_xact_lock(hashtext('weekly|' || new.user_id::text));
  select count(*) into used from public.bookings
   where user_id = new.user_id
     and booking_date between wk_start and wk_start + 6;
  if used >= weekly_limit then
    raise exception 'You have already booked % sessions in the week of %. The limit is % a week.',
      used, to_char(wk_start, 'FMDD FMMonth'), weekly_limit;
  end if;

  return new;
end $$;
