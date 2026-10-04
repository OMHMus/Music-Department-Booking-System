-- =====================================================================
-- Bands made of individual, approved pupil accounts
-- =====================================================================
-- STATUS: applied to the live database on 4 Oct 2026 (via SQL Editor) and tested
--         in rolled-back transactions with temporary pupils: invites, accept,
--         ready check, band booking limits and clashes, permissions, delete.
--
-- Why: one pupil used to register a whole band, so only that pupil had
-- agreed to the Practice Room Agreement. Now:
--   * every pupil registers individually (and is approved by staff)
--   * an approved pupil creates a band and invites band-mates by school email
--   * each band-mate accepts from their own account (they must be approved)
--   * a band is READY when it has 2+ members, all accepted and approved
--   * only a ready band can book; an individual booking is for that pupil only
--   * a band booking uses one session of EVERY member's weekly allowance,
--     and no member may already be booked in that session
--   * bands can't book the Music Tech computers (those are individual)
--
-- All band changes go through the functions below (security definer);
-- pupils can no longer write to bands / band_members directly.
-- Replaces practice_check_booking from 20261004_exam_students.sql and
-- get_slots from the original schema. Contains no DROP statements.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Membership rows: one per pupil per band (the lead included)
-- ---------------------------------------------------------------------
alter table public.band_members add column if not exists user_id uuid references public.profiles(id) on delete cascade;
alter table public.band_members add column if not exists email text;
alter table public.band_members add column if not exists status text not null default 'invited';
alter table public.band_members add column if not exists invited_at timestamptz not null default now();
alter table public.band_members add column if not exists responded_at timestamptz;
alter table public.bands add column if not exists created_at timestamptz not null default now();

do $$ begin
  alter table public.band_members add constraint band_members_status_check
    check (status in ('invited', 'accepted', 'declined'));
exception when duplicate_object then null; end $$;

create unique index if not exists band_members_one_per_email
  on public.band_members (band_id, lower(email));
create index if not exists band_members_user_idx on public.band_members (user_id);


-- Pupils change bands only through the functions below (restrictive = staff-only direct writes)
do $$
declare t text; c text; n text;
begin
  foreach t in array array['bands', 'band_members'] loop
    foreach c in array array['insert', 'update', 'delete'] loop
      n := format('practice: %s staff-only %s', t, c);
      if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = n) then
        if c = 'insert' then
          execute format('create policy %I on public.%I as restrictive for insert to authenticated with check (public.is_staff())', n, t);
        else
          execute format('create policy %I on public.%I as restrictive for %s to authenticated using (public.is_staff())', n, t, c);
        end if;
      end if;
    end loop;
  end loop;
end $$;

revoke all on public.bands, public.band_members from anon;


-- ---------------------------------------------------------------------
-- 2. Helpers
-- ---------------------------------------------------------------------
create or replace function public.practice_my_band_ids()
returns setof bigint language sql stable security definer set search_path = public as $$
  select band_id from public.band_members where user_id = auth.uid() and status = 'accepted';
$$;

