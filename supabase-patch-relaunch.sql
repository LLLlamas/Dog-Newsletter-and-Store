-- ═══════════════════════════════════════════════════════════════════
-- RELAUNCH SECURITY PATCH — Dogs & Llamas
-- ═══════════════════════════════════════════════════════════════════
--
-- WHAT THIS DOES
--   1. Admin PIN: removes the hardcoded '1234' from every admin RPC.
--      The PIN is now stored only as a bcrypt hash in a private schema
--      (dal_private, not reachable through the REST API), and checked by
--      one helper, dal_check_admin_pin(), which also enforces a global
--      lockout: more than 10 wrong PINs within 15 minutes locks ALL admin
--      access (even with the right PIN) for 15 minutes.
--   2. Grants: internal helpers (email builders, the trigger function,
--      PIN helpers) are revoked from PUBLIC/anon/authenticated. Before
--      this, anon could call e.g. dal_notify_client_of_decision directly
--      and send arbitrary email through your Gmail. Only the RPCs the site
--      uses are granted to anon/authenticated.
--   3. HTML injection: every user-supplied field (client name, dog name,
--      email, phone, notes) is passed through public.html_escape() in
--      every email template. Subjects have control characters stripped.
--   4. dal_create_booking_request: length caps, email format check,
--      flood throttle (max 20 requests per email per 24h, 60 total per
--      hour), date range sanity, and "today" computed in America/New_York.
--   5. dal_decide_booking_request: only 'pending' requests can be decided,
--      and approval fails if any requested day is already booked by a
--      different booking (instead of silently overwriting it).
--   6. Owner notification emails now carry reply_to = the client's email.
--
-- RUN ORDER
--   supabase-schema.sql  →  supabase-patch-payments.sql  →  THIS FILE.
--   Paste the whole file into the Supabase SQL editor and Run. It is
--   idempotent: safe to re-run at any time. Re-running supabase-schema.sql
--   or supabase-patch-payments.sql later would put '1234' back — if you
--   ever do that, run this file again right after.
--
-- REQUIRED: SET THE ADMIN PIN  (nobody can log in as admin until you do)
--   This patch deliberately sets NO default PIN. Until a PIN is set, every
--   admin check fails (calendar edits, approve/decline, mark paid, etc.).
--   After running this file, open a NEW query in the SQL editor and run:
--
--     select dal_set_admin_pin('your-new-long-passphrase');
--
--   (Delete that query from the SQL editor history afterwards.)
--   dal_set_admin_pin can only be run from the SQL editor — the website's
--   anon key cannot call it. Run it again any time to change the PIN.
--   NOTE: the PIN box on schedule.html currently has maxlength="4"; a
--   longer passphrase needs that attribute removed/raised in the HTML.
--
--   Locked out (e.g. someone hammered the PIN box)? From the SQL editor:
--     select dal_reset_admin_lockout();
--
-- EDGE FUNCTION
--   supabase/functions/send-email/index.ts was updated to honor the new
--   optional `reply_to` field. Redeploy it:
--     supabase functions deploy send-email
--   (Until you do, emails still send — the old function just ignores
--   reply_to and keeps using the sender as Reply-To.)
-- ═══════════════════════════════════════════════════════════════════

-- CHANGE THIS: select dal_set_admin_pin('your-new-long-passphrase');


-- ── 0. EXTENSIONS + PRIVATE SCHEMA ─────────────────────────────────
-- pgcrypto provides crypt()/gen_salt() for bcrypt. On Supabase it lives
-- in the `extensions` schema (already installed on most projects).
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- dal_private is NOT in PostgREST's exposed schemas, and anon has no
-- USAGE on it, so nothing in here is reachable from the website.
create schema if not exists dal_private;
revoke all on schema dal_private from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema dal_private from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on schema dal_private from authenticated';
  end if;
end $$;

-- Single-row table holding the bcrypt hash of the admin PIN.
create table if not exists dal_private.admin_pin (
  id         boolean primary key default true check (id),
  pin_hash   text not null,
  updated_at timestamptz not null default now()
);
revoke all on table dal_private.admin_pin from public;

-- Failed-attempt bookkeeping for the lockout.
-- Why sequences and not a table of attempts: most admin RPCs RAISE on a
-- bad PIN, which rolls back the whole transaction — any row we inserted
-- to record the failure would be rolled back with it, so an attacker
-- could brute-force through those RPCs without ever being counted.
-- Sequence updates (nextval/setval) are NOT rolled back, so the counter
-- survives the caller's exception.
--   pin_fail_count   failures in the current 15-minute window
--   pin_window_start epoch seconds when the current window started
--   pin_locked_until epoch seconds until which all admin checks fail
create sequence if not exists dal_private.pin_fail_count   minvalue 0 start with 0;
create sequence if not exists dal_private.pin_window_start minvalue 0 start with 0;
create sequence if not exists dal_private.pin_locked_until minvalue 0 start with 0;
revoke all on sequence dal_private.pin_fail_count   from public;
revoke all on sequence dal_private.pin_window_start from public;
revoke all on sequence dal_private.pin_locked_until from public;


-- ── 1. HELPERS ─────────────────────────────────────────────────────

