-- =====================================================================
-- Sexey's Music Practice Rooms: harden bookings at the database level
-- =====================================================================
-- Adopts the best ideas from the earlier standalone script:
--   * double-booking is impossible in the database, not just in the page
--   * pupils can only book for themselves and only cancel their own
-- and adds what the live app needs on top:
--   * only approved pupils (or staff) can book
--   * no past dates, nothing more than 28 days ahead, weekdays only
--   * closures and the Music Tech computer capacity are enforced
--   * one place at a time: a pupil can't hold two rooms in the same session
--   * staff can cancel anyone's booking
--   * pupils can't make themselves staff or approve themselves
--
-- SAFE TO RE-RUN. It only ADDS rules. Existing policies are left alone;
-- the new ones are RESTRICTIVE, so they tighten whatever is already there
-- (Postgres ANDs restrictive policies with the existing permissive ones).
--
-- HOW TO RUN: Supabase dashboard -> SQL Editor -> paste all -> Run.
-- It runs as one transaction: if any step errors, nothing is changed.
-- Run STEP 0 on its own first if you want to see whether existing
-- bookings would clash with the new rules.
-- =====================================================================


-- ---------------------------------------------------------------------
-- STEP 0 (optional, read-only): look for existing clashes.
-- Any rows returned here are double-bookings already in the table.
-- Delete or fix them before running the rest, or step 2 will stop.
-- ---------------------------------------------------------------------
-- select resource_id, booking_date, session, count(*)
-- from public.bookings
-- where resource_id <> 'computers'
-- group by 1,2,3 having count(*) > 1;
--
-- select user_id, booking_date, session, count(*)
-- from public.bookings
-- group by 1,2,3 having count(*) > 1;


begin;  -- all-or-nothing: if anything fails, nothing is changed

-- ---------------------------------------------------------------------
-- 1. Helpers (security definer so they can read profiles under RLS)
-- ---------------------------------------------------------------------
create or replace function public.practice_is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'staff');
$$;

create or replace function public.practice_can_book()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and (role = 'staff' or (coalesce(approved, false) and not coalesce(rejected, false)))
  );
$$;

revoke all on function public.practice_is_staff() from public;
revoke all on function public.practice_can_book() from public;
grant execute on function public.practice_is_staff() to authenticated;
grant execute on function public.practice_can_book() to authenticated;


-- ---------------------------------------------------------------------
-- 2. No double-booking (the "no_overlap" idea, fitted to fixed sessions)
--    A room can hold one booking per session. The computer suite is the
--    exception: it is shared, so its capacity is checked in step 4.
--    A pupil can only be in one place per session.
-- ---------------------------------------------------------------------
create unique index if not exists bookings_one_per_room_session
  on public.bookings (resource_id, booking_date, session)
  where resource_id <> 'computers';

create unique index if not exists bookings_one_place_per_pupil
  on public.bookings (user_id, booking_date, session);


-- ---------------------------------------------------------------------
-- 3. Basic sanity checks (the "check (ends_at > starts_at)" idea)
--    NOT VALID = applies to new bookings only, so old rows can't block it.
-- ---------------------------------------------------------------------
do $$ begin
  alter table public.bookings add constraint bookings_valid_session
    check (session::text in ('break', 'lunch')) not valid;
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.bookings add constraint bookings_weekday_only
    check (extract(isodow from booking_date) between 1 and 5) not valid;
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.bookings add constraint bookings_seats_positive
    check (seats is null or seats >= 1) not valid;
exception when duplicate_object then null; end $$;


-- ---------------------------------------------------------------------
-- 4. Booking rules that depend on today's date, closures and capacity
-- ---------------------------------------------------------------------
create or replace function public.practice_check_booking()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  today      date := (now() at time zone 'Europe/London')::date;
  now_local  time := (now() at time zone 'Europe/London')::time;
  starts     time := case new.session::text when 'break' then time '11:05' else time '12:25' end;
  cap        int;
  used       int;
