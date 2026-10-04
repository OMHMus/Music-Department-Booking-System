-- =====================================================================
-- Induction checklist + Booking and Practice Room Agreement
-- =====================================================================
-- STATUS: applied to the live database on 4 Oct 2026 (via Supabase connector)
--
-- Pupils now complete three steps before they can be approved:
--   1. Induction checklist   -> induction_done, induction_version, induction_items
--   2. Practice Room Agreement -> agreement_signed, agreement_version, agreement_signature
--   3. Registration details  -> registered (existing)
--
-- * The wording and version numbers live in index.html
--   (INDUCTION and AGREEMENT constants). Bump the version there when the
--   wording changes so staff can see which version each pupil agreed to.
-- * Completion times are set by the database, not the browser, so they
--   can't be back-dated.
-- * A pupil can't register, and staff can't approve a pupil, until both
--   the induction and the agreement are complete.
-- * Pupils approved before this change keep their access; they are marked
--   with version 'legacy' and no completion time.
-- =====================================================================

alter table public.profiles
  add column if not exists induction_version   text,
  add column if not exists induction_items     jsonb,
  add column if not exists induction_done_at   timestamptz,
  add column if not exists agreement_version   text,
  add column if not exists agreement_signature text,
  add column if not exists agreement_signed_at timestamptz;

-- Existing pupils who ticked the old boxes (before the trigger exists)
update public.profiles set induction_version = 'legacy'
  where induction_done and induction_version is null;
update public.profiles set agreement_version = 'legacy'
  where agreement_signed and agreement_version is null;

create or replace function public.practice_onboarding()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  was_ind boolean := case when tg_op = 'UPDATE' then coalesce(old.induction_done, false) else false end;
  was_agr boolean := case when tg_op = 'UPDATE' then coalesce(old.agreement_signed, false) else false end;
  was_ok  boolean := case when tg_op = 'UPDATE' then coalesce(old.approved, false) else false end;
begin
  -- Induction: stamp the time when it is (re)completed; clear it if undone
  if not coalesce(new.induction_done, false) then
    new.induction_done_at := null;
  elsif not was_ind or new.induction_version is distinct from old.induction_version then
    if new.induction_version is null then
      raise exception 'The induction checklist is missing its version.';
    end if;
    new.induction_done_at := now();
  else
    new.induction_done_at := old.induction_done_at;
  end if;

  -- Agreement: needs a typed-name signature, stamped by the database
  if not coalesce(new.agreement_signed, false) then
    new.agreement_signed_at := null;
  elsif not was_agr or new.agreement_version is distinct from old.agreement_version
        or new.agreement_signature is distinct from old.agreement_signature then
    if new.agreement_version is null then
      raise exception 'The Practice Room Agreement is missing its version.';
    end if;
    if length(trim(coalesce(new.agreement_signature, ''))) < 3 then
      raise exception 'Type your full name to sign the Practice Room Agreement.';
    end if;
    new.agreement_signed_at := now();
  else
    new.agreement_signed_at := old.agreement_signed_at;
  end if;

  if new.role = 'pupil' then
    if coalesce(new.registered, false) and not (coalesce(new.induction_done, false) and coalesce(new.agreement_signed, false)) then
      raise exception 'Complete the induction checklist and sign the Practice Room Agreement before registering.';
    end if;
    if coalesce(new.approved, false) and not was_ok
       and not (coalesce(new.induction_done, false) and coalesce(new.agreement_signed, false)) then
      raise exception 'This pupil has not completed the induction checklist and Practice Room Agreement yet, so they cannot be approved.';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists practice_onboarding on public.profiles;
create trigger practice_onboarding
  before insert or update on public.profiles
  for each row execute function public.practice_onboarding();
