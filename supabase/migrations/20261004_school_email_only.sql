-- =====================================================================
-- Only @sexeys.somerset.sch.uk addresses can create an account
-- =====================================================================
-- STATUS: applied to the live database on 4 Oct 2026 (via Supabase connector)
--
-- The sign-up page already checks the address, but anyone with the public
-- key could call Supabase directly. This trigger on auth.users makes the
-- database itself refuse any other domain, for new accounts and for
-- changes of email address.
--
-- * Matches the whole domain exactly (case-insensitive), so look-alikes
--   such as name@sexeys.somerset.sch.uk.evil.com or
--   name@fake-sexeys.somerset.sch.uk are refused.
-- * Must match SCHOOL_DOMAIN in index.html.
-- * Accounts that already exist are not affected (all were checked and use
--   the school domain on 4 Oct 2026).
-- * To let a non-school address in (e.g. a visiting teacher), create the
--   account in the Supabase dashboard after temporarily disabling this
--   trigger, or add the address to the allow-list below.
-- =====================================================================

create or replace function public.practice_school_email_only()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  allowed_domain constant text   := 'sexeys.somerset.sch.uk';
  allow_list     constant text[] := array[]::text[];  -- exact addresses, lower case
  addr text := lower(trim(coalesce(new.email, '')));
begin
  if addr = any(allow_list) then
    return new;
  end if;
  if addr !~ ('^[^@\s]+@' || replace(allowed_domain, '.', '\.') || '$') then
    raise exception 'Accounts can only be created with a @% email address.', allowed_domain
      using errcode = 'P0001';
  end if;
  return new;
end $$;

revoke all on function public.practice_school_email_only() from public, anon, authenticated;

drop trigger if exists practice_school_email_only on auth.users;
create trigger practice_school_email_only
  before insert or update of email on auth.users
  for each row execute function public.practice_school_email_only();
