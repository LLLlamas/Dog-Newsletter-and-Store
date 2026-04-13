# Calendar & Booking System — Technical Reference

> **Purpose:** Portable reference document describing the calendar, booking request flow, email notification system, and payment handoff implemented for the Dogs & Llamas project. Use this to replicate or adapt the system in another project.

---

## Stack & Technologies

| Layer | Technology | Role |
|-------|-----------|------|
| **Frontend** | Vanilla HTML/CSS/JS (no framework) | Static site hosted on GitHub Pages |
| **Database** | Supabase (hosted PostgreSQL) | `booking_requests`, `availability`, `app_config` tables |
| **Auth** | PIN-gated RPCs (no user accounts) | Admin actions require a PIN passed to each RPC |
| **Email relay** | Supabase Edge Function (Deno) → Gmail SMTP | `supabase/functions/send-email/index.ts` |
| **Email transport** | Gmail App Password via `smtp.gmail.com:465` | Using the `denomailer` Deno library |
| **Trigger mechanism** | Postgres `pg_net` extension | `AFTER INSERT` trigger calls the Edge Function via `net.http_post` |
| **Hosting** | GitHub Pages (static) + Supabase (backend) | No server, no build step |
| **Payment** | Venmo deep-link + Zelle manual handoff | No payment processor API; admin manually confirms |

---

## Database Schema

### `availability` table
Stores the calendar state for each day. One row per date.

```sql
create table public.availability (
  day        date primary key,
  status     text not null check (status in ('available','booked','unavailable')),
  dog_name   text,
  drop_off   time,
  pick_up    time,
  notes      text,
  updated_at timestamptz default now()
);
```

- **`available`** — open for booking (rendered as blue circles on the calendar)
- **`booked`** — locked by an approved booking (rendered as gold circles with a dog emoji badge)
- **`unavailable`** — not open (rendered as white circles, same as past dates visually)
- `dog_name`, `drop_off`, `pick_up` are only populated when `status = 'booked'`
- `notes` stores `'Booking #<first-8-chars-of-booking-uuid>'` when booked via the approval flow, which is used to match and delete rows when a booking is cancelled

### `booking_requests` table
Stores every booking request submitted by visitors. Lifecycle: `pending` → `approved` / `declined` / `cancelled`. Payment tracked via `paid_at`.

```sql
create table public.booking_requests (
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
```

### `app_config` table
Private key/value store for secrets and configuration. RLS enabled with zero policies; only `SECURITY DEFINER` functions can read it.

```sql
create table public.app_config (
  key   text primary key,
  value text not null
);
```

**Keys used:**
| Key | Purpose |
|-----|---------|
| `owner_email` | Where owner notification emails are sent |
| `owner_name` | Display name in email "to" field |
| `sender_email` | Gmail address used as the SMTP sender |
| `sender_name` | Display name in email "from" field |
| `email_fn_url` | Full URL of the Supabase Edge Function |
| `email_fn_secret` | Shared secret for `x-edge-secret` header auth |
| `venmo_handle` | Venmo username (no `@`) for deep-link |
| `zelle_display` | Email or phone shown to clients for Zelle |
| `zelle_display_type` | `'email'` or `'phone'` — controls the label |

---

## RPC Functions (Postgres)

All functions are `SECURITY DEFINER` with `search_path = public` (or `public, extensions` when using `pg_net`). Row-level security is enabled on all tables with zero policies — all access goes through these RPCs.

### Public (anon-callable)

| Function | Purpose |
|----------|---------|
| `dal_get_availability(p_from date, p_to date)` | Returns availability rows in the date range. Called on page load to render the calendar. |
| `dal_create_booking_request(...)` | Inserts a new `pending` booking request. Fires the `trg_notify_owner_of_request` trigger. |

### Admin (PIN-gated)

