-- =====================================================================
-- Foyer display board (display.html)
-- =====================================================================
-- STATUS: applied to the live database on 4 Oct 2026 (via Supabase connector).
--
-- The foyer TV is not logged in, and RLS rightly hides bookings from
-- anonymous visitors. Instead of loosening RLS, the TV calls one
-- SECURITY DEFINER function, display_board(), with a secret screen key
-- that is kept only in the TV's URL (never in this public repo).
--
-- * display_screens: one row per screen; only a SHA-256 hash of the key
--   is stored. last_seen is updated on every refresh so staff can check
--   a screen is alive:  select name, last_seen from display_screens;
-- * display_board(key, date) returns, for one school day (today .. +7):
--   rooms, closures and who is booked, as first name + surname initial
--   (or band name). No emails, no user ids, no purposes except staff ones.
--
-- Add a screen (SQL editor), then open  .../display.html?key=<the key>
--   insert into public.display_screens (name, token_hash)
--   values ('Foyer TV', encode(sha256(convert_to('<long random key>','UTF8')),'hex'));
-- Revoke a screen:  delete from public.display_screens where name = 'Foyer TV';
-- =====================================================================

create table if not exists public.display_screens (
  id         bigint generated always as identity primary key,
  name       text not null,
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  last_seen  timestamptz
);

alter table public.display_screens enable row level security;

drop policy if exists ds_stf on public.display_screens;
create policy ds_stf on public.display_screens
  for all to authenticated using (public.is_staff()) with check (public.is_staff());


create or replace function public.display_board(p_key text, p_date date default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Europe/London')::date;
  d     date := coalesce(p_date, today);
  wd    int  := extract(isodow from coalesce(p_date, today));
  scr   bigint;
begin
  update public.display_screens set last_seen = now()
   where token_hash = encode(sha256(convert_to(coalesce(p_key, ''), 'UTF8')), 'hex')
   returning id into scr;
  if scr is null then
    raise exception 'Unknown display key' using errcode = '28000';
  end if;
  if d < today or d > today + 7 then
    raise exception 'Date out of range' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'date', d,
    'generated_at', now(),
    'resources', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', r.id, 'name', r.name, 'capacity', r.capacity) order by r.sort, r.id), '[]')
      from public.resources r),
    'slots', (select coalesce(jsonb_agg(jsonb_build_object(
        'resource_id', r.id,
        'session', s.session,
        'closed', cl.closed,
        'reason', cl.reason,
        'seats', coalesce(bk.seats, 0),
        'who', coalesce(bk.who, '[]'::jsonb))), '[]')
      from public.resources r
      cross join (values ('break'), ('lunch')) s(session)
      cross join lateral (
        select (wd > 5
             or exists (select 1 from public.weekly_closures w
                         where (w.resource_id is null or w.resource_id = r.id)
                           and w.weekday = wd
                           and (w.session is null or w.session = s.session))
             or exists (select 1 from public.closures c
                         where (c.resource_id is null or c.resource_id = r.id)
                           and c.closure_date = d
                           and (c.session is null or c.session = s.session))) as closed,
               (select c.reason from public.closures c
                 where (c.resource_id is null or c.resource_id = r.id)
                   and c.closure_date = d
                   and (c.session is null or c.session = s.session)
                 order by c.id limit 1) as reason
      ) cl
      left join lateral (
        select sum(b.seats)::int as seats,
               jsonb_agg(jsonb_build_object(
                 'name', case
                   when b.band_id is not null and bd.name is not null then bd.name
                   when p.role = 'staff' then coalesce(nullif(trim(b.purpose), ''), 'Staff booking')
                   when coalesce(trim(p.full_name), '') = '' then 'Booked'
                   when position(' ' in trim(p.full_name)) = 0 then trim(p.full_name)
                   else split_part(trim(p.full_name), ' ', 1) || ' ' ||
                        left(regexp_replace(trim(p.full_name), '^.*\s', ''), 1) || '.'
                 end,
                 'band', b.band_id is not null,
                 'staff', p.role = 'staff',
                 'year', case when p.role = 'staff' then null else p.year_group end,
                 'seats', b.seats) order by b.created_at) as who
          from public.bookings b
          join public.profiles p on p.id = b.user_id
          left join public.bands bd on bd.id = b.band_id
         where b.resource_id = r.id and b.booking_date = d and b.session = s.session
      ) bk on true)
  );
end $$;

revoke all on function public.display_board(text, date) from public;
grant execute on function public.display_board(text, date) to anon, authenticated;
