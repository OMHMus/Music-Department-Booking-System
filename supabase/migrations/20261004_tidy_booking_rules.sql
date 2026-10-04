-- =====================================================================
-- Tidy-up after 20261004_harden_bookings.sql
-- STATUS: written 4 Oct 2026, NOT YET APPLIED to the live database.
-- =====================================================================
-- The live database already had most of those protections:
--   policies k_sel / k_ins / k_del, trigger validate_booking (approval,
--   weekdays, 28 days, closures, computer capacity), index one_room_booking,
--   trigger guard_profile, and the session/seats checks.
--
-- This removes the duplicates, and restores the original rule that pupils
-- can only cancel FUTURE bookings (the catch-all delete policy had widened it).
--
-- Kept, because they add something new:
--   * bookings_one_place_per_pupil  - a pupil can't hold two spaces in one session
--   * practice_check_booking        - can't book a session that has already started
--                                     today (UK time), now just that one check
--   * practice_protect_profile      - also blocks pupils inserting a profile
--                                     as staff/approved, and handles NULLs
-- =====================================================================
begin;

-- 1. Policies: the originals already do this job
drop policy if exists "practice: book for self when approved" on public.bookings;
drop policy if exists "practice: cancel own or staff"          on public.bookings;
drop policy if exists "practice: only staff edit bookings"     on public.bookings;
drop policy if exists "practice: see own bookings or staff"    on public.bookings;
drop policy if exists "practice: signed-in can insert"         on public.bookings;
drop policy if exists "practice: signed-in can delete"         on public.bookings;
drop policy if exists "practice: staff can update"             on public.bookings;

-- 2. Duplicate index and checks
drop index if exists public.bookings_one_per_room_session;   -- same as one_room_booking
alter table public.bookings drop constraint if exists bookings_valid_session;   -- same as bookings_session_check
alter table public.bookings drop constraint if exists bookings_seats_positive;  -- same as bookings_seats_check
alter table public.bookings drop constraint if exists bookings_weekday_only;    -- validate_booking already checks

-- 3. Booking trigger: keep only the new "session already started" rule
create or replace function public.practice_check_booking()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  today     date := (now() at time zone 'Europe/London')::date;
  now_local time := (now() at time zone 'Europe/London')::time;
  starts    time := case new.session when 'break' then time '11:05' else time '12:25' end;
begin
  if auth.uid() is null or public.practice_is_staff() then
    return new;
  end if;
  if new.booking_date < today or (new.booking_date = today and now_local >= starts) then
    raise exception 'That session has already started. Choose a later slot.';
  end if;
  return new;
end $$;

drop trigger if exists practice_check_booking on public.bookings;
create trigger practice_check_booking
  before insert on public.bookings
  for each row execute function public.practice_check_booking();

-- 4. No longer used
drop function if exists public.practice_can_book();

commit;
