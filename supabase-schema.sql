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
-- 7. AVAILABILITY CALENDAR
-- ═══════════════════════════════════════════════════════════════════
-- Stores Lorenzo & Catalina's availability for boarding/sitting.
-- Public visitors can READ via dal_get_availability.
-- Only the owner (with the admin PIN) can WRITE via dal_set_availability.
--
-- IMPORTANT: change the PIN below from '1234' to your own 4-digit PIN
-- before applying this in production. The PIN lives only inside the
-- function body — anon visitors never see it.

create table if not exists public.availability (
  day        date primary key,
  status     text not null check (status in ('available','booked','unavailable')),
  dog_name   text,
  drop_off   time,
  pick_up    time,
  notes      text,
  updated_at timestamptz default now()
);

-- If you ran an earlier version of this file, add the new columns:
alter table public.availability add column if not exists dog_name text;
alter table public.availability add column if not exists drop_off time;
alter table public.availability add column if not exists pick_up  time;
alter table public.availability add column if not exists notes    text;

comment on table public.availability is 'Owner-managed availability calendar — public read, PIN-gated write. Booking days carry dog_name + drop_off + pick_up.';

alter table public.availability enable row level security;
-- Zero policies on the table itself — all access via SECURITY DEFINER RPCs.

-- Drop older versions of the RPCs so the new signatures replace cleanly
drop function if exists public.dal_get_availability(date, date);
drop function if exists public.dal_set_availability(text, date, text);