-- 1a. HTML-escape user-supplied text before it goes into an email.
--     STRICT: null in → null out, so coalesce(...) defaults still work.
create or replace function public.html_escape(p_text text)
returns text
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select replace(replace(replace(replace(replace(p_text,
           '&', '&amp;'),
           '<', '&lt;'),
           '>', '&gt;'),
           '"', '&quot;'),
           '''', '&#39;');
$$;

comment on function public.html_escape(text) is 'Internal: escapes & < > " '' for safe interpolation into email HTML.';

-- 1b. Percent-encode text for use inside a URL query string (RFC 3986
--     unreserved chars pass through; everything else is %XX of UTF-8).
create or replace function public.dal_url_encode(p_text text)
returns text
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select coalesce(string_agg(
           case when t.ch ~ '^[A-Za-z0-9_.~-]$' then t.ch
                else upper(regexp_replace(encode(convert_to(t.ch, 'UTF8'), 'hex'), '(..)', '%\1', 'g'))
           end, '' order by t.ord), '')
  from regexp_split_to_table(p_text, '') with ordinality as t(ch, ord);
$$;

comment on function public.dal_url_encode(text) is 'Internal: percent-encodes text for URL query parameters.';

-- 1c. THE admin PIN check. Every PIN-gated RPC calls this.
--     Returns false if: no PIN has been set yet, the admin is locked
--     out, or the PIN is wrong. Wrong PINs count toward the lockout.
create or replace function public.dal_check_admin_pin(p_pin text)
returns boolean
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  c_max_failures constant integer := 10;    -- more than this per window → lock
  c_window_secs  constant integer := 900;   -- 15-minute counting window
  c_lock_secs    constant integer := 900;   -- 15-minute lockout
  v_now          bigint := floor(extract(epoch from clock_timestamp()))::bigint;
  v_locked_until bigint;
  v_window_start bigint;
  v_failures     bigint;
  v_hash         text;
begin
  -- 1. Locked out? Reject everything (correct PIN included) until expiry.
  select last_value into v_locked_until from dal_private.pin_locked_until;
  if v_locked_until > v_now then
    raise warning 'dal_check_admin_pin: admin locked out until % (too many failed PIN attempts)',
      to_timestamp(v_locked_until);
    return false;
  end if;

  -- 2. No PIN configured → admin is disabled (see header of this patch).
  select pin_hash into v_hash from dal_private.admin_pin where id;
  if v_hash is null then
    raise warning 'dal_check_admin_pin: no admin PIN set — run select dal_set_admin_pin(...) in the SQL editor';
    return false;
  end if;

  -- 3. Compare (bcrypt). Length guard keeps crypt() input sane.
  if p_pin is not null
     and length(p_pin) between 1 and 200
     and crypt(p_pin, v_hash) = v_hash then
    return true;
  end if;

  -- 4. Wrong PIN: count it (non-transactional, survives caller's RAISE).
  select last_value into v_window_start from dal_private.pin_window_start;
  if v_now - v_window_start >= c_window_secs then
    perform setval('dal_private.pin_window_start', v_now, true);
    perform setval('dal_private.pin_fail_count', 1, true);
    v_failures := 1;
  else
    v_failures := nextval('dal_private.pin_fail_count');
  end if;

  if v_failures > c_max_failures then
    perform setval('dal_private.pin_locked_until', v_now + c_lock_secs, true);
    raise warning 'dal_check_admin_pin: % failed PIN attempts in 15 min — admin locked for 15 min', v_failures;
  end if;

  return false;
end;
$$;

comment on function public.dal_check_admin_pin(text)
  is 'Internal: bcrypt admin PIN check with global lockout (>10 failures / 15 min → 15 min lock). Not callable by anon.';

-- 1d. Set / change the admin PIN. SQL editor only (revoked from all API roles).
create or replace function public.dal_set_admin_pin(p_new_pin text)
returns text
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if p_new_pin is null or length(p_new_pin) < 4 then
    raise exception 'PIN must be at least 4 characters';
  end if;
  if octet_length(p_new_pin) > 72 then
    raise exception 'PIN must be at most 72 bytes (bcrypt limit)';
  end if;
  if p_new_pin in ('1234', '0000', '1111') then
    raise exception 'That PIN is too guessable (and 1234 is in the public git history) — pick another';
  end if;
  if length(p_new_pin) < 12 then
    raise warning 'Short PIN (% chars). A 12+ character passphrase is strongly recommended.', length(p_new_pin);
  end if;

  insert into dal_private.admin_pin (id, pin_hash, updated_at)
  values (true, crypt(p_new_pin, gen_salt('bf', 10)), now())
  on conflict (id) do update
    set pin_hash   = excluded.pin_hash,
        updated_at = excluded.updated_at;

  -- Fresh start for the lockout counters.
  perform setval('dal_private.pin_fail_count',   0, true);
  perform setval('dal_private.pin_window_start', 0, true);
  perform setval('dal_private.pin_locked_until', 0, true);

  return 'Admin PIN updated';
end;
$$;

comment on function public.dal_set_admin_pin(text)
  is 'Owner-only (SQL editor): stores a bcrypt hash of the admin PIN. Not executable by anon/authenticated.';

-- 1e. Clear an active lockout. SQL editor only.
create or replace function public.dal_reset_admin_lockout()
returns text
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
begin
  perform setval('dal_private.pin_fail_count',   0, true);
  perform setval('dal_private.pin_window_start', 0, true);
  perform setval('dal_private.pin_locked_until', 0, true);
  return 'Admin lockout cleared';
end;
$$;

comment on function public.dal_reset_admin_lockout()
  is 'Owner-only (SQL editor): clears the admin PIN lockout counters.';


-- ── 2. AVAILABILITY RPCs (PIN via helper) ──────────────────────────

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
  v_row public.availability;
begin
  if not public.dal_check_admin_pin(p_pin) then
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

create or replace function public.dal_verify_admin_pin(p_pin text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.dal_check_admin_pin(p_pin);
end;
$$;

comment on function public.dal_verify_admin_pin(text) is 'Returns true if the supplied PIN matches the owner PIN (rate-limited via dal_check_admin_pin)';


-- ── 3. BOOKING REQUESTS ────────────────────────────────────────────

-- Indexes for the flood throttle below.
create index if not exists booking_requests_created_idx
  on public.booking_requests(created_at);
create index if not exists booking_requests_email_created_idx
  on public.booking_requests(client_email, created_at);

-- 3a. Public booking form submission (validation + throttle added).
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
  v_row        public.booking_requests;
  v_today      date := (now() at time zone 'America/New_York')::date;
  v_name       text := trim(p_client_name);
  v_email      text := lower(trim(p_client_email));
  v_phone      text := nullif(trim(p_client_phone), '');
  v_dog        text := trim(p_dog_name);
  v_notes      text := nullif(trim(p_notes), '');
  v_recent     integer;
begin
  -- Basic validation
  if v_name  is null or length(v_name)  = 0 then raise exception 'Name required';  end if;
  if v_email is null or length(v_email) = 0 then raise exception 'Email required'; end if;
  if v_dog   is null or length(v_dog)   = 0 then raise exception 'Dog name required'; end if;
  if p_start_date is null or p_end_date is null then raise exception 'Dates required'; end if;
  if p_end_date < p_start_date then raise exception 'End date must be on or after start date'; end if;
  if p_start_date < v_today then raise exception 'Cannot request a date in the past'; end if;
  if p_service not in ('boarding','daycare','dropin','walking','housesitting') then
    raise exception 'Invalid service';
  end if;

  -- Length caps
  if length(v_name)  > 100  then raise exception 'Name is too long (max 100 characters)'; end if;
  if length(v_email) > 254  then raise exception 'Email is too long (max 254 characters)'; end if;
  if length(v_phone) > 40   then raise exception 'Phone is too long (max 40 characters)'; end if;
  if length(v_dog)   > 80   then raise exception 'Dog name is too long (max 80 characters)'; end if;
  if length(v_notes) > 2000 then raise exception 'Notes are too long (max 2000 characters)'; end if;

  -- Format / sanity
  if v_email !~ '^[a-zA-Z0-9._%+''-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' then
    raise exception 'Invalid email address';
  end if;
  if v_name ~ '[[:cntrl:]]' or v_dog ~ '[[:cntrl:]]' or coalesce(v_phone, '') ~ '[[:cntrl:]]' then
    raise exception 'Invalid characters in name, dog name or phone';
  end if;
  if p_end_date - p_start_date > 365 then
    raise exception 'Date range too long (max 1 year)';
  end if;
  if p_start_date > v_today + 730 then
    raise exception 'Cannot request dates more than 2 years ahead';
  end if;

  -- Flood throttle (every request emails the owner)
  select count(*) into v_recent
    from public.booking_requests
   where client_email = v_email
     and created_at > now() - interval '24 hours';
  if v_recent >= 20 then
    raise exception 'Too many requests from this email address today. Please email us directly.';
  end if;

  select count(*) into v_recent
    from public.booking_requests
   where created_at > now() - interval '1 hour';
  if v_recent >= 60 then
    raise exception 'We are receiving too many requests right now. Please try again later.';
  end if;

  insert into public.booking_requests
    (service, client_name, client_email, client_phone,
     dog_name, start_date, end_date, drop_off, pick_up, notes)
  values
    (p_service, v_name, v_email, v_phone,
     v_dog, p_start_date, p_end_date, p_drop_off, p_pick_up, v_notes)
  returning * into v_row;

  return v_row;
end;
$$;

comment on function public.dal_create_booking_request(text,text,text,text,text,date,date,time,time,text)
  is 'Public booking request submission. No PIN required. Length caps + flood throttle.';

-- 3b. Owner list (PIN via helper).
create or replace function public.dal_list_booking_requests(p_pin text, p_status text default 'pending')
returns setof public.booking_requests
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.dal_check_admin_pin(p_pin) then raise exception 'Invalid PIN'; end if;
  return query
    select * from public.booking_requests
    where (p_status is null or status = p_status)
    order by created_at desc;
end;
$$;

comment on function public.dal_list_booking_requests(text, text)
  is 'Owner reads booking requests filtered by status (default pending).';

-- 3c. Approve / decline (pending-only + double-booking guard).
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
  v_req       public.booking_requests;
  v_day       date;
  v_tag       text;
  v_conflicts text;
begin
  if not public.dal_check_admin_pin(p_pin) then raise exception 'Invalid PIN'; end if;
  if p_action not in ('approve','decline') then raise exception 'Invalid action'; end if;

  select * into v_req from public.booking_requests where id = p_id for update;
  if not found then raise exception 'Request not found'; end if;

  if v_req.status <> 'pending' then
    raise exception 'Request % is already % — only pending requests can be approved or declined',
      substring(p_id::text, 1, 8), v_req.status;
  end if;

  v_tag := 'Booking #' || substring(v_req.id::text, 1, 8);

  if p_action = 'approve' then
    -- Serialize approvals so two concurrent approvals can't both pass the check.
    perform pg_advisory_xact_lock(hashtext('dal_availability_booking'));

    select string_agg(to_char(a.day, 'YYYY-MM-DD'), ', ' order by a.day)
      into v_conflicts
      from public.availability a
     where a.day between v_req.start_date and v_req.end_date
       and a.status = 'booked'
       and a.notes is distinct from v_tag;

    if v_conflicts is not null then
      raise exception 'Cannot approve: already booked on % (another booking). Cancel/free those days first or decline this request.',
        v_conflicts;
    end if;
  end if;

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
      values (v_day, 'booked', v_req.dog_name, v_req.drop_off, v_req.pick_up, v_tag, now())
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
  is 'Owner approves or declines a PENDING booking request. Approval marks availability days booked; refuses if any day is already booked by another booking.';


-- ── 4. PAYMENT / CANCEL RPCs (PIN via helper) ──────────────────────

create or replace function public.dal_list_awaiting_payment(p_pin text)
returns setof public.booking_requests
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.dal_check_admin_pin(p_pin) then
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
  v_req       public.booking_requests;
begin
  if not public.dal_check_admin_pin(p_pin) then
    raise exception 'unauthorized';
  end if;

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
    return v_req;
  end if;

  update public.booking_requests
    set paid_at = now(),
        paid_by = 'owner'
    where id = p_id
    returning * into v_req;

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

create or replace function public.dal_cancel_booking_request(
  p_pin text,
  p_id  uuid
)
returns public.booking_requests
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_req       public.booking_requests;
  v_short     text;
begin
  if not public.dal_check_admin_pin(p_pin) then
    raise exception 'unauthorized';
  end if;

  select * into v_req
    from public.booking_requests
    where id = p_id
    for update;

  if not found then
    raise exception 'booking % not found', p_id;
  end if;
  if v_req.status not in ('pending', 'approved') then
    raise exception 'booking % is already %, cannot cancel', p_id, v_req.status;
  end if;

  -- Free the calendar dates that dal_decide_booking_request locked in on approve.
  v_short := substring(v_req.id::text, 1, 8);
  delete from public.availability
    where day between v_req.start_date and v_req.end_date
      and notes = 'Booking #' || v_short;

  update public.booking_requests
    set status     = 'cancelled',
        decided_at = coalesce(decided_at, now()),
        decided_by = coalesce(decided_by, 'owner')
    where id = p_id
    returning * into v_req;

  -- Fire the client cancellation email (fire-and-forget). Wrapped in
  -- its own exception block so an email failure doesn't roll back the
  -- cancellation itself.
  begin
    perform public.dal_notify_client_of_cancellation(v_req);
  exception when others then
    raise warning 'dal_cancel_booking_request: notify failed: %', SQLERRM;
  end;

  return v_req;
end;
$$;

comment on function public.dal_cancel_booking_request(text, uuid)
  is 'Admin-only: soft-cancels a pending/approved booking and frees any locked calendar dates.';


-- ── 5. EMAIL BUILDERS (user fields HTML-escaped) ───────────────────
-- Bodies below are copied verbatim from the latest live versions
-- (supabase-patch-payments.sql §3, §4, §4b, §9 and supabase-schema.sql
-- §10e); the only changes are html_escape()/dal_url_encode() around
-- user-supplied values, plain-text subjects, the owner reply_to, and the
-- PIN check in dal_send_followup.

-- 5a. Owner "new booking request" email (trigger function).
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
  select exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('net','extensions') and p.proname = 'http_post'
  ) into v_pgnet_ok;
  if not v_pgnet_ok then return new; end if;

  select value into v_owner_email  from public.app_config where key = 'owner_email';
  select value into v_owner_name   from public.app_config where key = 'owner_name';
  select value into v_sender_email from public.app_config where key = 'sender_email';
  select value into v_sender_name  from public.app_config where key = 'sender_name';
  select value into v_fn_url       from public.app_config where key = 'email_fn_url';
  select value into v_fn_secret    from public.app_config where key = 'email_fn_secret';

  if v_owner_email is null or v_fn_url is null or v_fn_secret is null then
    return new;
  end if;

  v_service_label := case lower(coalesce(new.service, ''))
    when 'boarding'     then 'Overnight boarding'
    when 'daycare'      then 'Daycare'
    when 'dropin'       then 'Drop-in visit'
    when 'walking'      then 'Dog walk'
    when 'housesitting' then 'House-sitting'
    else coalesce(initcap(new.service), '—')
  end;

  case lower(coalesce(new.service, ''))
    when 'boarding' then
      v_unit_price := 90;  v_unit_label := 'night'; v_quantity := greatest(new.end_date - new.start_date, 1);
    when 'housesitting' then
      v_unit_price := 100; v_unit_label := 'night'; v_quantity := greatest(new.end_date - new.start_date, 1);
    when 'daycare' then
      v_unit_price := 50;  v_unit_label := 'day';   v_quantity := (new.end_date - new.start_date) + 1;
    when 'dropin' then
      v_unit_price := 45;  v_unit_label := 'visit'; v_quantity := (new.end_date - new.start_date) + 1;
    when 'walking' then
      v_unit_price := 25;  v_unit_label := 'walk';  v_quantity := (new.end_date - new.start_date) + 1;
    else
      v_unit_price := 0;   v_unit_label := '';      v_quantity := 0;
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

  if new.client_phone is not null and length(trim(new.client_phone)) > 0 then
    v_phone_block := $H$<br><span style="color:#4C5470;font-size:14px;">$H$ || public.html_escape(new.client_phone) || $H$</span>$H$;
  else
    v_phone_block := '';
  end if;

  if new.notes is not null and length(trim(new.notes)) > 0 then
    v_notes_block :=
      $H$<p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">Notes from Client</p><p style="margin:0 0 28px;font-family:Georgia,serif;font-size:15px;font-style:italic;line-height:1.7;color:#4C5470;border-left:3px solid #D4A017;padding:4px 0 4px 16px;">&ldquo;$H$
      || replace(replace(public.html_escape(new.notes), E'\r\n', E'\n'), E'\n', '<br>')
      || $H$&rdquo;</p>$H$;
  else
    v_notes_block := '';
  end if;

  -- Subject is a mail header (plain text, not HTML): strip control chars.
  v_subject := regexp_replace('New booking request from ' || new.client_name || ' (' || new.dog_name || ')',
                              '[[:cntrl:]]+', ' ', 'g');

  v_html :=
    $H$<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="X-UA-Compatible" content="IE=edge"><title>New booking request</title></head><body style="margin:0;padding:0;background-color:#F2F5FB;font-family:Arial,Helvetica,sans-serif;"><div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:#F2F5FB;">New booking request from $H$
    || coalesce(public.html_escape(new.client_name), 'a client')
    || $H$ for $H$
    || coalesce(public.html_escape(new.dog_name), 'their dog')
    || $H$ &mdash; open the admin view to approve or decline.</div><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color:#F2F5FB;"><tr><td align="center" style="padding:32px 16px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="560" style="background-color:#FFFFFF;border-radius:10px;overflow:hidden;max-width:560px;"><tr><td style="background-color:#1B4F8C;background-image:linear-gradient(150deg,#0A1E3D 0%,#1B4F8C 55%,#2B6CB0 100%);padding:36px 40px 32px;text-align:center;"><p style="margin:0 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#F5CC4A;font-weight:bold;">New Booking Request</p><h1 style="margin:0;font-family:Georgia,serif;font-size:28px;font-weight:600;color:#ffffff;line-height:1.2;letter-spacing:-0.3px;">Dogs &amp; Llamas</h1><p style="margin:10px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:rgba(255,255,255,0.85);font-style:italic;">$H$
    || coalesce(public.html_escape(new.client_name), 'Someone')
    || $H$ just requested $H$
    || coalesce(v_service_label, 'a stay')
    || $H$ for their dog, $H$
    || coalesce(public.html_escape(new.dog_name), 'their pup')
    || $H$</p></td></tr><tr><td style="padding:36px 40px 8px;"><p style="margin:0 0 24px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Hi Lorenzo, a new booking request just came in. Review the details below, then open the admin view to approve or decline.</p><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">Booking Details</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 28px;border-left:4px solid #D4A017;"><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;width:92px;vertical-align:top;">Service</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || v_service_label
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Dog</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(public.html_escape(new.dog_name), '—')
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
    || coalesce(public.html_escape(new.client_name), '—')
    || $H$</strong><br><a href="mailto:$H$
    || coalesce(public.html_escape(new.client_email), '')
    || $H$" style="color:#1B4F8C;text-decoration:none;font-size:14px;">$H$
    || coalesce(public.html_escape(new.client_email), '')
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

  -- Reply-To = the client, so hitting Reply in the owner's inbox goes
  -- straight to them. Ignored by older send-email deployments.
  if new.client_email is not null and length(trim(new.client_email)) > 0 then
    v_payload := v_payload || jsonb_build_object(
      'reply_to', jsonb_build_object(
        'email', new.client_email,
        'name',  regexp_replace(coalesce(new.client_name, ''), '[[:cntrl:]]+', ' ', 'g')));
  end if;

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

-- 5b. Client approve/decline email.
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

  v_service_label := case lower(coalesce(v_req.service, ''))
    when 'boarding'     then 'Overnight boarding'
    when 'daycare'      then 'Daycare'
    when 'dropin'       then 'Drop-in visit'
    when 'walking'      then 'Dog walk'
    when 'housesitting' then 'House-sitting'
    else coalesce(initcap(v_req.service), '—')
  end;

  case lower(coalesce(v_req.service, ''))
    when 'boarding' then
      v_unit_price := 90;  v_unit_label := 'night'; v_quantity := greatest(v_req.end_date - v_req.start_date, 1);
    when 'housesitting' then
      v_unit_price := 100; v_unit_label := 'night'; v_quantity := greatest(v_req.end_date - v_req.start_date, 1);
    when 'daycare' then
      v_unit_price := 50;  v_unit_label := 'day';   v_quantity := (v_req.end_date - v_req.start_date) + 1;
    when 'dropin' then
      v_unit_price := 45;  v_unit_label := 'visit'; v_quantity := (v_req.end_date - v_req.start_date) + 1;
    when 'walking' then
      v_unit_price := 25;  v_unit_label := 'walk';  v_quantity := (v_req.end_date - v_req.start_date) + 1;
    else
      v_unit_price := 0;   v_unit_label := '';      v_quantity := 0;
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

  -- Venmo deep-link: pre-fills amount + friendly note (dog name).
  -- The client just taps the button — no copying required.
  if v_venmo_handle is not null and length(trim(v_venmo_handle)) > 0 then
    v_venmo_url :=
      'https://venmo.com/' || public.dal_url_encode(v_venmo_handle)
      || '?txn=pay'
      || '&amount=' || coalesce(v_total, 0)::text
      || '&note=' || public.dal_url_encode(
                       coalesce(v_req.dog_name, 'Dog') || $Z$'s stay with Dogs & Llamas$Z$);
    v_venmo_block :=
      $H$<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 12px;background-color:#FFFFFF;border:1.5px solid #E4EAFA;border-left:4px solid #D4A017;border-radius:8px;"><tr><td style="padding:18px 20px;font-family:Arial,Helvetica,sans-serif;"><p style="margin:0 0 4px;font-size:10px;font-weight:bold;letter-spacing:1.4px;text-transform:uppercase;color:#D4A017;">Option 1 &middot; Venmo</p><p style="margin:0 0 14px;font-size:17px;font-weight:700;color:#1A1D26;">@$H$
      || public.html_escape(v_venmo_handle)
      || $H$</p><p style="margin:0 0 14px;font-size:13px;color:#4C5470;line-height:1.55;">Tap the button below &mdash; it opens the Venmo app (or venmo.com) with the amount and reference pre-filled.</p><table role="presentation" border="0" cellpadding="0" cellspacing="0"><tr><td><a href="$H$
      || public.html_escape(v_venmo_url)
      || $H$" style="display:inline-block;background-color:#3D95CE;background-image:linear-gradient(150deg,#3D95CE 0%,#2775C9 100%);color:#ffffff;font-family:Arial,Helvetica,sans-serif;font-size:14px;font-weight:bold;text-decoration:none;padding:12px 26px;border-radius:99px;letter-spacing:0.3px;">Pay &#36;$H$
      || v_total::text
      || $H$ on Venmo &rarr;</a></td></tr></table></td></tr></table>$H$;
  else
    v_venmo_block := '';
  end if;

  -- Zelle: identifier + "open your bank" copy. No reference-code ask.
  if v_zelle_display is not null and length(trim(v_zelle_display)) > 0 then
    v_zelle_label := case lower(coalesce(v_zelle_type, 'email'))
      when 'phone' then 'Phone number'
      else 'Email'
    end;
    v_zelle_block :=
      $H$<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 12px;background-color:#FFFFFF;border:1.5px solid #E4EAFA;border-left:4px solid #1B4F8C;border-radius:8px;"><tr><td style="padding:18px 20px;font-family:Arial,Helvetica,sans-serif;"><p style="margin:0 0 4px;font-size:10px;font-weight:bold;letter-spacing:1.4px;text-transform:uppercase;color:#1B4F8C;">Option 2 &middot; Zelle</p><p style="margin:0 0 10px;font-size:11px;font-weight:600;letter-spacing:0.3px;color:#8C94B0;text-transform:uppercase;">$H$
      || v_zelle_label
      || $H$</p><p style="margin:0 0 12px;font-size:17px;font-weight:700;color:#1A1D26;word-break:break-all;">$H$
      || public.html_escape(v_zelle_display)
      || $H$</p><p style="margin:0;font-size:13px;color:#4C5470;line-height:1.55;">Open your bank&rsquo;s app and send <strong>&#36;$H$
      || v_total::text
      || $H$</strong> via Zelle to the address above. No account setup needed on our end &mdash; we&rsquo;ll see it land right away.</p></td></tr></table>$H$;
  else
    v_zelle_block := '';
  end if;

  if p_action = 'approve' then
    v_subject := 'Almost there — complete payment to confirm your stay';
    v_html :=
      $H$<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="X-UA-Compatible" content="IE=edge"><title>Almost confirmed</title></head><body style="margin:0;padding:0;background-color:#F2F5FB;font-family:Arial,Helvetica,sans-serif;"><div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:#F2F5FB;">Lorenzo approved your booking for $H$
      || coalesce(public.html_escape(v_req.dog_name), 'your dog')
      || $H$ &mdash; one last step: complete payment to lock it in.</div><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color:#F2F5FB;"><tr><td align="center" style="padding:32px 16px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="560" style="background-color:#FFFFFF;border-radius:10px;overflow:hidden;max-width:560px;"><tr><td style="background-color:#1B4F8C;background-image:linear-gradient(150deg,#0A1E3D 0%,#1B4F8C 55%,#2B6CB0 100%);padding:36px 40px 32px;text-align:center;"><p style="margin:0 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#F5CC4A;font-weight:bold;">Almost Confirmed</p><h1 style="margin:0;font-family:Georgia,serif;font-size:28px;font-weight:600;color:#ffffff;line-height:1.2;letter-spacing:-0.3px;">Dogs &amp; Llamas</h1><p style="margin:10px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:rgba(255,255,255,0.85);font-style:italic;">One last step &mdash; complete payment to lock it in</p></td></tr><tr><td style="padding:36px 40px 8px;"><p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Hi $H$
      || coalesce(public.html_escape(v_req.client_name), 'there')
      || $H$,</p><p style="margin:0 0 24px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Lorenzo has <strong>approved</strong> your booking request for <strong>$H$
      || coalesce(public.html_escape(v_req.dog_name), 'your dog')
      || $H$</strong> &mdash; you&rsquo;re almost set! One last step: complete payment using the link below, and we&rsquo;ll send a final confirmation as soon as it clears.</p><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">Booking Summary</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 28px;border-left:4px solid #D4A017;"><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;width:92px;vertical-align:top;">Service</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
      || v_service_label
      || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Dog</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
      || coalesce(public.html_escape(v_req.dog_name), '—')
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
      || $H$<p style="margin:16px 0 20px;font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#8C94B0;text-align:center;line-height:1.55;font-style:italic;">That&rsquo;s all &mdash; pick whichever is easier for you and we&rsquo;ll take it from there.</p><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">What Happens Next</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;background-color:#E4F0FB;border-radius:6px;"><tr><td style="padding:18px 22px;font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#1A1D26;line-height:1.7;"><p style="margin:0 0 8px;"><strong style="color:#1B4F8C;">1.</strong> &nbsp;<strong>Send payment</strong> via Venmo or Zelle above &mdash; your dates are held while we wait for it.</p><p style="margin:0 0 8px;"><strong style="color:#1B4F8C;">2.</strong> &nbsp;As soon as Lorenzo sees the payment land, you&rsquo;ll get a <strong>final confirmation email</strong> with the address and drop-off details.</p><p style="margin:0 0 8px;"><strong style="color:#1B4F8C;">3.</strong> &nbsp;Reply to either email with anything Lorenzo should know &mdash; feeding schedule, meds, routines, quirks.</p><p style="margin:0;"><strong style="color:#1B4F8C;">4.</strong> &nbsp;Bring food, leash, and any comfort item &mdash; we&rsquo;ll handle the rest.</p></td></tr></table><p style="margin:0 0 4px;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;line-height:1.7;">Can&rsquo;t wait to host $H$
      || coalesce(public.html_escape(v_req.dog_name), 'your dog')
      || $H$!</p><p style="margin:0 0 4px;font-family:Georgia,serif;font-size:15px;color:#1A1D26;font-style:italic;">&mdash; Lorenzo &amp; Catalina</p></td></tr><tr><td style="padding:24px 40px 32px;border-top:1px solid #E7ECF5;text-align:center;"><p style="margin:0;font-family:Georgia,serif;font-size:13px;color:#1B4F8C;font-weight:600;letter-spacing:0.3px;">Dogs &amp; Llamas</p><p style="margin:4px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;line-height:1.6;">Lorenzo &amp; Catalina Llamas &middot; All bookings handled in-house</p></td></tr></table></td></tr></table></body></html>$H$;
  else
    v_subject := 'About your booking request with Dogs & Llamas';
    v_html :=
      $H$<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="X-UA-Compatible" content="IE=edge"><title>About your booking request</title></head><body style="margin:0;padding:0;background-color:#F2F5FB;font-family:Arial,Helvetica,sans-serif;"><div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:#F2F5FB;">Sorry &mdash; Lorenzo isn&rsquo;t able to take this booking. Try another window?</div><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color:#F2F5FB;"><tr><td align="center" style="padding:32px 16px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="560" style="background-color:#FFFFFF;border-radius:10px;overflow:hidden;max-width:560px;"><tr><td style="background-color:#1B4F8C;background-image:linear-gradient(150deg,#0A1E3D 0%,#1B4F8C 55%,#2B6CB0 100%);padding:36px 40px 32px;text-align:center;"><p style="margin:0 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#F5CC4A;font-weight:bold;">Booking Update</p><h1 style="margin:0;font-family:Georgia,serif;font-size:28px;font-weight:600;color:#ffffff;line-height:1.2;letter-spacing:-0.3px;">Dogs &amp; Llamas</h1><p style="margin:10px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:rgba(255,255,255,0.85);font-style:italic;">About your recent request</p></td></tr><tr><td style="padding:36px 40px 8px;"><p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Hi $H$
      || coalesce(public.html_escape(v_req.client_name), 'there')
      || $H$,</p><p style="margin:0 0 20px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Thank you so much for reaching out about <strong>$H$
      || coalesce(public.html_escape(v_req.dog_name), 'your dog')
      || $H$</strong>. Unfortunately Lorenzo isn&rsquo;t able to take this booking &mdash; we&rsquo;re genuinely sorry to miss it.</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;background-color:#E4F0FB;border-radius:6px;border-left:4px solid #D4A017;"><tr><td style="padding:16px 20px;font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#4C5470;line-height:1.6;"><p style="margin:0 0 4px;font-size:11px;font-weight:bold;letter-spacing:0.8px;text-transform:uppercase;color:#8C94B0;">Requested Window</p><p style="margin:0;font-size:15px;color:#1A1D26;font-weight:600;">$H$
      || coalesce(to_char(v_req.start_date, 'FMMon FMDD'), '—')
      || $H$ &nbsp;&rarr;&nbsp; $H$
      || coalesce(to_char(v_req.end_date, 'FMMon FMDD, YYYY'), '—')
      || $H$</p></td></tr></table><p style="margin:0 0 24px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Please feel free to check the calendar again and request another window &mdash; we&rsquo;d love to host $H$
      || coalesce(public.html_escape(v_req.dog_name), 'your dog')
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

-- 5c. Client "you're all set" payment confirmation email.
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
    || coalesce(public.html_escape(v_req.dog_name), 'your dog')
    || $H$&rsquo;s stay with Dogs &amp; Llamas is fully confirmed.</div><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color:#F2F5FB;"><tr><td align="center" style="padding:32px 16px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="560" style="background-color:#FFFFFF;border-radius:10px;overflow:hidden;max-width:560px;"><tr><td style="background-color:#1B4F8C;background-image:linear-gradient(150deg,#0A1E3D 0%,#1B4F8C 55%,#2B6CB0 100%);padding:36px 40px 32px;text-align:center;"><p style="margin:0 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#F5CC4A;font-weight:bold;">Booking Confirmed</p><h1 style="margin:0;font-family:Georgia,serif;font-size:28px;font-weight:600;color:#ffffff;line-height:1.2;letter-spacing:-0.3px;">Dogs &amp; Llamas</h1><p style="margin:10px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:rgba(255,255,255,0.85);font-style:italic;">You&rsquo;re all set &mdash; we can&rsquo;t wait to meet $H$
    || coalesce(public.html_escape(v_req.dog_name), 'your pup')
    || $H$</p></td></tr><tr><td style="padding:36px 40px 8px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;"><tr><td align="center"><div style="display:inline-block;width:68px;height:68px;border-radius:50%;background-image:linear-gradient(150deg,#D4A017 0%,#b8880f 100%);color:#ffffff;font-size:36px;line-height:68px;font-weight:bold;text-align:center;box-shadow:0 6px 22px rgba(212,160,23,0.35);">&#10003;</div></td></tr></table><p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;text-align:center;">Hi $H$
    || coalesce(public.html_escape(v_req.client_name), 'there')
    || $H$,</p><p style="margin:0 0 24px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;text-align:center;">Your payment came through &mdash; <strong>$H$
    || coalesce(public.html_escape(v_req.dog_name), 'your dog')
    || $H$&rsquo;s</strong> stay with us is officially on the books. We&rsquo;re so excited!</p><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">Confirmed Booking</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 28px;border-left:4px solid #D4A017;"><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;width:92px;vertical-align:top;">Service</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || v_service_label
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Dog</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(public.html_escape(v_req.dog_name), '—')
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Dates</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(to_char(v_req.start_date, 'FMMon FMDD'), '—')
    || $H$ &nbsp;&rarr;&nbsp; $H$
    || coalesce(to_char(v_req.end_date, 'FMMon FMDD, YYYY'), '—')
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Drop-off</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(to_char(v_req.drop_off, 'FMHH12:MI AM'), '—')
    || $H$</td></tr><tr><td style="padding:6px 0 6px 16px;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;text-transform:uppercase;letter-spacing:0.8px;vertical-align:top;">Pick-up</td><td style="padding:6px 0;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(to_char(v_req.pick_up, 'FMHH12:MI AM'), '—')
    || $H$</td></tr></table><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">Before You Drop Off</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;background-color:#E4F0FB;border-radius:6px;"><tr><td style="padding:18px 22px;font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#1A1D26;line-height:1.7;"><p style="margin:0 0 8px;"><strong style="color:#1B4F8C;">&bull;</strong> &nbsp;Lorenzo will reach out the day before drop-off with the address and any last-minute details.</p><p style="margin:0 0 8px;"><strong style="color:#1B4F8C;">&bull;</strong> &nbsp;Reply to this email with anything we should know &mdash; feeding schedule, meds, routines, quirks.</p><p style="margin:0;"><strong style="color:#1B4F8C;">&bull;</strong> &nbsp;Bring food, leash, and any comfort item. We&rsquo;ll handle the rest.</p></td></tr></table><p style="margin:0 0 4px;font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#1A1D26;line-height:1.7;text-align:center;">Thank you for trusting us with $H$
    || coalesce(public.html_escape(v_req.dog_name), 'your dog')
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

-- 5d. Client cancellation email.
create or replace function public.dal_notify_client_of_cancellation(
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
  v_schedule_url  text := 'https://llllamas.github.io/Dog-Newsletter-and-Store/schedule.html';
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

  v_subject := 'Your Dogs & Llamas booking has been cancelled';

  v_html :=
    $H$<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="X-UA-Compatible" content="IE=edge"><title>Booking cancelled</title></head><body style="margin:0;padding:0;background-color:#F2F5FB;font-family:Arial,Helvetica,sans-serif;"><div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:#F2F5FB;">Your booking for $H$
    || coalesce(public.html_escape(v_req.dog_name), 'your dog')
    || $H$ has been cancelled. Reach out if you think this was a mistake.</div><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color:#F2F5FB;"><tr><td align="center" style="padding:32px 16px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="560" style="background-color:#FFFFFF;border-radius:10px;overflow:hidden;max-width:560px;"><tr><td style="background-color:#1B4F8C;background-image:linear-gradient(150deg,#0A1E3D 0%,#1B4F8C 55%,#2B6CB0 100%);padding:36px 40px 32px;text-align:center;"><p style="margin:0 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#F5CC4A;font-weight:bold;">Booking Cancelled</p><h1 style="margin:0;font-family:Georgia,serif;font-size:28px;font-weight:600;color:#ffffff;line-height:1.2;letter-spacing:-0.3px;">Dogs &amp; Llamas</h1><p style="margin:10px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:rgba(255,255,255,0.85);font-style:italic;">We&rsquo;re sorry &mdash; something came up</p></td></tr><tr><td style="padding:36px 40px 8px;"><p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Hi $H$
    || coalesce(public.html_escape(v_req.client_name), 'there')
    || $H$,</p><p style="margin:0 0 20px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">We wanted to let you know that your booking for <strong>$H$
    || coalesce(public.html_escape(v_req.dog_name), 'your dog')
    || $H$</strong> has been cancelled. We&rsquo;re genuinely sorry for any inconvenience this causes.</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;background-color:#E4F0FB;border-radius:6px;border-left:4px solid #D4A017;"><tr><td style="padding:16px 20px;font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#4C5470;line-height:1.6;"><p style="margin:0 0 4px;font-size:11px;font-weight:bold;letter-spacing:0.8px;text-transform:uppercase;color:#8C94B0;">Cancelled Booking</p><p style="margin:0;font-size:15px;color:#1A1D26;font-weight:600;">$H$
    || coalesce(to_char(v_req.start_date, 'FMMon FMDD'), '—')
    || $H$ &nbsp;&rarr;&nbsp; $H$
    || coalesce(to_char(v_req.end_date, 'FMMon FMDD, YYYY'), '—')
    || $H$</p></td></tr></table><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;background-color:#FEF9E7;border:1.5px solid #F0D580;border-radius:6px;"><tr><td style="padding:16px 20px;font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#7A5E0D;line-height:1.6;text-align:center;"><strong>Think this was a mistake?</strong><br>Just reply to this email right away and we&rsquo;ll sort it out together.</td></tr></table><p style="margin:0 0 20px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Otherwise, feel free to check the calendar again whenever you&rsquo;d like to try another date &mdash; we&rsquo;d still love to host $H$
    || coalesce(public.html_escape(v_req.dog_name), 'your dog')
    || $H$ soon.</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 10px;"><tr><td align="center"><a href="$H$
    || v_schedule_url
    || $H$" style="display:inline-block;background-color:#1B4F8C;background-image:linear-gradient(150deg,#1B4F8C 0%,#2B6CB0 100%);color:#ffffff;font-family:Arial,Helvetica,sans-serif;font-size:14px;font-weight:bold;text-decoration:none;padding:14px 32px;border-radius:99px;letter-spacing:0.5px;">Check other dates &rarr;</a></td></tr></table><p style="margin:24px 0 4px;font-family:Georgia,serif;font-size:15px;color:#1A1D26;font-style:italic;">&mdash; Lorenzo &amp; Catalina</p></td></tr><tr><td style="padding:24px 40px 32px;border-top:1px solid #E7ECF5;text-align:center;"><p style="margin:0;font-family:Georgia,serif;font-size:13px;color:#1B4F8C;font-weight:600;letter-spacing:0.3px;">Dogs &amp; Llamas</p><p style="margin:4px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;line-height:1.6;">Lorenzo &amp; Catalina Llamas &middot; All bookings handled in-house</p></td></tr></table></td></tr></table></body></html>$H$;

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
    raise warning 'dal_notify_client_of_cancellation: edge POST failed: %', SQLERRM;
  end;
end;
$$;

-- 5e. Post-stay follow-up email (PIN-gated RPC).
create or replace function public.dal_send_followup(
  p_pin text,
  p_id  uuid
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_req          public.booking_requests;
  v_sender_email text;
  v_sender_name  text;
  v_fn_url       text;
  v_fn_secret    text;
  v_pgnet_ok     boolean;
  v_subject      text;
  v_html         text;
  v_payload      jsonb;
  v_schedule_url text := 'https://llllamas.github.io/Dog-Newsletter-and-Store/schedule.html';
  v_store_url    text := 'https://llllamas.github.io/Dog-Newsletter-and-Store/store.html';
begin
  if not public.dal_check_admin_pin(p_pin) then
    raise exception 'unauthorized';
  end if;

  select * into v_req from public.booking_requests where id = p_id;
  if not found then
    raise exception 'booking % not found', p_id;
  end if;
  if v_req.paid_at is null then
    raise exception 'booking % has not been marked paid yet', p_id;
  end if;

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

  v_subject := regexp_replace('Thanks for trusting us with ' || coalesce(v_req.dog_name, 'your pup') || '!',
                              '[[:cntrl:]]+', ' ', 'g');

  v_html :=
    $H$<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="X-UA-Compatible" content="IE=edge"><title>Thanks for staying</title></head><body style="margin:0;padding:0;background-color:#F2F5FB;font-family:Arial,Helvetica,sans-serif;"><div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:#F2F5FB;">We loved having $H$
    || coalesce(public.html_escape(v_req.dog_name), 'your pup')
    || $H$ &mdash; here are a few things we thought you&rsquo;d like.</div><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color:#F2F5FB;"><tr><td align="center" style="padding:32px 16px;"><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="560" style="background-color:#FFFFFF;border-radius:10px;overflow:hidden;max-width:560px;"><tr><td style="background-color:#1B4F8C;background-image:linear-gradient(150deg,#0A1E3D 0%,#1B4F8C 55%,#2B6CB0 100%);padding:36px 40px 32px;text-align:center;"><p style="margin:0 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#F5CC4A;font-weight:bold;">Post-Stay Note</p><h1 style="margin:0;font-family:Georgia,serif;font-size:28px;font-weight:600;color:#ffffff;line-height:1.2;letter-spacing:-0.3px;">Dogs &amp; Llamas</h1><p style="margin:10px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:rgba(255,255,255,0.85);font-style:italic;">We loved having $H$
    || coalesce(public.html_escape(v_req.dog_name), 'your pup')
    || $H$</p></td></tr><tr><td style="padding:36px 40px 8px;"><p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Hi $H$
    || coalesce(public.html_escape(v_req.client_name), 'there')
    || $H$,</p><p style="margin:0 0 20px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.7;color:#1A1D26;">Just wanted to say <strong>thank you</strong> for trusting us with <strong>$H$
    || coalesce(public.html_escape(v_req.dog_name), 'your pup')
    || $H$</strong>. We genuinely loved every minute &mdash; the walks, the play sessions, and yes, even the zoomies. You&rsquo;ve got an amazing dog.</p><p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase;color:#1B4F8C;">A Couple of Picks for $H$
    || coalesce(public.html_escape(v_req.dog_name), 'Your Pup')
    || $H$</p><p style="margin:0 0 16px;font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.65;color:#4C5470;">Based on what we noticed during the stay, here are a couple of products we think $H$
    || coalesce(public.html_escape(v_req.dog_name), 'your dog')
    || $H$ would love:</p><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 12px;background-color:#FFFFFF;border:1.5px solid #E4EAFA;border-left:4px solid #D4A017;border-radius:8px;"><tr><td style="padding:16px 20px;font-family:Arial,Helvetica,sans-serif;"><p style="margin:0 0 4px;font-size:15px;font-weight:700;color:#1A1D26;">KONG Classic Stuffable Toy</p><p style="margin:0 0 10px;font-size:13px;color:#4C5470;line-height:1.55;">Frozen with peanut butter, it keeps even the most restless dogs happily occupied for 30+ minutes.</p><a href="https://www.amazon.com/KONG-Classic-Durable-Natural-Rubber/dp/B0002AR0I8" style="font-family:Arial,Helvetica,sans-serif;font-size:13px;font-weight:600;color:#1B4F8C;text-decoration:none;" target="_blank" rel="noopener noreferrer sponsored">View on Amazon &rarr;</a></td></tr></table><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;background-color:#FFFFFF;border:1.5px solid #E4EAFA;border-left:4px solid #D4A017;border-radius:8px;"><tr><td style="padding:16px 20px;font-family:Arial,Helvetica,sans-serif;"><p style="margin:0 0 4px;font-size:15px;font-weight:700;color:#1A1D26;">Chuckit! Ultra Ball</p><p style="margin:0 0 10px;font-size:13px;color:#4C5470;line-height:1.55;">The most durable fetch ball I&rsquo;ve found &mdash; it bounces higher, floats, and doesn&rsquo;t grind down tooth enamel like tennis balls.</p><a href="https://www.amazon.com/Chuckit-Ultra-Squeaker-Ball-Medium/dp/B00UNLOWK0" style="font-family:Arial,Helvetica,sans-serif;font-size:13px;font-weight:600;color:#1B4F8C;text-decoration:none;" target="_blank" rel="noopener noreferrer sponsored">View on Amazon &rarr;</a></td></tr></table><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 24px;background-color:#FEF9E7;border:1.5px solid #F0D580;border-radius:6px;"><tr><td style="padding:16px 20px;font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#7A5E0D;line-height:1.6;text-align:center;"><strong style="color:#1A1D26;">Returning client perk:</strong> mention <strong style="color:#D4A017;">PUPS10</strong> when you book your next stay for <strong>10% off</strong>. We&rsquo;d love to have $H$
    || coalesce(public.html_escape(v_req.dog_name), 'your pup')
    || $H$ back.</td></tr></table><table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%"><tr><td align="center" style="padding:0 0 8px;"><a href="$H$
    || v_schedule_url
    || $H$" style="display:inline-block;background-color:#1B4F8C;background-image:linear-gradient(150deg,#1B4F8C 0%,#2B6CB0 100%);color:#ffffff;font-family:Arial,Helvetica,sans-serif;font-size:14px;font-weight:bold;text-decoration:none;padding:14px 32px;border-radius:99px;letter-spacing:0.5px;">Book again &rarr;</a></td></tr><tr><td align="center"><a href="$H$
    || v_store_url
    || $H$" style="display:inline-block;font-family:Arial,Helvetica,sans-serif;font-size:13px;font-weight:600;color:#1B4F8C;text-decoration:none;padding:8px 20px;">Browse all sitter picks &rarr;</a></td></tr></table><p style="margin:20px 0 4px;font-family:Georgia,serif;font-size:15px;color:#1A1D26;font-style:italic;text-align:center;">&mdash; Lorenzo &amp; Catalina</p></td></tr><tr><td style="padding:24px 40px 32px;border-top:1px solid #E7ECF5;text-align:center;"><p style="margin:0;font-family:Georgia,serif;font-size:13px;color:#1B4F8C;font-weight:600;letter-spacing:0.3px;">Dogs &amp; Llamas</p><p style="margin:4px 0 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#8C94B0;line-height:1.6;">Lorenzo &amp; Catalina Llamas &middot; All bookings handled in-house</p></td></tr></table></td></tr></table></body></html>$H$;

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
    raise warning 'dal_send_followup: edge POST failed: %', SQLERRM;
  end;
end;
$$;

comment on function public.dal_send_followup(text, uuid)
  is 'Admin-only: sends the post-stay follow-up email with product recommendations and PUPS10 loyalty code.';


-- ── 6. GRANTS ──────────────────────────────────────────────────────
-- Supabase gives every new function in `public` EXECUTE to PUBLIC and,
-- via default privileges, to anon/authenticated too. Internal helpers
-- must be revoked from all three.

-- 6a. Internal helpers — never callable from the website.
revoke all on function public.html_escape(text)                                       from public, anon, authenticated;
revoke all on function public.dal_url_encode(text)                                    from public, anon, authenticated;
revoke all on function public.dal_check_admin_pin(text)                               from public, anon, authenticated;
revoke all on function public.dal_set_admin_pin(text)                                 from public, anon, authenticated, service_role;
revoke all on function public.dal_reset_admin_lockout()                               from public, anon, authenticated, service_role;
revoke all on function public.dal_notify_owner_of_request()                           from public, anon, authenticated;
revoke all on function public.dal_notify_client_of_decision(public.booking_requests, text) from public, anon, authenticated;
revoke all on function public.dal_notify_client_of_payment(public.booking_requests)  from public, anon, authenticated;
revoke all on function public.dal_notify_client_of_cancellation(public.booking_requests) from public, anon, authenticated;

-- 6b. Public RPCs the site calls (dal-subscriber.js, index.html, schedule.html).
grant execute on function public.dal_subscribe(text)                                                         to anon, authenticated;
grant execute on function public.dal_lookup(text)                                                            to anon, authenticated;
grant execute on function public.dal_get_availability(date, date)                                            to anon, authenticated;
grant execute on function public.dal_set_availability(text, date, text, text, time, time, text)              to anon, authenticated;
grant execute on function public.dal_verify_admin_pin(text)                                                  to anon, authenticated;
grant execute on function public.dal_create_booking_request(text,text,text,text,text,date,date,time,time,text) to anon, authenticated;
grant execute on function public.dal_list_booking_requests(text, text)                                       to anon, authenticated;
grant execute on function public.dal_decide_booking_request(text, uuid, text)                                to anon, authenticated;
grant execute on function public.dal_list_awaiting_payment(text)                                             to anon, authenticated;
grant execute on function public.dal_mark_booking_paid(text, uuid)                                           to anon, authenticated;
grant execute on function public.dal_cancel_booking_request(text, uuid)                                      to anon, authenticated;
grant execute on function public.dal_send_followup(text, uuid)                                               to anon, authenticated;

-- 6c. Catch-all: any OTHER dal_* function in public (e.g. a stale
--     overload from an older schema version that may still contain
--     '1234') loses PUBLIC/anon/authenticated EXECUTE.
do $$
declare
  v_allow oid[];
  r       record;
begin
  select array_agg(o) into v_allow
  from (
    select to_regprocedure(x) as o
    from unnest(array[
      'public.dal_subscribe(text)',
      'public.dal_lookup(text)',
      'public.dal_get_availability(date,date)',
      'public.dal_set_availability(text,date,text,text,time,time,text)',
      'public.dal_verify_admin_pin(text)',
      'public.dal_create_booking_request(text,text,text,text,text,date,date,time,time,text)',
      'public.dal_list_booking_requests(text,text)',
      'public.dal_decide_booking_request(text,uuid,text)',
      'public.dal_list_awaiting_payment(text)',
      'public.dal_mark_booking_paid(text,uuid)',
      'public.dal_cancel_booking_request(text,uuid)',
      'public.dal_send_followup(text,uuid)'
    ]) as x
  ) s
  where o is not null;

  for r in
    select p.oid::regprocedure as fn
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'dal\_%'
      and p.prokind = 'f'
      and not (p.oid = any (v_allow))
  loop
    execute format('revoke all on function %s from public', r.fn);
    if exists (select 1 from pg_roles where rolname = 'anon') then
      execute format('revoke all on function %s from anon', r.fn);
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
      execute format('revoke all on function %s from authenticated', r.fn);
    end if;
  end loop;
end $$;


-- ═══════════════════════════════════════════════════════════════════
-- VERIFY (optional, run after the patch):
--
--   -- No function body should still use a hardcoded PIN:
--   select p.oid::regprocedure from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.prosrc like '%v_admin_pin%';
--   -- expect 0 rows
--
--   -- Which dal_* functions can the website (anon) call?
--   select p.oid::regprocedure, has_function_privilege('anon', p.oid, 'execute')
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.proname like 'dal\_%' order by 1;
--   -- expect true only for the 12 RPCs granted in §6b
--
--   -- Is a PIN set?
--   select updated_at from dal_private.admin_pin;
-- ═══════════════════════════════════════════════════════════════════
