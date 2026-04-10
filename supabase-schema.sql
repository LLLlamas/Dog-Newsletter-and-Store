-- ═══════════════════════════════════════════════════════════════════
-- Dogs & Llamas — Supabase schema
-- ═══════════════════════════════════════════════════════════════════
--
-- HOW TO APPLY:
--   1. Go to https://supabase.com/dashboard/project/nizvndjuzyblsewobkru
--   2. Click "SQL Editor" in the left nav
--   3. Paste the entire contents of this file into a new query
--   4. Click "Run" (or press Ctrl/Cmd+Enter)
--   5. You should see "Success. No rows returned" at the bottom
--
-- WHAT THIS CREATES:
--   • subscribers table           — stores email, username, and dog profile
--   • dal_subscribe(email)        — RPC function for new subscriptions
--   • dal_lookup(key)             — RPC function for login by email OR username
--   • Two seeded rows             — lorenzoleollamas@gmail.com → Turbo,
--                                   ltl924@gmail.com → Troy
--
-- SECURITY:
--   • Row-level security ON (no direct table access via anon key)
--   • Anonymous visitors can ONLY call the two RPC functions
--   • Each function exposes ONLY the dog profile, never the email list
--   • You the owner retain full access via the service-role key
--
-- ═══════════════════════════════════════════════════════════════════


-- ── 1. TABLE ───────────────────────────────────────────────────────
create table if not exists public.subscribers (
  id            uuid primary key default gen_random_uuid(),
  email         text unique not null,
  username      text unique not null,
  dog_name      text,
  dog_breed     text,
  dog_size      text,
  dog_traits    text[],
  dog_emoji     text,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

comment on table  public.subscribers          is 'Dogs & Llamas newsletter subscribers + optional dog profiles';
comment on column public.subscribers.username is 'Derived from email prefix; serves as the personal discount code';


-- ── 2. ROW-LEVEL SECURITY ──────────────────────────────────────────
alter table public.subscribers enable row level security;

-- We intentionally create ZERO policies on the table itself.
-- This means the anon role has no direct access.
-- All access happens via SECURITY DEFINER functions below.


-- ── 3. SUBSCRIBE FUNCTION ──────────────────────────────────────────
-- Inserts a new subscriber, or returns the existing one if the email
-- is already on file. Called from dal-subscriber.js handleSubscribe().
create or replace function public.dal_subscribe(p_email text)
returns table (
  email      text,
  username   text,
  dog_name   text,
  dog_breed  text,
  dog_size   text,
  dog_traits text[],
  dog_emoji  text,
  is_new     boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email    text;
  v_username text;
  v_existing public.subscribers%rowtype;
begin
  -- Normalize and validate
  v_email := lower(trim(p_email));
  if v_email !~ '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' then
    raise exception 'Invalid email format: %', v_email;
  end if;

  -- Derive username from email prefix (letters + digits only, lowercase)
  v_username := regexp_replace(split_part(v_email, '@', 1), '[^a-z0-9]', '', 'g');

  -- Already on file?
  select * into v_existing from public.subscribers where public.subscribers.email = v_email;

  if found then
    return query
      select v_existing.email,
             v_existing.username,
             v_existing.dog_name,
             v_existing.dog_breed,
             v_existing.dog_size,
             v_existing.dog_traits,
             v_existing.dog_emoji,
             false;
  else
    insert into public.subscribers (email, username)
      values (v_email, v_username);
    return query
      select v_email      as email,
             v_username   as username,
             null::text   as dog_name,
             null::text   as dog_breed,
             null::text   as dog_size,
             null::text[] as dog_traits,
             null::text   as dog_emoji,
             true         as is_new;
  end if;
end;
$$;

comment on function public.dal_subscribe(text) is 'Public subscribe endpoint — creates or returns an existing subscriber';


-- ── 4. LOOKUP FUNCTION (login / unlock) ────────────────────────────
-- Returns the dog profile for a matching email OR username.
-- Called from dal-subscriber.js loginWithKey().
create or replace function public.dal_lookup(p_key text)
returns table (
  username   text,
  dog_name   text,
  dog_breed  text,
  dog_size   text,
  dog_traits text[],
  dog_emoji  text
)
language sql
security definer
set search_path = public
as $$
  select s.username,
         s.dog_name,
         s.dog_breed,
         s.dog_size,
         s.dog_traits,
         s.dog_emoji
  from public.subscribers s
  where s.email = lower(trim(p_key))
     or s.username = lower(trim(p_key))
  limit 1;
$$;

comment on function public.dal_lookup(text) is 'Public login endpoint — look up a subscriber by email or username';


-- ── 5. GRANTS ──────────────────────────────────────────────────────
-- Only these two functions are reachable by anonymous visitors.
revoke all   on table public.subscribers              from anon, authenticated;
grant  execute on function public.dal_subscribe(text) to   anon, authenticated;
grant  execute on function public.dal_lookup(text)    to   anon, authenticated;


-- ── 6. SEED DATA ───────────────────────────────────────────────────
-- Your two personal profiles: Turbo (mini Aussie) and Troy (husky).
-- Re-running this SQL safely updates the profiles if you change the traits later.
insert into public.subscribers
  (email, username, dog_name, dog_breed, dog_size, dog_traits, dog_emoji)
values
  (
    'lorenzoleollamas@gmail.com',
    'lorenzoleollamas',
    'Turbo',
    'Mini Australian Shepherd',
    'medium',
    array['high-energy','food-motivated','agility','outdoor','barks-at-movement'],
    '⚡'
  ),
  (
    'ltl924@gmail.com',
    'ltl924',
    'Troy',
    'Husky',
    'large',
    array['endurance','outdoor','cold-weather','vocal','double-coat'],
    '🐺'
  )
on conflict (email) do update set
  username   = excluded.username,
  dog_name   = excluded.dog_name,
  dog_breed  = excluded.dog_breed,
  dog_size   = excluded.dog_size,
  dog_traits = excluded.dog_traits,
  dog_emoji  = excluded.dog_emoji,
  updated_at = now();


-- ═══════════════════════════════════════════════════════════════════
-- VERIFICATION (run these after applying to double-check everything)
-- ═══════════════════════════════════════════════════════════════════

-- 1. Check the seeded rows:
--    select username, dog_name, dog_breed from public.subscribers;
--
-- 2. Test the lookup function (should return Turbo's row):
--    select * from public.dal_lookup('lorenzoleollamas@gmail.com');
--    select * from public.dal_lookup('lorenzoleollamas');
--
-- 3. Test the subscribe function (should return a new row):
--    select * from public.dal_subscribe('test.user@example.com');
--
-- 4. Clean up the test row:
--    delete from public.subscribers where email = 'test.user@example.com';