-- ── 7a. READ FUNCTION ──────────────────────────────────────────────
-- Returns all availability rows in [p_from, p_to]. Anon-callable.
create or replace function public.dal_get_availability(p_from date, p_to date)
returns table (
  day        date,
  status     text,
  dog_name   text,
  drop_off   time,
  pick_up    time,
  notes      text,
  updated_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select a.day, a.status, a.dog_name, a.drop_off, a.pick_up, a.notes, a.updated_at
  from public.availability a
  where a.day between p_from and p_to;
$$;

comment on function public.dal_get_availability(date, date) is 'Public read of the availability calendar in a date range';

-- ── 7b. WRITE FUNCTION (PIN-gated) ─────────────────────────────────
-- Upserts a single day. Requires the admin PIN.
-- ⚠ Change '1234' to your real PIN before applying!
create or replace function public.dal_set_availability(
  p_pin      text,
  p_date     date,
  p_status   text,
  p_dog_name text default null,
  p_drop_off time default null,
  p_pick_up  time default null,
  p_notes    text default null
)
returns public.availability
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_pin constant text := '1234';   -- ← CHANGE ME
  v_row public.availability;
begin
  if p_pin is null or p_pin <> v_admin_pin then
    raise exception 'Invalid PIN';
  end if;
  if p_status not in ('available','booked','unavailable') then
    raise exception 'Invalid status: %', p_status;
  end if;

  insert into public.availability (day, status, dog_name, drop_off, pick_up, notes, updated_at)
  values (p_date, p_status, p_dog_name, p_drop_off, p_pick_up, p_notes, now())
  on conflict (day) do update
    set status     = excluded.status,
        dog_name   = excluded.dog_name,
        drop_off   = excluded.drop_off,
        pick_up    = excluded.pick_up,
        notes      = excluded.notes,
        updated_at = now()
  returning * into v_row;

  return v_row;
end;
$$;

comment on function public.dal_set_availability(text, date, text, text, time, time, text) is 'Owner write — requires admin PIN. Upserts a single day with optional booking details.';

-- ── 7c. PIN VERIFY (used by client to validate before showing edit UI) ─
create or replace function public.dal_verify_admin_pin(p_pin text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_pin constant text := '1234';   -- ← CHANGE ME (must match above)
begin
  return p_pin is not null and p_pin = v_admin_pin;
end;
$$;

comment on function public.dal_verify_admin_pin(text) is 'Returns true if the supplied PIN matches the owner PIN';

-- ── 7d. GRANTS ─────────────────────────────────────────────────────
revoke all   on table public.availability                                                       from anon, authenticated;
grant  execute on function public.dal_get_availability(date, date)                              to   anon, authenticated;
grant  execute on function public.dal_set_availability(text, date, text, text, time, time, text) to   anon, authenticated;
grant  execute on function public.dal_verify_admin_pin(text)                                    to   anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- 8. BOOKING REQUESTS  (in-house booking flow, replaces Rover)
-- ═══════════════════════════════════════════════════════════════════
-- Visitors submit booking requests on the schedule page. The owner
-- sees pending requests in admin mode and can approve / decline.
-- Approving a request flips the requested days to 'booked' on the
-- availability calendar (Stage 2 will also generate a Stripe link).

create table if not exists public.booking_requests (
  id            uuid primary key default gen_random_uuid(),
  status        text not null default 'pending'
                 check (status in ('pending','approved','declined','cancelled')),
  service       text not null
                 check (service in ('boarding','daycare','dropin','walking','housesitting')),
  client_name   text not null,
  client_email  text not null,
  client_phone  text,
  dog_name      text not null,
  start_date    date not null,
  end_date      date not null,
  drop_off      time,
  pick_up       time,
  notes         text,
  decided_at    timestamptz,
  decided_by    text,
  paid_at       timestamptz,
  paid_by       text,
  created_at    timestamptz default now()
);

-- Add payment-tracking columns for databases that were created
-- before they existed (no-op on fresh installs).
alter table public.booking_requests add column if not exists paid_at timestamptz;
alter table public.booking_requests add column if not exists paid_by text;

comment on table public.booking_requests is
  'Visitor-submitted booking requests. Owner approves/declines via PIN-gated RPC. paid_at marks the booking as confirmed after Venmo/Zelle payment received.';

create index if not exists booking_requests_status_idx on public.booking_requests(status);
create index if not exists booking_requests_dates_idx  on public.booking_requests(start_date, end_date);
create index if not exists booking_requests_paid_idx   on public.booking_requests(paid_at) where paid_at is null;

alter table public.booking_requests enable row level security;
-- Zero policies. All reads/writes go through SECURITY DEFINER RPCs below.

-- ── 8a. CREATE REQUEST (anon-callable, public form) ───────────────
drop function if exists public.dal_create_booking_request(text,text,text,text,text,date,date,time,time,text);

create or replace function public.dal_create_booking_request(
  p_service      text,
  p_client_name  text,
  p_client_email text,
  p_client_phone text,
  p_dog_name     text,
  p_start_date   date,
  p_end_date     date,
  p_drop_off     time,
  p_pick_up      time,
  p_notes        text
)
returns public.booking_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.booking_requests;
begin
  -- Basic validation
  if p_client_name  is null or length(trim(p_client_name))  = 0 then raise exception 'Name required';  end if;
  if p_client_email is null or length(trim(p_client_email)) = 0 then raise exception 'Email required'; end if;
  if p_dog_name     is null or length(trim(p_dog_name))     = 0 then raise exception 'Dog name required'; end if;
  if p_start_date is null or p_end_date is null then raise exception 'Dates required'; end if;
  if p_end_date < p_start_date then raise exception 'End date must be on or after start date'; end if;
  if p_start_date < current_date then raise exception 'Cannot request a date in the past'; end if;
  if p_service not in ('boarding','daycare','dropin','walking','housesitting') then
    raise exception 'Invalid service';
  end if;

  insert into public.booking_requests
    (service, client_name, client_email, client_phone,
     dog_name, start_date, end_date, drop_off, pick_up, notes)
  values
    (p_service, trim(p_client_name), lower(trim(p_client_email)), nullif(trim(p_client_phone),''),
     trim(p_dog_name), p_start_date, p_end_date, p_drop_off, p_pick_up, nullif(trim(p_notes),''))
  returning * into v_row;

  return v_row;
end;
$$;

comment on function public.dal_create_booking_request(text,text,text,text,text,date,date,time,time,text)
  is 'Public booking request submission. No PIN required.';

-- ── 8b. LIST PENDING REQUESTS  (PIN-gated, owner-only) ────────────
drop function if exists public.dal_list_booking_requests(text, text);

create or replace function public.dal_list_booking_requests(p_pin text, p_status text default 'pending')
returns setof public.booking_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_pin constant text := '1234';   -- ← must match dal_set_availability
begin
  if p_pin is null or p_pin <> v_admin_pin then raise exception 'Invalid PIN'; end if;
  return query
    select * from public.booking_requests
    where (p_status is null or status = p_status)
    order by created_at desc;
end;
$$;

comment on function public.dal_list_booking_requests(text, text)
  is 'Owner reads booking requests filtered by status (default pending).';

-- ── 8c. APPROVE / DECLINE  (PIN-gated, owner-only) ────────────────
drop function if exists public.dal_decide_booking_request(text, uuid, text);

create or replace function public.dal_decide_booking_request(
  p_pin     text,
  p_id      uuid,
  p_action  text   -- 'approve' | 'decline'
)
returns public.booking_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_pin constant text := '1234';   -- ← must match
  v_req public.booking_requests;
  v_day date;
begin
  if p_pin is null or p_pin <> v_admin_pin then raise exception 'Invalid PIN'; end if;
  if p_action not in ('approve','decline') then raise exception 'Invalid action'; end if;

  select * into v_req from public.booking_requests where id = p_id for update;
  if not found then raise exception 'Request not found'; end if;

  update public.booking_requests
     set status     = case when p_action = 'approve' then 'approved' else 'declined' end,
         decided_at = now(),
         decided_by = 'owner'
   where id = p_id
  returning * into v_req;

  -- On approval: mark every day in the range as 'booked' on the availability calendar
  if p_action = 'approve' then
    v_day := v_req.start_date;
    while v_day <= v_req.end_date loop
      insert into public.availability (day, status, dog_name, drop_off, pick_up, notes, updated_at)
      values (v_day, 'booked', v_req.dog_name, v_req.drop_off, v_req.pick_up,
              'Booking #' || substring(v_req.id::text, 1, 8), now())
      on conflict (day) do update
        set status     = excluded.status,
            dog_name   = excluded.dog_name,
            drop_off   = excluded.drop_off,
            pick_up    = excluded.pick_up,
            notes      = excluded.notes,
            updated_at = now();
      v_day := v_day + 1;
    end loop;
  end if;

  -- Notify the client of the decision (approve = confirmation, decline = polite no)
  begin
    perform public.dal_notify_client_of_decision(v_req, p_action);
  exception when others then
    raise warning 'dal_decide_booking_request: client email failed: %', SQLERRM;
  end;

  return v_req;
end;
$$;

comment on function public.dal_decide_booking_request(text, uuid, text)
  is 'Owner approves or declines a booking request. Approval marks availability days booked.';

-- ── 8d. GRANTS ─────────────────────────────────────────────────────
revoke all   on table public.booking_requests                                                                from anon, authenticated;
grant  execute on function public.dal_create_booking_request(text,text,text,text,text,date,date,time,time,text) to anon, authenticated;
grant  execute on function public.dal_list_booking_requests(text, text)                                      to anon, authenticated;
grant  execute on function public.dal_decide_booking_request(text, uuid, text)                               to anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- 9. EMAIL NOTIFICATIONS  (Gmail SMTP via Supabase Edge Function)
-- ═══════════════════════════════════════════════════════════════════
-- Sends an email to the owner whenever a new booking_request is
-- created, and emails the client when the owner approves/declines.
--
-- Architecture: Postgres trigger → pg_net.http_post → Supabase Edge
-- Function `send-email` (supabase/functions/send-email/index.ts) →
-- Gmail SMTP using a Google App Password. The Edge Function accepts
-- the exact same JSON payload shape Brevo used (sender / to / subject
-- / htmlContent) so these SQL functions only need to change the target
-- URL and the auth header.
--
-- Why not Brevo: Brevo refuses Gmail addresses as senders, and the
-- business runs out of dogsandllamasservice@gmail.com.
--
-- Required setup (run ONCE, outside this file):
--   1. Enable pg_net:
--        Dashboard → Database → Extensions → search "pg_net" → Enable
--   2. Generate a Google App Password for dogsandllamasservice@gmail.com
--      at myaccount.google.com → Security → App passwords.
--   3. Deploy the Edge Function with the Supabase CLI:
--        supabase login
--        supabase link --project-ref nizvndjuzyblsewobkru
--        supabase functions deploy send-email
--   4. Set the function secrets:
--        supabase secrets set \
--          GMAIL_USER=dogsandllamasservice@gmail.com \
--          GMAIL_APP_PASSWORD=<16-char app password> \
--          EDGE_SHARED_SECRET=<32+ random chars>
--   5. Insert the app_config rows (Gmail relay + payment handles):
--        insert into public.app_config(key, value) values
--          ('owner_email',           'dogsandllamasservice@gmail.com'),
--          ('owner_name',            'Lorenzo Llamas'),
--          ('sender_email',          'dogsandllamasservice@gmail.com'),
--          ('sender_name',           'Dogs & Llamas'),
--          ('email_fn_url',          'https://nizvndjuzyblsewobkru.supabase.co/functions/v1/send-email'),
--          ('email_fn_secret',       '<same EDGE_SHARED_SECRET as step 4>'),
--          -- PAYMENT HANDLES — mock values below. Replace with real ones
--          -- when your accounts are registered. DO NOT COMMIT real values
--          -- to git; keep them only in Supabase.
--          ('venmo_handle',          'dogsandllamas'),               -- just the username, no '@'
--          ('zelle_display',         'dogsandllamasservice@gmail.com'), -- email OR phone
--          ('zelle_display_type',    'email')                         -- 'email' or 'phone'
--        on conflict (key) do update set value = excluded.value;
--   6. Re-run this whole file so the triggers pick up the new config.
--
-- Legacy: the 'brevo_api_key' row (if present) is now unused. Safe to
-- leave in place as a rollback hedge; delete later once stable.
--
-- If pg_net is NOT enabled the triggers silently no-op, so the booking
-- request still saves successfully — you just won't get an email.

create table if not exists public.app_config (
  key   text primary key,
  value text not null
);
alter table public.app_config enable row level security;
-- Zero policies. Only SECURITY DEFINER functions read this table.
revoke all on table public.app_config from anon, authenticated;

comment on table public.app_config is 'Private key/value store for API keys and emails. Anon role has zero access.';

create or replace function public.dal_notify_owner_of_request()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner_email   text;
  v_owner_name    text;
  v_sender_email  text;
  v_sender_name   text;
  v_fn_url        text;
  v_fn_secret     text;
  v_subject       text;
  v_html          text;
  v_service_label text;
  v_phone_block   text;
  v_notes_block   text;
  v_unit_price    integer;
  v_unit_label    text;
  v_quantity      integer;
  v_total         integer;
  v_total_line    text;
  v_payload       jsonb;
  v_pgnet_ok      boolean;
begin
  -- Check pg_net is available
  select exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('net','extensions') and p.proname = 'http_post'
  ) into v_pgnet_ok;
  if not v_pgnet_ok then return new; end if;

  -- Pull config
  select value into v_owner_email  from public.app_config where key = 'owner_email';
  select value into v_owner_name   from public.app_config where key = 'owner_name';
  select value into v_sender_email from public.app_config where key = 'sender_email';
  select value into v_sender_name  from public.app_config where key = 'sender_name';
  select value into v_fn_url       from public.app_config where key = 'email_fn_url';
  select value into v_fn_secret    from public.app_config where key = 'email_fn_secret';

  if v_owner_email is null or v_fn_url is null or v_fn_secret is null then
    return new;
  end if;

  -- Pretty service label
  v_service_label := case lower(coalesce(new.service, ''))
    when 'boarding'     then 'Overnight boarding'
    when 'daycare'      then 'Daycare'
    when 'dropin'       then 'Drop-in visit'
    when 'walking'      then 'Dog walk'
    when 'housesitting' then 'House-sitting'
    else coalesce(initcap(new.service), '—')
  end;

  -- Pricing: unit price, unit label, quantity.
  -- Boarding + housesitting bill per NIGHT (end - start, min 1).
  -- Daycare / dropin / walking bill per DAY in the range (inclusive).
  case lower(coalesce(new.service, ''))
    when 'boarding' then
      v_unit_price := 90;
      v_unit_label := 'night';
      v_quantity   := greatest(new.end_date - new.start_date, 1);
    when 'housesitting' then
      v_unit_price := 100;
      v_unit_label := 'night';
      v_quantity   := greatest(new.end_date - new.start_date, 1);
    when 'daycare' then
      v_unit_price := 50;
      v_unit_label := 'day';
      v_quantity   := (new.end_date - new.start_date) + 1;
    when 'dropin' then
      v_unit_price := 45;
      v_unit_label := 'visit';
      v_quantity   := (new.end_date - new.start_date) + 1;
    when 'walking' then
      v_unit_price := 25;
      v_unit_label := 'walk';
      v_quantity   := (new.end_date - new.start_date) + 1;
    else
      v_unit_price := 0;
      v_unit_label := '';
      v_quantity   := 0;
  end case;
  v_total := v_unit_price * v_quantity;

  if v_total > 0 then
    v_total_line :=
      $H$<tr><td style="padding:10px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Total</td><td style="padding:10px 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:18px;color:#1B4F8C;font-weight:700;">&#36;$H$
      || v_total::text
      || $H$<span style="display:block;font-size:12px;font-weight:500;color:#8C94B0;margin-top:2px;">$H$
      || v_quantity::text
      || $H$ $H$ || v_unit_label || case when v_quantity = 1 then '' else 's' end
      || $H$ &times; &#36;$H$ || v_unit_price::text || $H$/$H$ || v_unit_label || $H$</span></td></tr>$H$;
  else
    v_total_line := '';
  end if;

  -- Optional phone line (hidden if empty)
  if new.client_phone is not null and length(trim(new.client_phone)) > 0 then
    v_phone_block := $H$<br><span style="color:#4C5470;font-size:14px;">$H$ || new.client_phone || $H$</span>$H$;
  else
    v_phone_block := '';
  end if;

  -- Optional notes block (hidden if empty)
  if new.notes is not null and length(trim(new.notes)) > 0 then
    v_notes_block :=
      $H$<p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">Notes from Client</p><p style="margin:0 0 28px;font-family:Georgia,serif;font-size:15px;font-style:italic;line-height:1.7;color:#4C5470;border-left:3px solid #D4A017;padding:4px 0 4px 16px;">&ldquo;$H$
      || replace(replace(replace(new.notes, '<', '&lt;'), '>', '&gt;'), E'\n', '<br>')
      || $H$&rdquo;</p>$H$;
  else
    v_notes_block := '';
  end if;

  v_subject := 'New booking request from ' || new.client_name || ' (' || new.dog_name || ')';

  v_html :=
    $H$<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="X-UA-Compatible" content="IE=edge"><title>New booking request</title></head><body style="margin:0;padding:0;background-color:#F2F5FB;font-family:Arial,Helvetica,sans-serif;"><div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:#F2F5FB;">New booking request from $H$
    || coalesce(new.client_name, 'a client')
    || $H$ for $H$
    || coalesce(new.dog_name, 'their dog')
    || $H$ &mdash; open the admin view to approve or decline.</div><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color:#F2F5FB;"><tr><td align="center" style="padding:32px 16px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="560" style="background-color:#FFFFFF;border-radius:10px;overflow:hidden;max-width:560px;"><tr><td style="background-color:#1B4F8C;background-image:linear-gradient(150deg,#0A1E3D 0%,#1B4F8C 55%,#2B6CB0 100%);padding:36px 40px 32px;text-align:center;"><p style="margin:0 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#F5CC4A;font-weight:bold;">New Booking Request</p><h1 style="margin:0;font-family:Georgia,serif;font-size:28px;font-weight:600;color:#ffffff;line-height:1.2;letter-spacing:-0.3px;">Dogs &amp; Llamas</h1><p style="margin:10px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:rgba(255,255,255,0.85);font-style:italic;">Someone just requested a stay</p></td></tr><tr><td style="padding:36px 40px 8px;"><p style="margin:0 0 24px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Hi Lorenzo, a new booking request just came in. Review the details below, then open the admin view to approve or decline.</p><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">Booking Details</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 28px;border-left:4px solid #D4A017;"><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;width:92px;vertical-align:top;">Service</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || v_service_label
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Dog</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(new.dog_name, '—')
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Dates</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(to_char(new.start_date, 'FMMon FMDD'), '—')
    || $H$ &nbsp;&rarr;&nbsp; $H$
    || coalesce(to_char(new.end_date, 'FMMon FMDD, YYYY'), '—')
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Drop-off</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(to_char(new.drop_off, 'FMHH12:MI AM'), '—')
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Pick-up</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(to_char(new.pick_up, 'FMHH12:MI AM'), '—')
    || $H$</td></tr>$H$
    || v_total_line
    || $H$</table><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">Client</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 28px;background-color:#E4F0FB;border-radius:6px;"><tr><td style="padding:16px 20px;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;line-height:1.6;"><strong style="font-size:16px;">$H$
    || coalesce(new.client_name, '—')
    || $H$</strong><br><a href="mailto:$H$
    || coalesce(new.client_email, '')
    || $H$" style="color:#1B4F8C;text-decoration:none;font-size:14px;">$H$
    || coalesce(new.client_email, '')
    || $H$</a>$H$
    || v_phone_block
    || $H$</td></tr></table>$H$
    || v_notes_block
    || $H$<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:8px 0 4px;"><tr><td align="center"><a href="https://llllamas.github.io/Dog-Newsletter-and-Store/schedule.html" style="display:inline-block;background-color:#1B4F8C;background-image:linear-gradient(150deg,#1B4F8C 0%,#2B6CB0 100%);color:#ffffff;font-family:Arial,Helvetica,sans-serif;font-size:14px;font-weight:bold;text-decoration:none;padding:14px 32px;border-radius:99px;letter-spacing:0.5px;">Open admin view &rarr;</a></td></tr></table><p style="margin:18px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#8C94B0;text-align:center;line-height:1.6;">Enter admin mode on the schedule page to approve or decline this request.<br>Approved bookings update the calendar automatically.</p></td></tr><tr><td style="padding:24px 40px 32px;border-top:1px solid #E7ECF5;text-align:center;"><p style="margin:0;font-family:Georgia,serif;font-size:13px;color:#1B4F8C;font-weight:600;letter-spacing:0.3px;">Dogs &amp; Llamas</p><p style="margin:4px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;line-height:1.6;">Lorenzo &amp; Catalina Llamas &middot; All bookings handled in-house</p></td></tr></table></td></tr></table></body></html>$H$;

  v_payload := jsonb_build_object(
    'sender',  jsonb_build_object('name', coalesce(v_sender_name, 'Dogs & Llamas'),
                                   'email', coalesce(v_sender_email, v_owner_email)),
    'to',      jsonb_build_array(jsonb_build_object('email', v_owner_email,
                                                    'name',  coalesce(v_owner_name, ''))),
    'subject', v_subject,
    'htmlContent', v_html
  );

  -- Fire-and-forget POST to the send-email Edge Function.
  -- Wrapped in EXCEPTION so the trigger can never block the insert.
  begin
    perform net.http_post(
      url     := v_fn_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-edge-secret', v_fn_secret),
      body    := v_payload
    );
  exception when others then
    raise warning 'dal_notify_owner_of_request: edge POST failed: %', SQLERRM;
  end;

  return new;
end;
$$;

drop trigger if exists trg_notify_owner_of_request on public.booking_requests;
create trigger trg_notify_owner_of_request
  after insert on public.booking_requests
  for each row execute function public.dal_notify_owner_of_request();


-- ── 9b. CLIENT-FACING DECISION EMAIL ──────────────────────────────
-- Sent from dal_decide_booking_request when Lorenzo approves or declines.
-- On approve, the email includes Venmo + Zelle payment instructions.
-- The client pays manually; Lorenzo then marks the booking as paid via
-- dal_mark_booking_paid which fires the final "You're all set" email.

create or replace function public.dal_notify_client_of_decision(
  v_req     public.booking_requests,
  p_action  text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_sender_email     text;
  v_sender_name      text;
  v_fn_url           text;
  v_fn_secret        text;
  v_pgnet_ok         boolean;
  v_subject          text;
  v_html             text;
  v_payload          jsonb;
  v_service_label    text;
  v_unit_price       integer;
  v_unit_label       text;
  v_quantity         integer;
  v_total            integer;
  v_total_line       text;
  v_venmo_handle     text;
  v_zelle_display    text;
  v_zelle_type       text;
  v_venmo_url        text;
  v_venmo_block      text;
  v_zelle_block      text;
  v_zelle_label      text;
  v_payment_ref      text;
  v_schedule_url     text := 'https://llllamas.github.io/Dog-Newsletter-and-Store/schedule.html';
begin
  select exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('net','extensions') and p.proname = 'http_post'
  ) into v_pgnet_ok;
  if not v_pgnet_ok then return; end if;

  select value into v_sender_email from public.app_config where key = 'sender_email';
  select value into v_sender_name  from public.app_config where key = 'sender_name';
  select value into v_fn_url       from public.app_config where key = 'email_fn_url';
  select value into v_fn_secret    from public.app_config where key = 'email_fn_secret';
  select value into v_venmo_handle  from public.app_config where key = 'venmo_handle';
  select value into v_zelle_display from public.app_config where key = 'zelle_display';
  select value into v_zelle_type    from public.app_config where key = 'zelle_display_type';
  if v_fn_url is null or v_fn_secret is null or v_req.client_email is null then
    return;
  end if;

  -- Short ID the client includes in the Venmo/Zelle payment note so
  -- Lorenzo can match the payment back to this booking.
  v_payment_ref := 'DAL-' || upper(substring(v_req.id::text, 1, 8));

  -- Pretty service label
  v_service_label := case lower(coalesce(v_req.service, ''))
    when 'boarding'     then 'Overnight boarding'
    when 'daycare'      then 'Daycare'
    when 'dropin'       then 'Drop-in visit'
    when 'walking'      then 'Dog walk'
    when 'housesitting' then 'House-sitting'
    else coalesce(initcap(v_req.service), '—')
  end;

  -- Pricing: see dal_notify_owner_of_request for rationale.
  case lower(coalesce(v_req.service, ''))
    when 'boarding' then
      v_unit_price := 90;
      v_unit_label := 'night';
      v_quantity   := greatest(v_req.end_date - v_req.start_date, 1);
    when 'housesitting' then
      v_unit_price := 100;
      v_unit_label := 'night';
      v_quantity   := greatest(v_req.end_date - v_req.start_date, 1);
    when 'daycare' then
      v_unit_price := 50;
      v_unit_label := 'day';
      v_quantity   := (v_req.end_date - v_req.start_date) + 1;
    when 'dropin' then
      v_unit_price := 45;
      v_unit_label := 'visit';
      v_quantity   := (v_req.end_date - v_req.start_date) + 1;
    when 'walking' then
      v_unit_price := 25;
      v_unit_label := 'walk';
      v_quantity   := (v_req.end_date - v_req.start_date) + 1;
    else
      v_unit_price := 0;
      v_unit_label := '';
      v_quantity   := 0;
  end case;
  v_total := v_unit_price * v_quantity;

  if v_total > 0 then
    v_total_line :=
      $H$<tr><td style="padding:10px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Total</td><td style="padding:10px 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:18px;color:#1B4F8C;font-weight:700;">&#36;$H$
      || v_total::text
      || $H$<span style="display:block;font-size:12px;font-weight:500;color:#8C94B0;margin-top:2px;">$H$
      || v_quantity::text
      || $H$ $H$ || v_unit_label || case when v_quantity = 1 then '' else 's' end
      || $H$ &times; &#36;$H$ || v_unit_price::text || $H$/$H$ || v_unit_label || $H$</span></td></tr>$H$;
  else
    v_total_line := '';
  end if;

  -- Venmo deep-link: opens the Venmo app on mobile or venmo.com on desktop,
  -- pre-fills the recipient, amount, and payment note (payment ref).
  -- Falls back to empty Venmo card when no venmo_handle is configured.
  if v_venmo_handle is not null and length(trim(v_venmo_handle)) > 0 then
    v_venmo_url :=
      'https://venmo.com/' || v_venmo_handle
      || '?txn=pay'
      || '&amount=' || coalesce(v_total, 0)::text
      || '&note=' || replace(replace(v_payment_ref || ' ' || coalesce(v_service_label, ''), ' ', '%20'), '&', '%26');

    v_venmo_block :=
      $H$<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 12px;background-color:#FFFFFF;border:1.5px solid #E4EAFA;border-left:4px solid #D4A017;border-radius:8px;"><tr><td style="padding:18px 20px;font-family:Arial,Helvetica,sans-serif;"><p style="margin:0 0 4px;font-size:10px;font-weight:bold;letter-spacing:1.4px;text-transform:uppercase;color:#D4A017;">Option 1 &middot; Venmo</p><p style="margin:0 0 14px;font-size:17px;font-weight:700;color:#1A1D26;">@$H$
      || v_venmo_handle
      || $H$</p><p style="margin:0 0 14px;font-size:13px;color:#4C5470;line-height:1.55;">Tap the button below &mdash; it opens the Venmo app (or venmo.com) with the amount and reference pre-filled.</p><table role="presentation" border="0" cellpadding="0" cellspacing="0"><tr><td><a href="$H$
      || v_venmo_url
      || $H$" style="display:inline-block;background-color:#3D95CE;background-image:linear-gradient(150deg,#3D95CE 0%,#2775C9 100%);color:#ffffff;font-family:Arial,Helvetica,sans-serif;font-size:14px;font-weight:bold;text-decoration:none;padding:12px 26px;border-radius:99px;letter-spacing:0.3px;">Pay &#36;$H$
      || v_total::text
      || $H$ on Venmo &rarr;</a></td></tr></table></td></tr></table>$H$;
  else
    v_venmo_block := '';
  end if;

  -- Zelle "card": plain identifier the client copies into their bank app.
  -- Zelle has no deep-link; we just show the email/phone prominently.
  if v_zelle_display is not null and length(trim(v_zelle_display)) > 0 then
    v_zelle_label := case lower(coalesce(v_zelle_type, 'email'))
      when 'phone' then 'Phone number'
      else 'Email'
    end;

    v_zelle_block :=
      $H$<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 12px;background-color:#FFFFFF;border:1.5px solid #E4EAFA;border-left:4px solid #1B4F8C;border-radius:8px;"><tr><td style="padding:18px 20px;font-family:Arial,Helvetica,sans-serif;"><p style="margin:0 0 4px;font-size:10px;font-weight:bold;letter-spacing:1.4px;text-transform:uppercase;color:#1B4F8C;">Option 2 &middot; Zelle</p><p style="margin:0 0 10px;font-size:11px;font-weight:600;letter-spacing:0.3px;color:#8C94B0;text-transform:uppercase;">$H$
      || v_zelle_label
      || $H$</p><p style="margin:0 0 14px;font-size:17px;font-weight:700;color:#1A1D26;word-break:break-all;">$H$
      || v_zelle_display
      || $H$</p><p style="margin:0;font-size:13px;color:#4C5470;line-height:1.55;">Open your bank&rsquo;s app, choose <strong>Send money with Zelle</strong>, and send <strong>&#36;$H$
      || v_total::text
      || $H$</strong> to the address above.</p></td></tr></table>$H$;
  else
    v_zelle_block := '';
  end if;

  if p_action = 'approve' then
    v_subject := 'Almost there — complete payment to confirm your stay';
    v_html :=
      $H$<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="X-UA-Compatible" content="IE=edge"><title>Almost confirmed</title></head><body style="margin:0;padding:0;background-color:#F2F5FB;font-family:Arial,Helvetica,sans-serif;"><div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:#F2F5FB;">Lorenzo approved your booking for $H$
      || coalesce(v_req.dog_name, 'your dog')
      || $H$ &mdash; one last step: complete payment to lock it in.</div><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color:#F2F5FB;"><tr><td align="center" style="padding:32px 16px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="560" style="background-color:#FFFFFF;border-radius:10px;overflow:hidden;max-width:560px;"><tr><td style="background-color:#1B4F8C;background-image:linear-gradient(150deg,#0A1E3D 0%,#1B4F8C 55%,#2B6CB0 100%);padding:36px 40px 32px;text-align:center;"><p style="margin:0 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#F5CC4A;font-weight:bold;">Almost Confirmed</p><h1 style="margin:0;font-family:Georgia,serif;font-size:28px;font-weight:600;color:#ffffff;line-height:1.2;letter-spacing:-0.3px;">Dogs &amp; Llamas</h1><p style="margin:10px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:rgba(255,255,255,0.85);font-style:italic;">One last step &mdash; complete payment to lock it in</p></td></tr><tr><td style="padding:36px 40px 8px;"><p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Hi $H$
      || coalesce(v_req.client_name, 'there')
      || $H$,</p><p style="margin:0 0 24px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Lorenzo has <strong>approved</strong> your booking request for <strong>$H$
      || coalesce(v_req.dog_name, 'your dog')
      || $H$</strong> &mdash; you&rsquo;re almost set! One last step: complete payment using the link below, and we&rsquo;ll send a final confirmation as soon as it clears.</p><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">Booking Summary</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 28px;border-left:4px solid #D4A017;"><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;width:92px;vertical-align:top;">Service</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
      || v_service_label
      || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Dog</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
      || coalesce(v_req.dog_name, '—')
      || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Dates</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
      || coalesce(to_char(v_req.start_date, 'FMMon FMDD'), '—')
      || $H$ &nbsp;&rarr;&nbsp; $H$
      || coalesce(to_char(v_req.end_date, 'FMMon FMDD, YYYY'), '—')
      || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Drop-off</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
      || coalesce(to_char(v_req.drop_off, 'FMHH12:MI AM'), '—')
      || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Pick-up</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
      || coalesce(to_char(v_req.pick_up, 'FMHH12:MI AM'), '—')
      || $H$</td></tr>$H$
      || v_total_line
      || $H$</table><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">How to Pay</p><p style="margin:0 0 16px;font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.65;color:#4C5470;">Pick whichever you&rsquo;re already set up for &mdash; Venmo or Zelle. Either one locks in your booking the moment Lorenzo sees it land.</p>$H$
      || v_venmo_block
      || v_zelle_block
      || $H$<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:6px 0 24px;background-color:#FEF9E7;border:1.5px dashed #D4A017;border-radius:6px;"><tr><td style="padding:12px 18px;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#7A5E0D;line-height:1.55;text-align:center;"><strong>Important:</strong> include the reference <span style="display:inline-block;background:#ffffff;border:1px solid #D4A017;border-radius:4px;padding:2px 8px;font-family:Consolas,Menlo,monospace;font-size:13px;color:#1A1D26;letter-spacing:0.5px;">$H$
      || v_payment_ref
      || $H$</span> in the payment note so we can match it to your booking.</td></tr></table><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">What Happens Next</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;background-color:#E4F0FB;border-radius:6px;"><tr><td style="padding:18px 22px;font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#1A1D26;line-height:1.7;"><p style="margin:0 0 8px;"><strong style="color:#1B4F8C;">1.</strong> &nbsp;<strong>Send payment</strong> via Venmo or Zelle above &mdash; your dates are held while we wait for it.</p><p style="margin:0 0 8px;"><strong style="color:#1B4F8C;">2.</strong> &nbsp;As soon as Lorenzo sees the payment land, you&rsquo;ll get a <strong>final confirmation email</strong> with the address and drop-off details.</p><p style="margin:0 0 8px;"><strong style="color:#1B4F8C;">3.</strong> &nbsp;Reply to either email with anything Lorenzo should know &mdash; feeding schedule, meds, routines, quirks.</p><p style="margin:0;"><strong style="color:#1B4F8C;">4.</strong> &nbsp;Bring food, leash, and any comfort item &mdash; we&rsquo;ll handle the rest.</p></td></tr></table><p style="margin:0 0 4px;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;line-height:1.7;">Can&rsquo;t wait to host $H$
      || coalesce(v_req.dog_name, 'your dog')
      || $H$!</p><p style="margin:0 0 4px;font-family:Georgia,serif;font-size:15px;color:#1A1D26;font-style:italic;">&mdash; Lorenzo &amp; Catalina</p></td></tr><tr><td style="padding:24px 40px 32px;border-top:1px solid #E7ECF5;text-align:center;"><p style="margin:0;font-family:Georgia,serif;font-size:13px;color:#1B4F8C;font-weight:600;letter-spacing:0.3px;">Dogs &amp; Llamas</p><p style="margin:4px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;line-height:1.6;">Lorenzo &amp; Catalina Llamas &middot; All bookings handled in-house</p></td></tr></table></td></tr></table></body></html>$H$;
  else
    v_subject := 'About your booking request with Dogs & Llamas';
    v_html :=
      $H$<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="X-UA-Compatible" content="IE=edge"><title>About your booking request</title></head><body style="margin:0;padding:0;background-color:#F2F5FB;font-family:Arial,Helvetica,sans-serif;"><div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:#F2F5FB;">Sorry &mdash; Lorenzo isn&rsquo;t able to take this booking. Try another window?</div><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color:#F2F5FB;"><tr><td align="center" style="padding:32px 16px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="560" style="background-color:#FFFFFF;border-radius:10px;overflow:hidden;max-width:560px;"><tr><td style="background-color:#1B4F8C;background-image:linear-gradient(150deg,#0A1E3D 0%,#1B4F8C 55%,#2B6CB0 100%);padding:36px 40px 32px;text-align:center;"><p style="margin:0 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#F5CC4A;font-weight:bold;">Booking Update</p><h1 style="margin:0;font-family:Georgia,serif;font-size:28px;font-weight:600;color:#ffffff;line-height:1.2;letter-spacing:-0.3px;">Dogs &amp; Llamas</h1><p style="margin:10px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:rgba(255,255,255,0.85);font-style:italic;">About your recent request</p></td></tr><tr><td style="padding:36px 40px 8px;"><p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Hi $H$
      || coalesce(v_req.client_name, 'there')
      || $H$,</p><p style="margin:0 0 20px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Thank you so much for reaching out about <strong>$H$
      || coalesce(v_req.dog_name, 'your dog')
      || $H$</strong>. Unfortunately Lorenzo isn&rsquo;t able to take this booking &mdash; we&rsquo;re genuinely sorry to miss it.</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;background-color:#E4F0FB;border-radius:6px;border-left:4px solid #D4A017;"><tr><td style="padding:16px 20px;font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#4C5470;line-height:1.6;"><p style="margin:0 0 4px;font-size:11px;font-weight:bold;letter-spacing:0.8px;text-transform:uppercase;color:#8C94B0;">Requested Window</p><p style="margin:0;font-size:15px;color:#1A1D26;font-weight:600;">$H$
      || coalesce(to_char(v_req.start_date, 'FMMon FMDD'), '—')
      || $H$ &nbsp;&rarr;&nbsp; $H$
      || coalesce(to_char(v_req.end_date, 'FMMon FMDD, YYYY'), '—')
      || $H$</p></td></tr></table><p style="margin:0 0 24px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Please feel free to check the calendar again and request another window &mdash; we&rsquo;d love to host $H$
      || coalesce(v_req.dog_name, 'your dog')
      || $H$ on a different date.</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 10px;"><tr><td align="center"><a href="$H$
      || v_schedule_url
      || $H$" style="display:inline-block;background-color:#1B4F8C;background-image:linear-gradient(150deg,#1B4F8C 0%,#2B6CB0 100%);color:#ffffff;font-family:Arial,Helvetica,sans-serif;font-size:14px;font-weight:bold;text-decoration:none;padding:14px 32px;border-radius:99px;letter-spacing:0.5px;">Check other dates &rarr;</a></td></tr></table><p style="margin:24px 0 4px;font-family:Georgia,serif;font-size:15px;color:#1A1D26;font-style:italic;">&mdash; Lorenzo &amp; Catalina</p></td></tr><tr><td style="padding:24px 40px 32px;border-top:1px solid #E7ECF5;text-align:center;"><p style="margin:0;font-family:Georgia,serif;font-size:13px;color:#1B4F8C;font-weight:600;letter-spacing:0.3px;">Dogs &amp; Llamas</p><p style="margin:4px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;line-height:1.6;">Lorenzo &amp; Catalina Llamas &middot; All bookings handled in-house</p></td></tr></table></td></tr></table></body></html>$H$;
  end if;

  v_payload := jsonb_build_object(
    'sender',  jsonb_build_object('name', coalesce(v_sender_name, 'Dogs & Llamas'),
                                   'email', coalesce(v_sender_email, 'no-reply@dogsandllamas.com')),
    'to',      jsonb_build_array(jsonb_build_object('email', v_req.client_email,
                                                    'name',  coalesce(v_req.client_name, ''))),
    'subject', v_subject,
    'htmlContent', v_html
  );

  begin
    perform net.http_post(
      url     := v_fn_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-edge-secret', v_fn_secret),
      body    := v_payload
    );
  exception when others then
    raise warning 'dal_notify_client_of_decision: edge POST failed: %', SQLERRM;
  end;
end;
$$;

-- This helper is called only from dal_decide_booking_request, so no anon grant needed.
revoke all on function public.dal_notify_client_of_decision(public.booking_requests, text) from anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- 10. PAYMENT CONFIRMATION FLOW (Venmo / Zelle manual handoff)
-- ═══════════════════════════════════════════════════════════════════
-- After Lorenzo approves a booking, the client receives the Venmo/Zelle
-- payment instructions. Once the client pays and Lorenzo sees the money
-- land, Lorenzo clicks "Mark Paid" in the admin panel, which:
--   1. Sets paid_at = now() on the booking_request
--   2. Fires dal_notify_client_of_payment() to send the final
--      "You're all set!" confirmation email
--
-- Security: the mark-paid RPC is PIN-gated (same hardcoded '1234' pattern
-- as dal_decide_booking_request) and refuses to flip the state of
-- anything that isn't currently 'approved' + unpaid, so double-marking
-- or marking pending/declined rows is impossible.

-- ── 10a. CLIENT "YOU'RE ALL SET" EMAIL ────────────────────────────
create or replace function public.dal_notify_client_of_payment(
  v_req public.booking_requests
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_sender_email  text;
  v_sender_name   text;
  v_fn_url        text;
  v_fn_secret     text;
  v_pgnet_ok      boolean;
  v_subject       text;
  v_html          text;
  v_payload       jsonb;
  v_service_label text;
begin
  select exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('net','extensions') and p.proname = 'http_post'
  ) into v_pgnet_ok;
  if not v_pgnet_ok then return; end if;

  select value into v_sender_email from public.app_config where key = 'sender_email';
  select value into v_sender_name  from public.app_config where key = 'sender_name';
  select value into v_fn_url       from public.app_config where key = 'email_fn_url';
  select value into v_fn_secret    from public.app_config where key = 'email_fn_secret';
  if v_fn_url is null or v_fn_secret is null or v_req.client_email is null then
    return;
  end if;

  v_service_label := case lower(coalesce(v_req.service, ''))
    when 'boarding'     then 'Overnight boarding'
    when 'daycare'      then 'Daycare'
    when 'dropin'       then 'Drop-in visit'
    when 'walking'      then 'Dog walk'
    when 'housesitting' then 'House-sitting'
    else coalesce(initcap(v_req.service), '—')
  end;

  v_subject := 'You''re all set! Your stay with Dogs & Llamas is confirmed';

  v_html :=
    $H$<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="X-UA-Compatible" content="IE=edge"><title>Booking confirmed</title></head><body style="margin:0;padding:0;background-color:#F2F5FB;font-family:Arial,Helvetica,sans-serif;"><div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:#F2F5FB;">Payment received &mdash; $H$
    || coalesce(v_req.dog_name, 'your dog')
    || $H$&rsquo;s stay with Dogs &amp; Llamas is fully confirmed.</div><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color:#F2F5FB;"><tr><td align="center" style="padding:32px 16px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="560" style="background-color:#FFFFFF;border-radius:10px;overflow:hidden;max-width:560px;"><tr><td style="background-color:#1B4F8C;background-image:linear-gradient(150deg,#0A1E3D 0%,#1B4F8C 55%,#2B6CB0 100%);padding:36px 40px 32px;text-align:center;"><p style="margin:0 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#F5CC4A;font-weight:bold;">Booking Confirmed</p><h1 style="margin:0;font-family:Georgia,serif;font-size:28px;font-weight:600;color:#ffffff;line-height:1.2;letter-spacing:-0.3px;">Dogs &amp; Llamas</h1><p style="margin:10px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:rgba(255,255,255,0.85);font-style:italic;">You&rsquo;re all set &mdash; we can&rsquo;t wait to meet $H$
    || coalesce(v_req.dog_name, 'your pup')
    || $H$</p></td></tr><tr><td style="padding:36px 40px 8px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;"><tr><td align="center"><div style="display:inline-block;width:68px;height:68px;border-radius:50%;background-image:linear-gradient(150deg,#D4A017 0%,#b8880f 100%);color:#ffffff;font-size:36px;line-height:68px;font-weight:bold;text-align:center;box-shadow:0 6px 22px rgba(212,160,23,0.35);">&#10003;</div></td></tr></table><p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;text-align:center;">Hi $H$
    || coalesce(v_req.client_name, 'there')
    || $H$,</p><p style="margin:0 0 24px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;text-align:center;">Your payment came through &mdash; <strong>$H$
    || coalesce(v_req.dog_name, 'your dog')
    || $H$&rsquo;s</strong> stay with us is officially on the books. We&rsquo;re so excited!</p><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">Confirmed Booking</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 28px;border-left:4px solid #D4A017;"><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;width:92px;vertical-align:top;">Service</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || v_service_label
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Dog</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(v_req.dog_name, '—')
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Dates</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(to_char(v_req.start_date, 'FMMon FMDD'), '—')
    || $H$ &nbsp;&rarr;&nbsp; $H$
    || coalesce(to_char(v_req.end_date, 'FMMon FMDD, YYYY'), '—')
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Drop-off</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(to_char(v_req.drop_off, 'FMHH12:MI AM'), '—')
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Pick-up</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(to_char(v_req.pick_up, 'FMHH12:MI AM'), '—')
    || $H$</td></tr></table><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">Before You Drop Off</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;background-color:#E4F0FB;border-radius:6px;"><tr><td style="padding:18px 22px;font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#1A1D26;line-height:1.7;"><p style="margin:0 0 8px;"><strong style="color:#1B4F8C;">&bull;</strong> &nbsp;Lorenzo will reach out the day before drop-off with the address and any last-minute details.</p><p style="margin:0 0 8px;"><strong style="color:#1B4F8C;">&bull;</strong> &nbsp;Reply to this email with anything we should know &mdash; feeding schedule, meds, routines, quirks.</p><p style="margin:0;"><strong style="color:#1B4F8C;">&bull;</strong> &nbsp;Bring food, leash, and any comfort item. We&rsquo;ll handle the rest.</p></td></tr></table><p style="margin:0 0 4px;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;line-height:1.7;text-align:center;">Thank you for trusting us with $H$
    || coalesce(v_req.dog_name, 'your dog')
    || $H$!</p><p style="margin:0 0 4px;font-family:Georgia,serif;font-size:15px;color:#1A1D26;font-style:italic;text-align:center;">&mdash; Lorenzo &amp; Catalina</p></td></tr><tr><td style="padding:24px 40px 32px;border-top:1px solid #E7ECF5;text-align:center;"><p style="margin:0;font-family:Georgia,serif;font-size:13px;color:#1B4F8C;font-weight:600;letter-spacing:0.3px;">Dogs &amp; Llamas</p><p style="margin:4px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;line-height:1.6;">Lorenzo &amp; Catalina Llamas &middot; All bookings handled in-house</p></td></tr></table></td></tr></table></body></html>$H$;

  v_payload := jsonb_build_object(
    'sender',  jsonb_build_object('name', coalesce(v_sender_name, 'Dogs & Llamas'),
                                   'email', coalesce(v_sender_email, 'no-reply@dogsandllamas.com')),
    'to',      jsonb_build_array(jsonb_build_object('email', v_req.client_email,
                                                    'name',  coalesce(v_req.client_name, ''))),
    'subject', v_subject,
    'htmlContent', v_html
  );

  begin
    perform net.http_post(
      url     := v_fn_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-edge-secret', v_fn_secret),
      body    := v_payload
    );
  exception when others then
    raise warning 'dal_notify_client_of_payment: edge POST failed: %', SQLERRM;
  end;
end;
$$;

-- Helper called only from dal_mark_booking_paid — no anon grant needed.
revoke all on function public.dal_notify_client_of_payment(public.booking_requests) from anon, authenticated;


-- ── 10b. LIST AWAITING PAYMENT (admin) ────────────────────────────
-- Lists all bookings that are approved but haven't been marked paid yet.
-- PIN-gated; returns nothing unless the caller knows the PIN.
drop function if exists public.dal_list_awaiting_payment(text);

create or replace function public.dal_list_awaiting_payment(p_pin text)
returns setof public.booking_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_pin text := '1234';
begin
  if p_pin is null or p_pin <> v_admin_pin then
    return;
  end if;
  return query
    select *
    from public.booking_requests
    where status = 'approved'
      and paid_at is null
    order by decided_at desc nulls last, created_at desc;
end;
$$;

comment on function public.dal_list_awaiting_payment(text)
  is 'Admin-only: returns approved bookings that have not yet been marked paid.';


-- ── 10c. MARK BOOKING PAID (admin) ────────────────────────────────
-- Flips an approved booking to "paid" and fires the confirmation email.
drop function if exists public.dal_mark_booking_paid(text, uuid);

create or replace function public.dal_mark_booking_paid(
  p_pin text,
  p_id  uuid
)
returns public.booking_requests
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin_pin text := '1234';
  v_req       public.booking_requests;
begin
  if p_pin is null or p_pin <> v_admin_pin then
    raise exception 'unauthorized';
  end if;

  -- Lock the row so two clicks can't race each other
  select * into v_req
    from public.booking_requests
    where id = p_id
    for update;

  if not found then
    raise exception 'booking % not found', p_id;
  end if;
  if v_req.status <> 'approved' then
    raise exception 'booking % is not approved (status=%)', p_id, v_req.status;
  end if;
  if v_req.paid_at is not null then
    -- Already marked paid — idempotent no-op; return current row.
    return v_req;
  end if;

  update public.booking_requests
    set paid_at = now(),
        paid_by = 'owner'
    where id = p_id
    returning * into v_req;

  -- Fire the "You're all set" confirmation email (fire-and-forget).
  begin
    perform public.dal_notify_client_of_payment(v_req);
  exception when others then
    raise warning 'dal_mark_booking_paid: notify failed: %', SQLERRM;
  end;

  return v_req;
end;
$$;

comment on function public.dal_mark_booking_paid(text, uuid)
  is 'Admin-only: flips an approved booking to paid, fires the final confirmation email.';

grant execute on function public.dal_list_awaiting_payment(text)        to anon, authenticated;
grant execute on function public.dal_mark_booking_paid(text, uuid)      to anon, authenticated;


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