begin
  -- Staff and admin tools (SQL editor, service role) are not limited by these rules
  if auth.uid() is null or public.practice_is_staff() then
    return new;
  end if;

  if new.booking_date < today or (new.booking_date = today and now_local >= starts) then
    raise exception 'That session has already started. Choose a later slot.' using errcode = 'P0001';
  end if;

  if new.booking_date > today + 28 then
    raise exception 'You can only book up to 4 weeks ahead.' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.closures c
    where c.closure_date = new.booking_date
      and (c.resource_id is null or c.resource_id = new.resource_id)
      and (c.session is null or c.session::text = new.session::text)
  ) or exists (
    select 1 from public.weekly_closures w
    where w.weekday = extract(isodow from new.booking_date)
      and (w.resource_id is null or w.resource_id = new.resource_id)
      and (w.session is null or w.session::text = new.session::text)
  ) then
    raise exception 'That room is closed for this session.' using errcode = 'P0001';
  end if;

  if new.resource_id = 'computers' then
    -- Serialise bookings for this session so two pupils can't take the last place at once
    perform pg_advisory_xact_lock(hashtext('computers|' || new.booking_date || '|' || new.session::text));
    select capacity into cap from public.resources where id = 'computers';
    select coalesce(sum(seats), 0) into used from public.bookings
      where resource_id = 'computers' and booking_date = new.booking_date
        and session::text = new.session::text and id is distinct from new.id;
    if cap is not null and used + coalesce(new.seats, 1) > cap then
      raise exception 'Only % computer place(s) left for this session.', greatest(cap - used, 0) using errcode = 'P0001';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists practice_check_booking on public.bookings;
create trigger practice_check_booking
  before insert or update on public.bookings
  for each row execute function public.practice_check_booking();


-- ---------------------------------------------------------------------
-- 5. Row level security (the "book for self" / "cancel own" idea)
--    RESTRICTIVE policies narrow whatever permissive policies exist.
-- ---------------------------------------------------------------------
alter table public.bookings enable row level security;

drop policy if exists "practice: book for self when approved" on public.bookings;
create policy "practice: book for self when approved" on public.bookings
  as restrictive for insert to authenticated
  with check (public.practice_is_staff() or (user_id = auth.uid() and public.practice_can_book()));

drop policy if exists "practice: cancel own or staff" on public.bookings;
create policy "practice: cancel own or staff" on public.bookings
  as restrictive for delete to authenticated
  using (public.practice_is_staff() or user_id = auth.uid());

drop policy if exists "practice: only staff edit bookings" on public.bookings;
create policy "practice: only staff edit bookings" on public.bookings
  as restrictive for update to authenticated
  using (public.practice_is_staff());

-- Make sure the permissive side exists too, otherwise nobody could do anything
-- once RLS is on. (Harmless if equivalent policies already exist.)
drop policy if exists "practice: signed-in can insert" on public.bookings;
create policy "practice: signed-in can insert" on public.bookings
  for insert to authenticated with check (true);
drop policy if exists "practice: signed-in can delete" on public.bookings;
create policy "practice: signed-in can delete" on public.bookings
  for delete to authenticated using (true);
drop policy if exists "practice: staff can update" on public.bookings;
create policy "practice: staff can update" on public.bookings
  for update to authenticated using (public.practice_is_staff());

-- Privacy: pupils see only their own booking rows; the timetable shows
-- "Booked" via get_slots. Applied ONLY if get_slots is security definer,
-- otherwise the timetable would show other pupils' slots as free.
do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'get_slots' and p.prosecdef) then
    execute 'drop policy if exists "practice: see own bookings or staff" on public.bookings';
    execute 'create policy "practice: see own bookings or staff" on public.bookings
             as restrictive for select to authenticated
             using (public.practice_is_staff() or user_id = auth.uid())';
    raise notice 'Booking privacy policy applied.';
  else
    raise notice 'Skipped booking privacy policy: get_slots is not SECURITY DEFINER.';
  end if;
end $$;


-- ---------------------------------------------------------------------
-- 6. Stop pupils promoting or approving themselves
-- ---------------------------------------------------------------------
create or replace function public.practice_protect_profile()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.practice_is_staff() then
    return new;  -- staff, sign-up trigger and SQL editor are allowed
  end if;
  if tg_op = 'INSERT' then
    if new.role is distinct from 'pupil' or coalesce(new.approved, false) then
      raise exception 'Only staff can set roles or approvals.' using errcode = 'P0001';
    end if;
  elsif new.role is distinct from old.role
     or new.approved is distinct from old.approved
     or new.rejected is distinct from old.rejected then
    raise exception 'Only staff can change roles or approvals.' using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists practice_protect_profile on public.profiles;
create trigger practice_protect_profile
  before insert or update on public.profiles
  for each row execute function public.practice_protect_profile();

commit;