| Function | Purpose |
|----------|---------|
| `dal_verify_admin_pin(p_pin text)` | Returns `true` if PIN matches, `false` otherwise. |
| `dal_set_availability(p_pin, p_date, p_status, ...)` | Sets a single day's availability. Used by the admin state-picker modal. |
| `dal_list_booking_requests(p_pin, p_status)` | Lists booking requests filtered by status. Used for the "Pending" admin panel. |
| `dal_decide_booking_request(p_pin, p_id, p_action)` | Approves or declines a request. On approve: inserts daily rows into `availability` with `status='booked'`. Calls `dal_notify_client_of_decision()`. |
| `dal_list_awaiting_payment(p_pin)` | Lists approved bookings where `paid_at IS NULL`. Used for the "Awaiting Payment" admin panel. |
| `dal_mark_booking_paid(p_pin, p_id)` | Sets `paid_at = now()`. Calls `dal_notify_client_of_payment()` to send the "You're all set" email. Idempotent — double-marking is a no-op. Uses `FOR UPDATE` row lock to prevent races. |
| `dal_cancel_booking_request(p_pin, p_id)` | Soft-cancels a pending or approved booking. Deletes matching `availability` rows (by `notes = 'Booking #<short_id>'`), freeing the calendar dates. Calls `dal_notify_client_of_cancellation()`. |

### Email Helpers (internal only — no anon grant)

| Function | Triggered by | Email sent |
|----------|-------------|------------|
| `dal_notify_owner_of_request()` | `AFTER INSERT` trigger on `booking_requests` | Owner notification: "Sarah just requested Overnight boarding for their dog, Biscuit" |
| `dal_notify_client_of_decision(v_req, p_action)` | Called from `dal_decide_booking_request` | **Approve:** "Almost there — complete payment" with Venmo/Zelle cards. **Decline:** polite "we can't take this booking" with reschedule CTA. |
| `dal_notify_client_of_payment(v_req)` | Called from `dal_mark_booking_paid` | "You're all set!" confirmation with booking details + "Before You Drop Off" tips |
| `dal_notify_client_of_cancellation(v_req)` | Called from `dal_cancel_booking_request` | "Your booking has been cancelled" with "Think this was a mistake? Reply to this email" callout |

---

## Email Relay Architecture

```
Postgres trigger/RPC
  → net.http_post() [pg_net extension, async/fire-and-forget]
    → Supabase Edge Function (supabase/functions/send-email/index.ts)
      → Gmail SMTP (smtp.gmail.com:465, TLS, App Password auth)
        → Client/Owner inbox
```

### Edge Function: `send-email/index.ts`

- **Runtime:** Deno (Supabase Edge Functions)
- **Auth:** `x-edge-secret` header matched against `EDGE_SHARED_SECRET` env var (constant-time compare). JWT verification is disabled in `supabase/config.toml` because `pg_net` can't attach JWTs.
- **Payload shape** (accepted from all SQL email helpers):
  ```json
  {
    "sender": { "name": "Dogs & Llamas", "email": "service@gmail.com" },
    "to": [{ "email": "client@example.com", "name": "Sarah" }],
    "subject": "Your booking is confirmed",
    "htmlContent": "<html>...</html>"
  }
  ```
- **SMTP library:** `denomailer` v1.6.0 (`https://deno.land/x/denomailer@1.6.0/mod.ts`)
- **Gmail behavior:** rewrites `From:` to the authenticated mailbox regardless of what's passed. The caller's `sender.email` is set as `Reply-To`.
- **Error handling:** returns `{ ok: false, error, detail }` with HTTP 502 on SMTP failure. Logs via `console.error` for Edge Function log visibility.

### Supabase Secrets (env vars on the Edge Function)

| Secret | Value |
|--------|-------|
| `GMAIL_USER` | The Gmail address (e.g. `dogsandllamasservice@gmail.com`) |
| `GMAIL_APP_PASSWORD` | 16-char Google App Password (NOT the login password) |
| `EDGE_SHARED_SECRET` | High-entropy random string (32+ chars), same value in `app_config.email_fn_secret` |

### Config file: `supabase/config.toml`

```toml
project_id = "your-project-ref"

[functions.send-email]
verify_jwt = false
```

`verify_jwt = false` is required because `pg_net` calls the function without a JWT. The `x-edge-secret` header is the sole auth gate.