create or replace function public.practice_band_ready(p_band bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select count(*) >= 2
     and coalesce(bool_and(coalesce(m.status = 'accepted' and p.id is not null and p.approved and not p.rejected, false)), false)
  from public.band_members m
  left join public.profiles p on p.id = m.user_id
  where m.band_id = p_band and m.status <> 'declined';
$$;

-- Sessions a pupil has used in the week containing p_date (own + band bookings)
create or replace function public.practice_week_used(p_user uuid, p_date date)
returns int language sql stable security definer set search_path = public as $$
  select count(distinct b.id)::int
  from public.bookings b
  where b.booking_date between date_trunc('week', p_date)::date and date_trunc('week', p_date)::date + 6
    and (b.user_id = p_user
         or b.band_id in (select band_id from public.band_members where user_id = p_user and status = 'accepted'))
    and (b.resource_id <> 'computers'
         or not exists (select 1 from public.profiles where id = p_user and exam_course is not null));
$$;

create or replace function public.practice_week_limit(p_user uuid)
returns int language sql stable security definer set search_path = public as $$
  select case when exists (select 1 from public.profiles where id = p_user and exam_course is not null) then 4 else 3 end;
$$;

-- For the app's weekly counter
create or replace function public.my_week_usage(p_date date)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('used', public.practice_week_used(auth.uid(), p_date),
                           'limit', public.practice_week_limit(auth.uid()));
$$;


-- ---------------------------------------------------------------------
-- 3. Band actions
-- ---------------------------------------------------------------------
create or replace function public.band_create(p_name text, p_instrument text)
returns bigint language plpgsql security definer set search_path = public as $$
declare me public.profiles; bid bigint;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null or not me.approved or me.rejected then
    raise exception 'Your account must be approved before you can create a band.';
  end if;
  p_name := btrim(coalesce(p_name, ''));
  if length(p_name) < 2 or length(p_name) > 40 then
    raise exception 'Band names must be between 2 and 40 characters.';
  end if;
  if (select count(*) from public.bands where lead_id = me.id) >= 5 then
    raise exception 'You can lead up to 5 bands.';
  end if;
  insert into public.bands(name, lead_id) values (p_name, me.id) returning id into bid;
  insert into public.band_members(band_id, user_id, email, member_name, instrument, status, responded_at)
    values (bid, me.id, lower(me.email), coalesce(nullif(me.full_name, ''), me.email), nullif(btrim(p_instrument), ''), 'accepted', now());
  return bid;
end $$;

create or replace function public.band_invite(p_band bigint, p_email text, p_instrument text)
returns json language plpgsql security definer set search_path = public as $$
declare e text := lower(btrim(coalesce(p_email, ''))); target public.profiles; existing public.band_members;
begin
  if not exists (select 1 from public.bands where id = p_band and lead_id = auth.uid()) then
    raise exception 'Only the band leader can invite members.';
  end if;
  if e !~ '^[^@\s]+@sexeys\.somerset\.sch\.uk$' then
    raise exception 'Invite band-mates using their @sexeys.somerset.sch.uk school email.';
  end if;
  if (select count(*) from public.band_members where band_id = p_band and status <> 'declined') >= 8 then
    raise exception 'A band can have up to 8 members.';
  end if;
  select * into target from public.profiles where lower(email) = e;
  if target.role = 'staff' then raise exception 'Staff can''t be added to bands.'; end if;
  select * into existing from public.band_members where band_id = p_band and lower(email) = e;
  if existing.id is not null and existing.status <> 'declined' then
    raise exception 'That pupil is already in this band or has already been invited.';
  end if;
  if existing.id is not null then
    update public.band_members set status = 'invited', invited_at = now(), responded_at = null,
           user_id = target.id, member_name = coalesce(nullif(target.full_name, ''), e), instrument = nullif(btrim(p_instrument), '') where id = existing.id;
  else
    insert into public.band_members(band_id, user_id, email, member_name, instrument, status)
      values (p_band, target.id, e, coalesce(nullif(target.full_name, ''), e), nullif(btrim(p_instrument), ''), 'invited');
  end if;
  return json_build_object('has_account', target.id is not null,
                           'approved', coalesce(target.approved and not target.rejected, false));
end $$;

create or replace function public.band_respond(p_band bigint, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare me public.profiles; m public.band_members;
begin
  select * into me from public.profiles where id = auth.uid();
  select * into m from public.band_members
   where band_id = p_band and status = 'invited' and (user_id = me.id or lower(email) = lower(me.email));
  if m.id is null then raise exception 'That invitation is no longer available.'; end if;
  if p_accept and (not me.approved or me.rejected) then
    raise exception 'You can accept once a member of staff has approved your account.';
  end if;
  update public.band_members
     set status = case when p_accept then 'accepted' else 'declined' end,
         user_id = me.id, member_name = coalesce(nullif(me.full_name, ''), m.member_name), responded_at = now()
   where id = m.id;
end $$;

-- Leader removes a member, or a member leaves
create or replace function public.band_remove(p_member bigint)
returns void language plpgsql security definer set search_path = public as $$
declare m public.band_members; lead uuid;
begin
  select * into m from public.band_members where id = p_member;
  if m.id is null then return; end if;
  select lead_id into lead from public.bands where id = m.band_id;
  if m.user_id = lead then raise exception 'The leader can''t leave. Delete the band instead.'; end if;
  if not (auth.uid() = lead or auth.uid() = m.user_id or public.is_staff()) then
    raise exception 'Only the band leader can remove members.';
  end if;
  delete from public.band_members where id = p_member;
end $$;

-- Leader deletes the band; its upcoming bookings are cancelled
create or replace function public.band_delete(p_band bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.bands where id = p_band and (lead_id = auth.uid() or public.is_staff())) then
    raise exception 'Only the band leader can delete the band.';
  end if;
  delete from public.bookings where band_id = p_band and booking_date >= (now() at time zone 'Europe/London')::date;
  update public.bookings set band_id = null where band_id = p_band;  -- past bookings stay as the leader's
  delete from public.band_members where band_id = p_band;
  delete from public.bands where id = p_band;
end $$;

-- Everything the "My bands" tab needs
create or replace function public.my_bands()
returns json language sql stable security definer set search_path = public as $$
  with me as (select * from public.profiles where id = auth.uid()),
  mine as (
    select distinct m.band_id from public.band_members m, me
    where (m.user_id = me.id or lower(m.email) = lower(me.email)) and m.status <> 'declined'
  )
  select coalesce(json_agg(json_build_object(
    'id', b.id, 'name', b.name,
    'is_lead', b.lead_id = (select id from me),
    'lead_name', (select full_name from public.profiles where id = b.lead_id),
    'my_status', (select m.status from public.band_members m, me where m.band_id = b.id
                   and (m.user_id = me.id or lower(m.email) = lower(me.email)) limit 1),
    'ready', public.practice_band_ready(b.id),
    'members', (select json_agg(json_build_object(
        'id', m.id, 'name', coalesce(p.full_name, m.member_name), 'email', m.email,
        'instrument', m.instrument, 'status', m.status, 'is_lead', m.user_id = b.lead_id,
        'has_account', p.id is not null, 'approved', coalesce(p.approved and not p.rejected, false))
        order by (m.user_id = b.lead_id) desc, m.invited_at)
      from public.band_members m
      left join public.profiles p on p.id = coalesce(m.user_id, (select id from public.profiles where lower(email) = lower(m.email) limit 1))
      where m.band_id = b.id and m.status <> 'declined')
  ) order by b.name), '[]'::json)
  from public.bands b where b.id in (select band_id from mine);
$$;

-- Staff overview of every band
create or replace function public.staff_bands()
returns json language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'Staff only.'; end if;
  return (select coalesce(json_agg(json_build_object(
    'id', b.id, 'name', b.name, 'ready', public.practice_band_ready(b.id),
    'lead_name', (select full_name from public.profiles where id = b.lead_id),
    'members', (select json_agg(json_build_object('name', coalesce(p.full_name, m.member_name, m.email),
        'instrument', m.instrument, 'status', m.status, 'has_account', p.id is not null,
        'approved', coalesce(p.approved and not p.rejected, false)) order by m.invited_at)
      from public.band_members m left join public.profiles p on p.id = m.user_id
      where m.band_id = b.id and m.status <> 'declined')) order by b.name), '[]'::json)
    from public.bands b);
end $$;


-- ---------------------------------------------------------------------
-- 4. Booking rules (replaces practice_check_booking)
-- ---------------------------------------------------------------------
create or replace function public.practice_check_booking()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  today     date := (now() at time zone 'Europe/London')::date;
  now_local time := (now() at time zone 'Europe/London')::time;
  starts    time := case new.session when 'break' then time '11:05' else time '12:25' end;
  mem record;
begin
  if auth.uid() is null or public.is_staff() then return new; end if;

  if new.booking_date < today or (new.booking_date = today and now_local >= starts) then
    raise exception 'That session has already started. Choose a later slot.';
  end if;

  if new.band_id is null then
    -- Individual booking: for this pupil only
    perform pg_advisory_xact_lock(hashtext('weekly|' || new.user_id::text));
    if exists (select 1 from public.bookings b
               where b.booking_date = new.booking_date and b.session = new.session
                 and b.band_id in (select band_id from public.band_members where user_id = new.user_id and status = 'accepted')) then
      raise exception 'You already have a band booking in that session.';
    end if;
    if new.resource_id = 'computers'
       and exists (select 1 from public.profiles where id = new.user_id and exam_course is not null) then
      return new;  -- GCSE / A Level: unlimited computer bookings
    end if;
    if public.practice_week_used(new.user_id, new.booking_date) >= public.practice_week_limit(new.user_id) then
      raise exception 'You have already booked % sessions in the week of %. The limit is % a week.',
        public.practice_week_used(new.user_id, new.booking_date),
        to_char(date_trunc('week', new.booking_date), 'FMDD FMMonth'), public.practice_week_limit(new.user_id);
    end if;
    return new;
  end if;

  -- Band booking
  if new.resource_id = 'computers' then
    raise exception 'The Music Tech computers are booked individually, not as a band.';
  end if;
  if not exists (select 1 from public.band_members where band_id = new.band_id and user_id = new.user_id and status = 'accepted') then
    raise exception 'You can only book for a band you are a member of.';
  end if;
  if not public.practice_band_ready(new.band_id) then
    raise exception 'This band can''t book yet: every member needs an approved account and must accept the invitation.';
  end if;

  -- Lock every member (in a fixed order) so their limits can't be raced
  for mem in select m.user_id from public.band_members m
             where m.band_id = new.band_id and m.status = 'accepted' order by m.user_id loop
    perform pg_advisory_xact_lock(hashtext('weekly|' || mem.user_id::text));
  end loop;

  for mem in select m.user_id, p.full_name from public.band_members m join public.profiles p on p.id = m.user_id
             where m.band_id = new.band_id and m.status = 'accepted' loop
    if exists (select 1 from public.bookings b
               where b.booking_date = new.booking_date and b.session = new.session
                 and (b.user_id = mem.user_id
                      or b.band_id in (select band_id from public.band_members where user_id = mem.user_id and status = 'accepted'))) then
      raise exception '% already has a booking in that session.', mem.full_name;
    end if;
    if public.practice_week_used(mem.user_id, new.booking_date) >= public.practice_week_limit(mem.user_id) then
      raise exception '% has already used all % of their sessions in the week of %.',
        mem.full_name, public.practice_week_limit(mem.user_id), to_char(date_trunc('week', new.booking_date), 'FMDD FMMonth');
    end if;
  end loop;

  return new;
end $$;


-- ---------------------------------------------------------------------
-- 5. Band-mates see band bookings as theirs
-- ---------------------------------------------------------------------
create or replace function public.get_slots(d1 date, d2 date)
returns table(resource_id text, booking_date date, session text, seats integer, mine boolean)
language sql stable security definer set search_path = public as $$
  select b.resource_id, b.booking_date, b.session, b.seats,
         (b.user_id = auth.uid() or b.band_id in (select public.practice_my_band_ids()))
  from public.bookings b
  where b.booking_date between d1 and d2 and auth.uid() is not null;
$$;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'bookings'
                 and policyname = 'practice: band members see band bookings') then
    create policy "practice: band members see band bookings" on public.bookings
      for select to authenticated using (band_id in (select public.practice_my_band_ids()));
  end if;
end $$;


-- ---------------------------------------------------------------------
-- 6. Who can call what
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'practice_my_band_ids()', 'practice_band_ready(bigint)', 'practice_week_used(uuid, date)',
    'practice_week_limit(uuid)', 'my_week_usage(date)', 'band_create(text, text)',
    'band_invite(bigint, text, text)', 'band_respond(bigint, boolean)', 'band_remove(bigint)',
    'band_delete(bigint)', 'my_bands()', 'staff_bands()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
