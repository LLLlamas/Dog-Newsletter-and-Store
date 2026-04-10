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
  created_at    timestamptz default now()
);

comment on table public.booking_requests is
  'Visitor-submitted booking requests. Owner approves/declines via PIN-gated RPC.';

create index if not exists booking_requests_status_idx on public.booking_requests(status);
create index if not exists booking_requests_dates_idx  on public.booking_requests(start_date, end_date);

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
-- 9. EMAIL NOTIFICATIONS  (Brevo via pg_net trigger)
-- ═══════════════════════════════════════════════════════════════════
-- Sends an email to the owner whenever a new booking_request is created.
-- Requires:
--   1. Enable the pg_net extension:
--        Dashboard → Database → Extensions → search "pg_net" → Enable
--   2. Create the app_config table (below) and insert your secrets:
--        insert into app_config(key, value) values
--          ('brevo_api_key',  'xkeysib-YOUR-KEY-HERE'),
--          ('owner_email',    'lorenzoleollamas@gmail.com'),
--          ('owner_name',     'Lorenzo Llamas'),
--          ('sender_email',   'no-reply@dogsandllamas.com'),  -- Brevo verified sender
--          ('sender_name',    'Dogs & Llamas');
--   3. Re-run this whole file so the trigger picks up the config.
--
-- If pg_net is NOT enabled the trigger silently no-ops, so the booking
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
  v_brevo_key   text;
  v_owner_email text;
  v_owner_name  text;
  v_sender_email text;
  v_sender_name  text;
  v_subject     text;
  v_html        text;
  v_payload     jsonb;
  v_pgnet_ok    boolean;
begin
  -- Check pg_net is available
  select exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('net','extensions') and p.proname = 'http_post'
  ) into v_pgnet_ok;
  if not v_pgnet_ok then return new; end if;

  -- Pull config
  select value into v_brevo_key    from public.app_config where key = 'brevo_api_key';
  select value into v_owner_email  from public.app_config where key = 'owner_email';
  select value into v_owner_name   from public.app_config where key = 'owner_name';
  select value into v_sender_email from public.app_config where key = 'sender_email';
  select value into v_sender_name  from public.app_config where key = 'sender_name';

  if v_brevo_key is null or v_owner_email is null then return new; end if;

  v_subject := 'New booking request from ' || new.client_name || ' (' || new.dog_name || ')';
  v_html := format(
    '<h2>New booking request</h2>'
    '<p><strong>Client:</strong> %s &lt;%s&gt;%s</p>'
    '<p><strong>Dog:</strong> %s</p>'
    '<p><strong>Service:</strong> %s</p>'
    '<p><strong>Dates:</strong> %s to %s</p>'
    '<p><strong>Drop-off:</strong> %s &nbsp; <strong>Pick-up:</strong> %s</p>'
    '<p><strong>Notes:</strong><br>%s</p>'
    '<hr><p><a href="https://dogsandllamas.pages.dev/schedule.html">Open the schedule</a> and use admin mode to approve or decline.</p>',
    coalesce(new.client_name, ''),
    coalesce(new.client_email, ''),
    coalesce(' / ' || new.client_phone, ''),
    coalesce(new.dog_name, ''),
    coalesce(new.service, ''),
    coalesce(new.start_date::text, ''),
    coalesce(new.end_date::text, ''),
    coalesce(new.drop_off::text, '—'),
    coalesce(new.pick_up::text, '—'),
    coalesce(new.notes, '(none)')
  );

  v_payload := jsonb_build_object(
    'sender',  jsonb_build_object('name', coalesce(v_sender_name, 'Dogs & Llamas'),
                                   'email', coalesce(v_sender_email, v_owner_email)),
    'to',      jsonb_build_array(jsonb_build_object('email', v_owner_email,
                                                    'name',  coalesce(v_owner_name, ''))),
    'subject', v_subject,
    'htmlContent', v_html
  );

  -- Fire-and-forget POST to Brevo. Wrapped in EXCEPTION so trigger can't block insert.
  begin
    perform net.http_post(
      url     := 'https://api.brevo.com/v3/smtp/email',
      headers := jsonb_build_object('Content-Type', 'application/json', 'api-key', v_brevo_key),
      body    := v_payload
    );
  exception when others then
    raise warning 'dal_notify_owner_of_request: Brevo POST failed: %', SQLERRM;
  end;

  return new;
end;
$$;

drop trigger if exists trg_notify_owner_of_request on public.booking_requests;
create trigger trg_notify_owner_of_request
  after insert on public.booking_requests
  for each row execute function public.dal_notify_owner_of_request();


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
