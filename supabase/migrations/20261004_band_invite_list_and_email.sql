-- =====================================================================
-- Band invites: pick existing pupils from a list, automatic emails
-- =====================================================================
-- STATUS: applied to the live database on 4 Oct 2026 (via Supabase connector) and tested
--         in rolled-back transactions: list, invite from list, unapproved blocked,
--         10-minute resend limit, failure reset, leader-only, no email once accepted.
--
-- * band_candidates(band)  - approved pupils the leader can pick from a
--   list (name + year group only, no emails); excludes current members.
-- * band_invite_user(band, pupil, instrument) - invite a listed pupil.
-- * band_invite (unchanged rules) now also returns the new member_id.
-- * band_invite_email(member) - used ONLY by the band-invite-email Edge
--   Function: checks the caller leads the band, the invite is still open
--   and it wasn't emailed in the last 10 minutes, then returns what the
--   email needs and records when it was sent.
-- Contains no DROP statements.
-- =====================================================================

alter table public.band_members add column if not exists emailed_at timestamptz;


create or replace function public.band_invite(p_band bigint, p_email text, p_instrument text)
returns json language plpgsql security definer set search_path = public as $$
declare e text := lower(btrim(coalesce(p_email, ''))); target public.profiles; existing public.band_members; mid bigint;
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
    update public.band_members set status = 'invited', invited_at = now(), responded_at = null, emailed_at = null,
           user_id = target.id, member_name = coalesce(nullif(target.full_name, ''), e), instrument = nullif(btrim(p_instrument), '')
     where id = existing.id returning id into mid;
  else
    insert into public.band_members(band_id, user_id, email, member_name, instrument, status)
      values (p_band, target.id, e, coalesce(nullif(target.full_name, ''), e), nullif(btrim(p_instrument), ''), 'invited')
      returning id into mid;
  end if;
  return json_build_object('member_id', mid, 'has_account', target.id is not null,
                           'approved', coalesce(target.approved and not target.rejected, false));
end $$;


-- Approved pupils the leader can choose from (not already in / invited to the band)
create or replace function public.band_candidates(p_band bigint)
returns json language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (select 1 from public.bands where id = p_band and lead_id = auth.uid()) then
    raise exception 'Only the band leader can invite members.';
  end if;
  return (select coalesce(json_agg(json_build_object('id', p.id, 'name', p.full_name, 'year', p.year_group)
                                   order by p.full_name), '[]'::json)
    from public.profiles p
    where p.role = 'pupil' and p.approved and not p.rejected and p.id <> auth.uid()
      and coalesce(p.full_name, '') <> ''
      and not exists (select 1 from public.band_members m
                      where m.band_id = p_band and m.status <> 'declined'
                        and (m.user_id = p.id or lower(m.email) = lower(p.email))));
end $$;


create or replace function public.band_invite_user(p_band bigint, p_user uuid, p_instrument text)
returns json language plpgsql security definer set search_path = public as $$
declare e text;
begin
  select email into e from public.profiles where id = p_user and role = 'pupil' and approved and not rejected;
  if e is null then raise exception 'That pupil can''t be invited.'; end if;
  return public.band_invite(p_band, e, p_instrument);
end $$;


-- Details for the invitation email (called by the Edge Function as the leader)
create or replace function public.band_invite_email(p_member bigint)
returns json language plpgsql security definer set search_path = public as $$
declare m public.band_members; b public.bands; lead public.profiles; acct boolean;
begin
  select * into m from public.band_members where id = p_member;
  select * into b from public.bands where id = m.band_id;
  if b.id is null or b.lead_id is distinct from auth.uid() then
    raise exception 'Only the band leader can send this invitation.';
  end if;
  if m.status <> 'invited' then raise exception 'That invitation has already been answered.'; end if;
  if m.emailed_at is not null and m.emailed_at > now() - interval '10 minutes' then
    raise exception 'That invitation was emailed a few minutes ago. Please wait before sending it again.';
  end if;
  select * into lead from public.profiles where id = b.lead_id;
  acct := exists (select 1 from public.profiles where lower(email) = lower(m.email));
  update public.band_members set emailed_at = now() where id = m.id;
  return json_build_object('to', m.email, 'band', b.name, 'inviter', lead.full_name,
                           'inviter_email', lead.email, 'has_account', acct);
end $$;

-- If sending fails, let the leader try again straight away
create or replace function public.band_invite_email_failed(p_member bigint)
returns void language sql security definer set search_path = public as $$
  update public.band_members m set emailed_at = null
   where m.id = p_member and exists (select 1 from public.bands b where b.id = m.band_id and b.lead_id = auth.uid());
$$;


do $$
declare f text;
begin
  foreach f in array array['band_invite(bigint, text, text)', 'band_candidates(bigint)',
    'band_invite_user(bigint, uuid, text)', 'band_invite_email(bigint)', 'band_invite_email_failed(bigint)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