---

## Frontend Calendar Logic

### Data flow

1. **On page load:** `cloudFetchAvailability()` calls `dal_get_availability(today, rangeEnd)` via Supabase REST API. Response is merged into `localStorage` (keyed by `dal_schedule`) and the calendar renders from that cache.
2. **Rendering:** `renderCalendars()` loops over `MONTHS_AHEAD` months from the current month, calling `buildMonth(year, month)` for each. Each day cell gets its state from `getEntry(key)`.
3. **State resolution:** `getEntry(key)` returns `{ status, dogName, dropOff, pickUp }`. If `isPast(key)`, it forces `status: 'past'` regardless of what's in the schedule map.
4. **Visual mapping:** `applyCellState(cell, key)` sets the CSS class (`available`, `booked`, `unavailable`, `past`) and the visitor range-selection overlay classes (`in-range`, `range-end`).

### Past vs. Unavailable

Past and unavailable dates render identically (white circle, lavender border, readable dark text). The only difference:
- **Past:** `cursor: not-allowed`, click is blocked by `if (isPast(key)) return;`
- **Unavailable:** `cursor: not-allowed` for visitors, but `cursor: pointer` in admin mode

### Visitor booking flow (non-admin)

1. User clicks an **available** (blue) day → `handleVisitorPick(key)` sets `visitorPick.start`.
2. User clicks a second available day → extends `visitorPick.end`. Yellow range overlay appears.
3. User selects a service from the dropdown → `updateBookingSummary()` enables the "Confirm Booking" button and adds the `.ready` class (gold pulse animation).
4. User clicks "Confirm Booking →" → `openVisitorModal()` opens the booking details modal pre-filled with dates + service.
5. User fills in dog name, their name, email (required), phone (optional), drop-off/pick-up times, notes → labels turn gold as fields are filled via `vmSyncLabel()`.
6. When dog + name + valid email are all filled, the "Send request" button gets the `.ready` class (same gold pulse as the main CTA).
7. User clicks "Send request" → `submitVisitorRequest()` calls `dal_create_booking_request` via Supabase REST API → trigger fires → owner gets the notification email.

### Admin state-picker modal

Instead of a fixed click-cycle (unavailable → available → booking modal → clear), every admin click opens a **state-picker modal** with three buttons:
- **Mark Available** — commits `{ status: 'available' }`
- **Mark Unavailable** — commits `{ status: 'unavailable' }`
- **Mark as Boarding →** / **Edit boarding details →** — opens the existing booking-details modal (pre-fills dog name + times if editing an existing booking)

The current state's button is greyed out (`.is-current` class, 45% opacity) so the admin can tell at a glance what the day already is.

### Admin pending-requests panel

Visible only in admin mode. Fetches `dal_list_booking_requests(pin, 'pending')` and renders a card for each with Approve / Decline buttons. Approving refreshes the calendar (new booked dates appear) and the awaiting-payment list.

### Admin awaiting-payment panel

Gold-washed card below the pending panel. Fetches `dal_list_awaiting_payment(pin)` and renders cards showing:
- Dog name, total amount with breakdown, service, dates, client contact
- **"Mark Paid — send confirmation email"** button (gold gradient)
- **"Cancel booking"** button (white outline, turns red on hover)

Mark Paid → calls `dal_mark_booking_paid` → removes card → fires "You're all set" email.
Cancel → confirmation dialog → calls `dal_cancel_booking_request` → removes card → fires cancellation email → refreshes calendar (freed dates revert to unavailable).

---

## Payment Flow (Venmo / Zelle manual handoff)

This is NOT an automated payment processor integration. It's a manual handoff:

1. **Approval email** includes two payment "cards":
   - **Venmo card:** one-tap button that deep-links to `venmo.com/{handle}?txn=pay&amount={total}&note={dog's stay with Dogs & Llamas}`. Opens the Venmo app on mobile or venmo.com on desktop with amount and note pre-filled.
   - **Zelle card:** shows the registered email/phone prominently with "open your bank's app and send $X" instructions. No deep-link (Zelle doesn't have one).
2. Client pays via their preferred method.
3. Owner sees the payment land in their Venmo/Zelle app, then clicks **"Mark Paid"** in the admin panel.
4. The system sets `paid_at = now()` on the booking and fires the "You're all set!" confirmation email to the client.

If the client never pays, the owner clicks **"Cancel booking"** which soft-cancels the request, frees the calendar dates, and sends the polite cancellation email.

**Venmo deep-link format:**
```
https://venmo.com/{handle}?txn=pay&amount={total}&note={url-encoded note}
```

---

## Email Template Pattern

All emails share the same visual structure (matching the site's blue/gold theme):

```
┌─────────────────────────────────┐
│  Navy→Blue gradient header      │
│  Yellow eyebrow label           │
│  "Dogs & Llamas" Georgia serif  │
│  Italic subtitle                │
├─────────────────────────────────┤
│  White body card                │
│  Gold-bordered detail table     │
│  Blue-pale info callouts        │
│  Pill-shaped CTA button         │
├─────────────────────────────────┤
│  Light footer with brand name   │
└─────────────────────────────────┘
```

**Colors:** `#0A1E3D` (dark navy), `#1B4F8C` (primary blue), `#2B6CB0` (mid blue), `#D4A017` (gold/yellow), `#F5CC4A` (light yellow), `#E4F0FB` (blue pale), `#F2F5FB` (page background), `#FEF9E7` (yellow pale).

**Fonts:** Georgia/serif for headings, Arial/Helvetica/sans-serif for body (email-safe stack).

All HTML is built via PL/pgSQL string concatenation using `$H$...$H$` dollar-quoting (avoids issues with single quotes in HTML). Currency signs use `&#36;` entity to prevent `$$` conflicts with the outer function-body delimiter.

---

## Pricing Logic

Duplicated in both the SQL email templates and the frontend JS admin panel:

| Service | Unit | Rate | Quantity formula |
|---------|------|------|-----------------|
| Boarding | night | $90 | `max(end_date - start_date, 1)` |
| House-sitting | night | $100 | `max(end_date - start_date, 1)` |
| Daycare | day | $50 | `end_date - start_date + 1` |
| Drop-in | visit | $45 | `end_date - start_date + 1` |
| Walking | walk | $25 | `end_date - start_date + 1` |

Boarding and house-sitting bill per **night** (date difference). Daycare/dropin/walking bill per **day** (inclusive count).

---

## Security Notes

- **Admin PIN is hardcoded** as `'1234'` inside each RPC function body. It's checked via simple string comparison. This is a known weakness — flagged for future improvement (move to an `app_config` lookup or proper auth).
- **`app_config` is RLS-locked** with zero policies and `REVOKE ALL FROM anon, authenticated`. Only SECURITY DEFINER functions can read it.
- **Edge Function auth** uses a shared secret header (`x-edge-secret`), not JWT. The secret must be high-entropy (32+ chars) and stored both as a Supabase secret and in `app_config.email_fn_secret`.
- **`dal_mark_booking_paid` uses `FOR UPDATE` row locking** to prevent race conditions from double-clicks.
- **All email helpers are fire-and-forget** — wrapped in `BEGIN/EXCEPTION` blocks so email failures never roll back the parent transaction.
- **Supabase anon key** is hardcoded in the frontend JS (`dal-subscriber.js`). This is standard for Supabase — the anon key is public, and security is enforced by RLS + function-level grants.

---

## File Map

| File | Purpose |
|------|---------|
| `schedule.html` | Calendar UI, service picker, booking modals, admin panels (all inline CSS/JS) |
| `dal-subscriber.js` | Supabase client init, exposes `DAL._supabase = { url, key }` globally |
| `supabase-schema.sql` | Full database schema, all RPCs, triggers, grants, email templates |
| `supabase-patch-payments.sql` | Standalone patch for the payment flow (idempotent, safe to re-run) |
| `supabase/functions/send-email/index.ts` | Deno Edge Function — Gmail SMTP relay |
| `supabase/config.toml` | Edge Function config (`verify_jwt = false` for `send-email`) |
