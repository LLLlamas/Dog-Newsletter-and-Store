# Dogs & Llamas — Project Handoff
**Date:** April 10, 2026 (updated late session)
**Prepared for:** Codex / next AI session
**Project:** Dogs & Llamas — Lorenzo & Catalina Llamas's husband-and-wife dog-sitting business. Newsletter, booking/availability hub, photo gallery, about page, and curated affiliate product store.

---

## 1. What This Project Is

A static multi-page website + email newsletter system for **Lorenzo & Catalina Llamas**, a husband-and-wife team of **Rover Star Sitters** currently earning their dog training certification. Brand: **"Dogs & Llamas."** Rover profile: <https://www.rover.com/sit/lorenl45629>.

Focus services (highlighted with ⭐ "Our Favorite" labels on the schedule page):
- **Dog Boarding** — $90/night (in our home)
- **Doggy Day Care** — $50/day (in our home)

Supporting services:
- Drop-In Visits — $45/visit
- Dog Walking — $25/walk
- House Sitting — $100/night

Six public pages:

| Page | Purpose |
|---|---|
| `index.html` | Newsletter hub, hero + subscribe, dog grid, testimonials, store teaser, coupons |
| `schedule.html` | **Calendar first**, then service dropdown, then Rover booking CTA. Sitter edits calendar via PIN-gated admin mode |
| `gallery.html` | Masonry photo gallery with filter + lightbox, "photography services coming soon" teaser |
| `about.html` | Couple bio, Star Sitter + dog training cert badges, values, dog chips, Rover CTA |
| `store.html` | Curated Amazon affiliate product picks with filter + pagination |
| `privacy.html` | Privacy policy (shared nav, blue/yellow design) |

**Rover-safe framing**: all bookings go through Rover.com. No off-platform booking language anywhere.

**Tech stack:** Pure static HTML + CSS + vanilla JS. No framework, no build step. Deploys to GitHub Pages, Netlify, or Cloudflare Pages.

---

## 2. File Structure

```
/Dog Newsletter and Store/
├── index.html                    ← Newsletter hub / landing
├── schedule.html                 ← Calendar-first + service dropdown (admin editable via PIN)
├── gallery.html                  ← Masonry photo gallery + lightbox + filter
├── about.html                    ← About Lorenzo & Catalina
├── store.html                    ← Curated Amazon picks
├── privacy.html                  ← Privacy policy
├── newsletter-template.html      ← Monthly email template (blue/yellow rebranded)
├── welcome-email.html            ← One-time welcome email (blue/yellow rebranded)
├── monthly-issue-01.html         ← April 2026 issue (blue/yellow rebranded)
├── mini-update-01.html           ← Short-form mid-month template (blue/yellow rebranded)
├── _headers                      ← Netlify/Cloudflare security headers
├── dogsitter_newsletter_project_brief.md
├── chatgpt takeover 4-9-2026.md  ← Original handoff
├── chatgpt takeover 4-10-2026.md ← THIS FILE (latest)
├── dal-subscriber.js             ← Subscriber / login / personalization system v2.0
├── supabase-schema.sql           ← Run this in Supabase SQL Editor to create tables + RPC + seed data
└── media/
    ├── Turbo Outside.jpg         ← Hero main, store pick 2, dogs grid
    ├── Turbo sleeping.JPG        ← Gallery
    ├── Troy.jpg                  ← Hero secondary, dogs grid
    ├── Dakota and me.JPG         ← About hero, gallery (placeholder until couple portrait)
    ├── Ace.DNG                   ← RAW — convert via cloudconvert.com
    ├── Mango Outside.DNG         ← RAW — convert
    └── Teddy.DNG                 ← RAW — convert
```

---

## 3. Design System — Blue & Yellow (Dog Vision Palette)

Inspired by research that dogs primarily see shades of blue, yellow, and gray.

### Fonts

- **Display / headings:** `Playfair Display` **600 weight, roman (not italic)** — used at larger sizes with tight negative letter-spacing for presence. Italic is reserved for the small decorative brand wordmark (nav-brand, footer-brand) and the stylized `&` ampersand only.
- **Body / UI / long text:** `DM Sans` — clean, modern, highly legible. Used for all body copy, subtitles, card descriptions, value cards, bios on dark heroes.
- **Email templates:** body font is **Arial/Helvetica** (email-client safe). Headline wordmark uses Georgia 600.

> Late in the April 10 session, the site was audited for italic Playfair Display overuse (hard to read at body sizes). All large italic headings and long italic body copy on dark backgrounds were converted to either Playfair roman 600 (headings) or DM Sans (body). See `§ 15`.

### Color Tokens (shared across all 6 HTML pages)

```css
:root {
  --bg:          #F2F5FB;   /* cool soft ice blue */
  --bg-2:        #E4EAFA;
  --surface:     #FFFFFF;
  --blue:        #1B4F8C;   /* primary deep navy */
  --blue-mid:    #2B6CB0;
  --blue-light:  #6BA3D6;
  --blue-pale:   #E4F0FB;
  --yellow:      #D4A017;   /* accent — all CTAs */
  --yellow-light:#F5CC4A;   /* nav accent, hero highlights */
  --yellow-pale: #FEF9E7;   /* coupon/callout backgrounds */
  --text:        #1A1D26;
  --text-2:      #4C5470;
  --text-3:      #8C94B0;
  --border:      #CCDAEF;
  --shadow-sm:   0 2px 8px rgba(27,79,140,.08);
  --shadow-md:   0 6px 24px rgba(27,79,140,.12);
  --shadow-lg:   0 12px 40px rgba(27,79,140,.16);
  --radius-sm:   8px;
  --radius-md:   14px;
  --radius-lg:   20px;
  --radius-full: 99px;
  --font-head:   'Playfair Display', Georgia, serif;
  --font-body:   'DM Sans', system-ui, sans-serif;
  --nav-h:       62px;
}
```

> `store.html` retains legacy `--green` / `--amber` variable name aliases (pointing at the blue/yellow values) for backward compatibility with pre-refactor rules. Both naming conventions resolve to the same values.

### Hero gradient (all pages)

```css
background: linear-gradient(150deg, #0A1E3D 0%, #1B4F8C 55%, #2B6CB0 100%);
```
With a radial dot overlay via `::before` (24px spacing).

### Footer

```css
background: #081529;
```

---

## 4. Shared Navigation

All 6 HTML pages use an **identical nav** with 4 main tabs + Subscribe CTA. Hamburger kicks in at `max-width: 820px`.

```html
<nav>
  <a href="index.html" class="nav-brand">Dogs <span class="amp">&amp;</span> Llamas</a>
  <button class="nav-toggle" id="nav-toggle" aria-label="Open menu" aria-expanded="false">☰</button>
  <div class="nav-links" id="nav-links">
    <a href="schedule.html" class="nav-link">Schedule</a>
    <a href="gallery.html"  class="nav-link">Gallery</a>
    <a href="about.html"    class="nav-link">About</a>
    <a href="store.html"    class="nav-link">Shop</a>
    <a href="index.html#subscribe" class="nav-cta">Subscribe</a>
  </div>
</nav>
```

Add `class="nav-link active"` to the current page's link on each page.

### Personalize button (NEW — all 6 pages)

A `🐾 [username]` button appears **next to the nav brand** — only when the user has subscribed. When clicked, it toggles `dal-personalized` on `<body>`.

```html
<button class="dal-personalize-btn" id="dal-personalize-btn" type="button"
        style="display:none"
        onclick="DAL && DAL.onPersonalizeBtnClick()"
        title="Toggle personalized view"
        aria-label="Toggle personalized view">
  🐾 <span class="dal-btn-label">you</span>
</button>
```

All 6 pages also include `<script src="dal-subscriber.js" defer></script>` and an ARIA live region `#dal-live-region`.

Shared JS:
```javascript
document.getElementById('nav-toggle').addEventListener('click', function () {
  var links = document.getElementById('nav-links');
  var open = links.classList.toggle('open');
  this.setAttribute('aria-expanded', String(open));
});
```

---

## 5. Responsive Breakpoints

Three-tier mobile-first scaling applied to every page:

| Breakpoint | Range | Behavior |
|---|---|---|
| Desktop (default) | `≥ 961px` | Full nav, multi-column grids, large hero |
| Tablet | `≤ 960px` | Tighter padding, 2-col grids |
| Mobile | `≤ 820px` | Hamburger menu, single/2-col grids, stacked hero |
| Small mobile | `≤ 480px` | Single-column, reduced type, stacked forms |

Every page also includes:

```css
/* Accessibility — shared */
:focus-visible {
  outline: 3px solid var(--yellow-light);
  outline-offset: 3px;
  border-radius: 4px;
}
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: .001ms !important;
    transition-duration: .001ms !important;
    scroll-behavior: auto !important;
  }
}
```

`index.html` also has a **skip-to-main-content** link for keyboard users.

---

## 6. Micro-interactions & Animations

Added late in the April 10 session to give the site warmth and feedback without being noisy. All animations respect `prefers-reduced-motion` (a late block in every page's stylesheet cancels them if the user opts out).

### Shared keyframes (in every page's style block, near the ACCESSIBILITY section)

```css
@keyframes dal-fade-up   { from { opacity: 0; transform: translateY(14px); } to { opacity: 1; transform: translateY(0); } }
@keyframes dal-pop       { 0% { transform: scale(1); } 45% { transform: scale(1.22); } 100% { transform: scale(1); } }
@keyframes dal-pulse     { 0% { box-shadow: 0 0 0 0 rgba(212,160,23,.55); } 80% { box-shadow: 0 0 0 18px rgba(212,160,23,0); } 100% { box-shadow: 0 0 0 0 rgba(212,160,23,0); } }
@keyframes dal-wiggle    { 0%,100% { transform: rotate(0); } 25% { transform: rotate(-3.5deg); } 50% { transform: rotate(3.5deg); } 75% { transform: rotate(-2deg); } }
@keyframes dal-paw-walk  { 0% { transform: translateY(0) rotate(0); } 50% { transform: translateY(-5px) rotate(-5deg); } 100% { transform: translateY(0) rotate(0); } }
```

### Global effects (all pages)

| Interaction | Effect |
|---|---|
| Page load | `main` / `.page-wrap` fade-up over 550ms |
| Nav brand hover | `dal-wiggle` — playful 500ms wiggle |
| Nav link hover / active | Yellow underline slides in from center (`::after` scaleX transition) |
| `.dal-pop` class | JS-triggered 420ms pop scale (1 → 1.22 → 1) with bouncy cubic-bezier |

### Page-specific effects

**index.html**
- Primary CTAs (`.btn-primary`, `.issue-read-link`, `.hero-form button`): `dal-pulse` welcome ring, 2 iterations on page load then stops
- Dog cards: on hover, photo runs `dal-paw-walk` (gentle lift + rotate)
- Perk-strip icons: `dal-paw-walk` on hover
- Coupon codes: `dal-wiggle` on hover (subtle "try me" gesture)

**store.html**
- `.btn-amazon`, `.pick-cta`: `dal-pulse` welcome ring × 2 on load
- Filter buttons: hover `translateY(-1px)`, active `scale(.95)`, JS adds `.dal-pop` on click for a tactile pop
- Product-img icons: `dal-paw-walk` on card hover

**about.html**
- Credential badges (Star Sitter, Training Cert, Background Checked): **stagger-in** animation on load (150ms, 300ms, 450ms delays)
- Value-card icons: `dal-paw-walk` on hover
- Dog chips: `dal-wiggle` on hover
- Hero photo: gentle rock (`dal-wiggle`) on hover
- `.rover-link` / `.btn-rover`: `dal-pulse` welcome ring × 2 on load

**schedule.html**
- Calendar months: stagger-in (`dal-month-slide`) with 50ms/150ms/250ms delays
- **Calendar day click**: bounce animation (`dal-cal-bounce`: scale 1 → 1.35 → .92 → 1) via JS-added `.dal-bounce` class, triggered on any future-date click — works in both view-only and admin mode
- `.cal-day.available:hover`: lifts to `scale(1.14)` with soft blue shadow
- Service select: hover `translateY(-1px)`
- Service detail pane: slides in with opacity + translateY + max-height when a service is picked
- `.btn-book`: `dal-pulse` welcome ring × 2 on load
- Admin FAB (⚙): 60° spin on hover
- Legend dots: `dal-pop` on hover

**gallery.html**
- Gallery items: `translateY(-4px) rotate(-.8deg)` + shadow lift on hover
- Filter buttons: hover translate + JS `.dal-pop` on click
- Lightbox: `dal-lightbox-in` (scale .92 → 1 + opacity) on open

**privacy.html**
- Page fade-up, nav brand wiggle, nav underline slide (no loud effects — legal page stays calm)

### JavaScript hooks

Two JS handlers add `.dal-pop` / `.dal-bounce` classes briefly:

**schedule.html** (inside `cell.addEventListener('click', ...)`):
```javascript
if (!isPast(key)) {
  cell.classList.remove('dal-bounce');
  void cell.offsetWidth;  /* restart animation */
  cell.classList.add('dal-bounce');
  setTimeout(function() { cell.classList.remove('dal-bounce'); }, 520);
}
```

**store.html** and **gallery.html** (inside filter button click handlers):
```javascript
btn.classList.remove('dal-pop');
void btn.offsetWidth;
btn.classList.add('dal-pop');
setTimeout(function () { btn.classList.remove('dal-pop'); }, 420);
```

---

## 7. Page-by-Page Notes (post-April-10)

### index.html
- Hero byline: "by Lorenzo & Catalina Llamas • Rover Star Sitters"
- Polaroid Turbo (main) + Troy (secondary) in hero
- Perks, What You'll Get pillars, Latest Issue preview
- Our Recent Dogs grid: Turbo (only once), Troy, Dakota, + Ace/Mango/Harley placeholders
- Testimonial copy uses plural ("Lorenzo & Catalina always take...")
- Footer: "Lorenzo & Catalina Llamas • Rover Star Sitters"

### schedule.html *(redesigned in April 10 session)*
- **Layout order changed:** Hero → Calendar (Step 1) → Service dropdown (Step 2) → Rover CTA
- Removed: old service-tile grid (4 tiles), trust note paragraph, "$25K vet coverage" line
- Calendar: 3 months, blue available / gray booked / amber today ring
- Service picker card below calendar with `<select>` dropdown
- When a service is selected, a yellow-accented detail pane slides in showing name + price + description. **Dog Boarding & Doggy Day Care** include a "⭐ Our Favorite" badge
- Services JS object (`SERVICES`) defines rates:
  - `boarding` — $90/night (focus: true)
  - `daycare` — $50/day (focus: true)
  - `dropin` — $45/visit
  - `walking` — $25/walk
  - `housesitting` — $100/night
- Admin mode: ⚙ FAB → PIN modal (default `1234` — CHANGE IT)
- LocalStorage: `dal_schedule` (JSON `{ "YYYY-MM-DD": status }`) and `dal_admin_pin`
- Click any future date → `dal-bounce` animation; in admin mode, also cycles through available → booked → unavailable

### gallery.html
- CSS masonry `columns: 4 240px`
- Filter: All, Outdoors, Portraits, Action, Rest & Play
- Each item has `data-tags`, `data-name`, `data-caption`
- Click real photo → lightbox (ESC / click-outside closes)
- 4 real photos + 4 placeholders
- Tablet: 3 columns; mobile: 2 columns; small: 2 narrow
- Footer: "Lorenzo & Catalina Llamas • Photos shared with client permission"

### about.html *(rewritten for couple in April 10 session)*
- Title: "About Us — Dogs & Llamas"
- Hero name: "Lorenzo & Catalina" (eyebrow "Meet Your Sitters")
- Tagline: "Rover Star Sitters • Dog Walkers • Training Students"
- Badge row: ⭐ Rover Star Sitters, 🎓 Dog Training Cert (In Progress), 🛡️ Background Checked
- Stat bar placeholders: `[X]` Happy Dogs, ⭐ Star (Rover Star Sitter), `[X]` 5-Star Reviews, `[X]+` Stays Completed
- Bio rewritten in plural (we/our/us); removed "A note on trust" paragraph entirely
- **Certification callout card** (yellow left border) reiterates the in-progress credential
- 6 value cards: Photo Updates, Your Dog's Routine, Always Reachable, Training-Informed, **Two Sets of Hands** (new — replaces Rover-Covered), Genuinely Personal
- Dog chips: Turbo, Troy, Dakota, Harley, Ace, Mango
- Rover CTA card: no more "$25K vet coverage" footer line

### store.html *(picks sidebar + hover shadow updated)*
- Affiliate disclosure bar + personalized welcome bar (`.dal-welcome-bar`, hidden by default) + coupon bar (`SHOP10`)
- Sticky filter bar at `top: var(--nav-h)` with 10 filter tags
- **Personal Picks redesigned**: now compact sidebar (≥960px) / collapsible one-liner (<960px)
  - Two-column layout: `.main-with-picks { grid-template-columns: 1fr 256px }`
  - Picks section: `.picks-section` is `position: sticky; top: calc(var(--nav-h) + var(--filter-h) + 16px)` on wide
  - Narrow: collapse button with `aria-expanded`, clicks toggle `.picks-inner.open` class
  - Each pick: compact `.pick-item` with 50×50 `.pick-item-thumb` (emoji or centered `object-fit:cover` photo)
- **Product card hover**: removed `transform: translateY(-3px)` tilt; replaced with enhanced shadow `0 8px 32px rgba(27,79,140,.2)`
- 15-product grid with JS pagination (6 per page on "All", show-all for filtered)
- Each card has ASIN in HTML comment + `rel="sponsored noopener noreferrer"`
- Subscribe banner wired to `DAL.handleSubscribe()` → shows toast with username + discount code
- Share row + footer: "Lorenzo & Catalina Llamas • Rover Star Sitters"

### privacy.html *(rebuilt in April 9 session)*
- Blue/yellow design system + shared nav
- Intro card (no italic — changed in April 10)
- Sections: Info Collected, Email Use, Affiliate Links, Rover Bookings, Unsubscribing, External Links, Contact
- Rover links go directly to the Rover profile

---

## 8. Email Templates *(rebranded blue/yellow in April 10 session)*

All 4 email files now match the site:

- `welcome-email.html` — fully rewritten
- `mini-update-01.html` — fully rewritten
- `monthly-issue-01.html` — fully rewritten, now includes a yellow Rover CTA button
- `newsletter-template.html` — color tokens + fonts swapped in-place to preserve optional section blocks

Shared email styling:
- Background: `#F2F5FB`
- Card: `#FFFFFF` with `border-radius: 10px` + subtle blue shadow
- Header: navy gradient (`#0A1E3D → #1B4F8C → #2B6CB0`) with `#F5CC4A` eyebrow
- Body font: **Arial / Helvetica** (email-client safe)
- Wordmark font: Georgia 600 (`"Dogs & Llamas"`)
- Accent callouts: `#E4F0FB` background with `#D4A017` left border
- Link color: `#2B6CB0`
- Footer: `#081529` with muted white text
- All sign-offs: "Lorenzo & Catalina Llamas" + "Rover Star Sitters • rover.com/sit/lorenl45629"
- Monthly issue copy rewritten in plural voice (we/our)

`newsletter-template.html` still includes the OPTIONAL sections (Photo Strip, Testimonial, Product Spotlight, Personalized Dog Pick) commented out — uncomment and fill in the config block at the top of the file.

---

## 9. Subscriber, Login & Personalization (`dal-subscriber.js` v2.0)

### Overview

A Supabase-backed subscriber system with:
1. **Subscribe** — derives username from email prefix, saves to Supabase + localStorage
2. **Login / Unlock** — auto-injected login strip below every nav lets returning visitors re-enter their email or username to unlock personalized view
3. **Content personalization** — elements with `data-dal-slot="key"` are text-swapped with dog-specific content from the built-in `DOG_CONTENT` object
4. **Dev helper** — `DAL.devLoginAs('turbo')` in console for local testing without hitting Supabase

### Supabase setup (one-time)

1. Dashboard: https://supabase.com/dashboard/project/nizvndjuzyblsewobkru
2. Settings → API → copy **Project URL** and **anon public** key
3. Paste the anon key into `CONFIG.supabaseAnonKey` in `dal-subscriber.js`
4. SQL Editor → New Query → paste contents of `supabase-schema.sql` → Run
5. Two seeded rows exist immediately: Turbo (`lorenzoleollamas@gmail.com`) and Troy (`ltl924@gmail.com`)

### Database schema

One table `public.subscribers`:

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | primary key |
| `email` | text | unique, lowercased |
| `username` | text | unique, derived from email prefix |
| `dog_name` | text | optional; "Turbo", "Troy", etc. |
| `dog_breed` | text | optional |
| `dog_size` | text | optional |
| `dog_traits` | text[] | optional array |
| `dog_emoji` | text | optional |
| `created_at` | timestamptz | auto |

Two Postgres RPC functions exposed to anon:
- `dal_subscribe(p_email text)` — inserts or returns existing row
- `dal_lookup(p_key text)` — finds a row by email OR username

RLS is enabled with **zero policies on the table itself**, so the anon key can only call the two RPCs. No direct SELECT on the subscribers list is possible from the client.

### Built-in dog profiles

In `dal-subscriber.js`:

```javascript
var DOG_CONTENT = {
  turbo: {
    name: 'Turbo',
    'hero-title': "Turbo's Corner",
    'issue-title': "April 2026 — Agility & Food Puzzles",
    'tip-1': "Turbo is food-motivated — use freeze-dried liver...",
    'pick-name': "Chuckit! Sport 26L Launcher",
    /* ...more slots */
  },
  troy: { /* husky-specific content */ }
};
```

To add a new dog:
1. Add an entry to `DOG_CONTENT`
2. Run `insert into public.subscribers ...` in Supabase SQL Editor with matching `dog_name`
3. The site picks it up automatically next page load

### Client API

```javascript
DAL.handleSubscribe(email)      // Promise → creates/returns subscriber
DAL.loginWithKey(emailOrUser)   // Promise → finds existing subscriber
DAL.getSubscriber()             // sync → returns cached subscriber or null
DAL.clearSubscriber()           // sync → logout (clears localStorage + restores content)
DAL.devLoginAs('turbo'|'troy')  // sync → local test helper (no Supabase needed)
DAL.initPersonalizeButton()     // sync → re-applies nav button state
DAL.onPersonalizeBtnClick()     // toggle personalized view on/off
DAL.personalizeContent()        // sync → swaps [data-dal-slot] elements
```

### Content slot system

Any element with `data-dal-slot="key"` gets its `textContent` replaced when a matched dog profile is active. Original content is preserved in `data-dal-original` and restored on logout/toggle-off.

Currently wired slots:
- **index.html**: `issue-title`, `issue-body-1/2/3`, `tip-eyebrow`, `tip-title`, `tip-1/2/3`
- **store.html**: `emoji`, `pick-label`, `pick-name`, `pick-reason` (in personalized pick card)

### CSS visibility hooks (auto-injected by the script)

```css
.dal-personal-only { display: none; }
body.dal-personalized .dal-personal-only { display: block; }

.dal-dog-only { display: none; }
body.dal-personalized.dal-has-dog .dal-dog-only { display: block; }
```

- `.dal-personal-only` — shows for **any** logged-in subscriber (e.g., the store welcome bar)
- `.dal-dog-only` — shows **only** when the subscriber has a matched dog profile (e.g., Turbo's tips section, personalized pick card)

### Login strip (auto-injected below nav on every page)

The script auto-injects a blue strip between `<nav>` and the rest of the page:

```
🐾 Already subscribed?  [ your username or email ]  [ Unlock ]  ×
```

- On submit: calls `DAL.loginWithKey(key)` → on success, hides the strip, shows the personalize button, populates content slots
- Dismissible per-session via the × button
- Hides automatically when the user is already logged in

### Email sending (Mailchimp is no longer free)

Recommended free alternatives for actually sending newsletters:

| Service | Free tier | Best for |
|---|---|---|
| **Brevo** (Sendinblue) | 300 emails/day, **unlimited contacts** | Best overall — has API + embedded forms + transactional |
| **MailerLite** | 1,000 subs, 12,000 emails/mo | Prettiest drag-drop editor |
| **Beehiiv** | 2,500 subs free | Creator-focused, great analytics |
| **EmailOctopus** | 2,500 subs, 10k emails/mo | Cheapest paid upgrade |
| **Buttondown** | 100 subs free | Developer-friendly, Markdown-based |

Recommended: **Brevo**. Export subscribers CSV from Supabase → import into Brevo → send using your blue/yellow email templates.

---

## 10. Coupons

Honor-based. The username-derived code is automatically generated; `SHOP10` is static.

| Code | Trigger | Discount |
|---|---|---|
| `[USERNAME]` | Subscribes to newsletter (auto-generated from email) | Personal code — apply on Rover at booking |
| `SHOP10` | Purchases via store affiliate link | 10% off next sit (new + returning) |

---

## 11. Amazon Affiliate Links

All product links use direct Amazon URLs with real ASINs. Replace with personal `amzn.to/XXXXX` short links once affiliate program is approved.

**ASINs on file:** Big Barker `B009G9Y5UC`, MidWest iCrate `B000OX64P8`, KONG `B0002AR0I8`, Benebone `B00CPDWT2M`, Chuckit Ultra `B00UNLOWK0`, Chuckit Sport 26L `B001B4TV1I`, West Paw Zisc `B004A7X29U`, Blue Buffalo `B0009YWKUA`, Purina Pro Plan `B01EY9KQ2Y`, Earth Rated Wipes `B07NHL31CC`, Puomue Towel `B0BY57YF6B`.

---

## 12. Security

### In HTML (works everywhere including GitHub Pages)
- `<meta name="referrer" content="strict-origin-when-cross-origin">`
- `<meta http-equiv="Permissions-Policy" content="camera=(), microphone=(), geolocation=()">`
- All external links: `rel="noopener noreferrer"`
- All Amazon affiliate links: `rel="noopener noreferrer sponsored"`
- Event listeners via `addEventListener` (no inline `onclick`)
- Schedule admin PIN is **hashed in localStorage** (simple polynomial hash — soft lock, not cryptographic)

### `_headers` file (Netlify / Cloudflare only)
- X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, CSP
- Cache: HTML = 1hr, `/media/*` = 30 days immutable
- GitHub Pages ignores this file

---

## 13. Placeholders Still to Fill

| Placeholder | Where | Replace With |
|---|---|---|
| `[X]` stat numbers | `about.html` stat bar | Actual Rover stats (Happy Dogs, 5-Star Reviews, Stays Completed) |
| Default PIN `1234` | `schedule.html` line ~441 | Personal 4-digit admin PIN |
| Solo / couple portrait | `about.html` hero | Replace `Dakota and me.JPG` with a photo of the two of you |
| Harley photo | `store.html` personal pick + gallery | Add `./media/Harley.jpg` |
| Testimonial copy | `index.html` | 3 real client quotes (with written permission) |
| `[YOUR-GITHUB-USERNAME]` / `[REPO-NAME]` | OG meta tags | Actual deployment URL |
| `[YOUR-SITE]` | Share links in store.html | Live site URL |
| `https://amzn.to/XXXXX` | All 15 product cards | Personal amzn.to affiliate links |

---

## 14. Pending Work

### Immediate (before launch)
- [ ] Fill in real Rover stats on `about.html`
- [ ] Change schedule admin PIN from `1234`
- [ ] Replace testimonial placeholders with real client quotes
- [ ] Convert `Ace.DNG`, `Mango Outside.DNG`, `Teddy.DNG` to JPG
- [ ] **Run `supabase-schema.sql`** in Supabase SQL Editor
- [ ] **Paste Supabase anon key** into `dal-subscriber.js` → `CONFIG.supabaseAnonKey`
- [ ] Sign up for **Brevo** (or alternative) and import any existing subscribers
- [ ] Replace Amazon URLs with personal amzn.to links
- [ ] Add couple portrait for about page
- [ ] Confirm Catalina's credential status and adjust badges if needed

### Short-term
- [ ] Send welcome email to existing client list
- [ ] Publish `monthly-issue-01.html` to subscribers
- [ ] Add more dogs to "Our Recent Dogs" as photos come in
- [ ] Add optional `dogName` field to subscribe forms to enable better personalization

### Medium-term
- [ ] `monthly-issue-02.html` for May using the template
- [ ] **Supabase v2**: create `subscribers` table for cross-device sync (see §9)
- [ ] Add breed filter or "best for your breed" section to store
- [ ] Testimonial carousel for about page when real reviews come in
- [ ] Build dog profile mapping (username → dog breed/size/picks) for richer personalization on store page

### Long-term
- [ ] Swap "In Progress" badge for full credential card when certification is earned
- [ ] JSON-synced schedule via GitHub Actions if multi-device sync becomes needed
- [ ] Subscriber analytics dashboard (Mailchimp + optional Supabase)

---

## 15. Deployment

### GitHub Pages
1. Push repo to GitHub
2. Settings → Pages → Source: `main` / root
3. Site live at `https://<username>.github.io/<repo-name>/`
4. Replace OG meta placeholders with real URL

### Netlify / Cloudflare Pages
1. Connect repo
2. Build command: *(none)*
3. Publish directory: `/` (root)
4. `_headers` activates automatically

### Email platform (not yet connected)
Subscribe forms currently `preventDefault` + toast. Replace `action="#"` with Mailchimp/beehiiv embed. Recommended: **beehiiv** (free tier, simple analytics).

---

## 16. Changes in this April 10 session

### Content / copy
1. **Sitter name corrected**: Loren → Lorenzo
2. **Added Catalina** as co-sitter. Site now reads "Lorenzo & Catalina Llamas" / "Rover Star Sitters" (plural) everywhere — about, index, store, gallery, privacy, schedule, all emails
3. About bio rewritten in plural voice (we/our/us)
4. New value card: **"Two Sets of Hands"** (husband-and-wife team angle), replaces "Rover-Covered"
5. **Removed trust paragraph** from about.html entirely
6. **Removed "$25K vet coverage"** lines from about Rover CTA card and schedule book section
7. Schedule page Rover booking CTA text pruned (no insurance boilerplate)

### Design / UX
8. **Star Sitter + Dog Training Cert badges** added to about hero with stagger-in animation
9. **Font readability fix** — italic Playfair Display replaced with roman 600 weight (headings) or DM Sans (body) across all pages. Italic retained only for the small decorative `nav-brand` / `footer-brand` wordmark and stylized `&` ampersand.
10. **Schedule page restructure**:
    - Calendar is now **first** (directly after hero)
    - Service tiles replaced with a **`<select>` dropdown** below the calendar
    - Selecting a service reveals a detail pane with rate, description, and "⭐ Our Favorite" badge for Boarding and Doggy Day Care
    - Rates populated: Boarding $90/night, Doggy Day Care $50/day, Drop-In $45/visit, Walking $25/walk, House Sitting $100/night
11. **store.html blue/yellow verification**: added proper `--blue`/`--yellow` CSS variable aliases; fixed two hardcoded green leftovers (`.badge-value`, `.product-why` text color)

### Email rebrand
12. All 4 email templates rebranded from green/cream Georgia to **blue/yellow Arial-Helvetica**
13. Header: navy gradient with yellow eyebrow
14. Monthly issue #1 got a new **yellow Rover CTA button** table-row
15. All email sign-offs updated to "Lorenzo & Catalina Llamas" + "Rover Star Sitters • rover.com/sit/lorenl45629"

### Micro-interactions (new in late-session addition)
16. **Shared animation system** added to every page (5 keyframes: fade-up, pop, pulse, wiggle, paw-walk)
17. **Page fade-in** on load for all main content
18. **Nav brand wiggle** on hover
19. **Nav link underline slide** (yellow, scaleX origin center)
20. **Welcome pulse ring** (2 iterations on load) on primary CTAs — book, Rover, Amazon
21. **Calendar day click bounce** — visible feedback for every click on any future date (view-only or admin)
22. **Calendar months stagger-in** on page load
23. **Filter button pop** on click (store + gallery)
24. **About badge stagger-in** on load (150/300/450ms delays)
25. **Dog cards / perk icons / value icons** do a gentle paw-walk on hover
26. **Dog chips / coupon codes / hero photo** wiggle on hover
27. **Service detail pane** slides in when a schedule service is selected
28. **Admin FAB spins** 60° on hover
29. **Lightbox** scales in with bouncy cubic-bezier
30. All animations wrapped in `prefers-reduced-motion` guards

### What did NOT change
- 6 public pages, shared nav structure
- Blue/yellow palette values (just renamed the variables in store.html)
- Responsive breakpoints (960 / 820 / 480)
- Schedule admin PIN system (localStorage + polynomial hash)
- Store filter + pagination JS
- Gallery masonry layout + lightbox
- Amazon ASINs
- Deployment assumptions (GitHub Pages / Netlify / Cloudflare)

---

---

## 17. Changes — Late April 10 session (subscriber system + store redesign)

### store.html — Personal Picks redesign
31. **Picks section shrunk and repositioned**: replaced full-width 2-up card grid with compact side panel
    - Wide (≥960px): CSS grid two-column layout — products left (1fr), picks sidebar right (256px, sticky)
    - Narrow (<960px): picks become a collapsible one-liner with `aria-expanded` toggle button
    - Each pick is now a `.pick-item`: 50×50px thumbnail + dog label + product name + 2-line reason + link
    - Photo thumbnail: `object-fit: cover; object-position: center` — always centered
    - Old `.pick-card`, `.picks-grid`, `.pick-photo-placeholder` etc. fully removed

32. **Product card hover effect improved**: removed `transform: translateY(-3px)` tilt; hover now only deepens the box shadow (`0 8px 32px rgba(27,79,140,.2)`) — no movement, card stays stable

### New file: `dal-subscriber.js`
33. **Subscriber system** — shared across all 6 pages
    - `DAL.handleSubscribe(email)`: saves to localStorage, derives username from email prefix, posts to Mailchimp (if configured)
    - `DAL.getSubscriber()`: returns stored `{ email, username, discountCode, dogName, subscribedAt }` or null
    - `DAL.initPersonalizeButton()`: auto-runs on page load; reveals nav `🐾 [username]` button if subscribed
    - `DAL.onPersonalizeBtnClick()`: toggles `body.dal-personalized`, shows/hides `.dal-personal-only` elements

### Nav — Personalize button (all 6 pages)
34. **`🐾 [username]` button** added next to nav-brand on every page
    - Hidden (`display:none`) by default — only shown after subscribing
    - On click, toggles personalized view; button gets `.dal-active` class (golden fill)
    - ARIA live region `#dal-live-region` announces state change for screen readers

### store.html — Personalized welcome bar
35. **`.dal-welcome-bar`** strip between nav and affiliate-bar
    - `display:none` by default; shown when `body.dal-personalized` is active (via `.dal-personal-only`)
    - Populated by JS: "Hi, [username]! Showing [dog's picks]." + `[DISCOUNTCODE]` chip in yellow

### Subscribe form wiring (index.html + store.html)
36. Both subscribe forms now call `DAL.handleSubscribe(email)` and show a toast: *"🐾 Welcome, [username]! Your discount code: [CODE]"*

*All 6 pages updated. `dal-subscriber.js` created. Handoff doc renumbered (sections 9–17).*

---

## 18. Changes — late April 10 session 2 (Supabase + login + content personalization)

### Email service switch
37. **Mailchimp → Supabase + Brevo.** Mailchimp no longer offers a free tier. `dal-subscriber.js` was rebuilt around Supabase for data, with Brevo (or MailerLite / Beehiiv) recommended for actually sending newsletters. Mailchimp iframe code removed.

### Supabase integration
38. **`supabase-schema.sql` created** — single SQL file you paste into Supabase → SQL Editor → Run. Creates:
    - `public.subscribers` table (email, username, dog profile columns)
    - `dal_subscribe(email)` RPC function — public insert-or-return
    - `dal_lookup(key)` RPC function — public lookup by email or username
    - Row-level security: RLS enabled, no policies → anon has zero direct table access
    - Seeded rows: Turbo (`lorenzoleollamas@gmail.com`) and Troy (`ltl924@gmail.com`)
39. **`dal-subscriber.js` v2.0** — full rewrite:
    - Added `rpc()` helper (fetch-based, no SDK bloat)
    - `handleSubscribe()` now calls Supabase `dal_subscribe` RPC, falls back to localStorage-only if unavailable
    - New `DAL.loginWithKey(email|username)` → calls `dal_lookup` RPC
    - `normalizeRow()` maps snake_case Supabase rows to camelCase JS objects
    - Supabase project URL pre-filled; user only needs to paste the anon key

### Login / Unlock strip (all 6 pages, auto-injected)
40. A pale blue strip appears below every page's nav when NOT logged in:
    > 🐾 Already subscribed?  [your username or email]  [Unlock]  ×
41. Fully auto-injected by `dal-subscriber.js` — no HTML changes needed on individual pages
42. On submit → calls `DAL.loginWithKey()` → Supabase RPC → if matched, hides strip, shows personalize button, swaps content slots
43. Dismissible per-session via ×; CSS also auto-injected as a `<style>` tag into `<head>`

### Content personalization via `[data-dal-slot]`
44. New text-swap system: any element with `data-dal-slot="key"` gets replaced with the matching value from `DAL.DOG_CONTENT[dogName]`
45. Original content preserved in `data-dal-original` attribute → restored on logout/toggle-off
46. Two built-in dog profiles shipped:
    - **Turbo** (mini Australian Shepherd): food, agility, outdoors, barking
    - **Troy** (husky): endurance, blow-coat, cold-weather, double-coat
47. Each profile defines ~12 slot values: hero-title, issue-title, 3× issue-body, tip-eyebrow, tip-title, 3× tip, pick-label, pick-name, pick-reason, emoji

### index.html — personalized content slots
48. **Latest Issue card** — title + 3 body paragraphs now carry `data-dal-slot` attributes; swap to dog-specific content when logged in
49. **New "Personal Tips" section** added between Latest Issue and Recent Dogs grid
    - Class `.dal-dog-only` — completely hidden unless the subscriber has a matched dog profile
    - Dark navy gradient card with 3 numbered tip boxes
    - Each tip box has a `data-dal-slot="tip-1/2/3"` paragraph

### store.html — personalized pick card
50. New `.pick-item.pick-item-personal.dal-dog-only` card at the top of the picks sidebar
    - Gold-accented (yellow left border + gradient background) to distinguish from generic picks
    - Content slots: emoji, pick-label, pick-name, pick-reason
    - Only visible when a matched dog profile is active

### Dev helper
51. `DAL.devLoginAs('turbo' | 'troy')` — run in browser console to activate a dog profile locally for testing, even before Supabase is configured. Useful for previewing what subscribers will see.

### CSS scope helpers (injected with login strip styles)
52. `.dal-personal-only` → shown for any logged-in subscriber
53. `.dal-dog-only` → shown only when `body.dal-has-dog` (matched profile)
54. `body[data-dal-dog="turbo"]` and `body[data-dal-dog="troy"]` attributes set for future CSS-only dog-specific styling

### What still needs a human
55. Paste Supabase anon key into `CONFIG.supabaseAnonKey`
56. Run `supabase-schema.sql` in the Supabase SQL Editor
57. Sign up for Brevo / MailerLite / Beehiiv and import subscribers for actual email sending

*Next: test the login flow with Turbo / Troy, add more dog profiles as clients come in, and wire the monthly issue page with slot attributes too.*

---

## 19. Changes — late April 10 session 3 (login strip UX + subscribe-to-bottom)

### Login strip — always visible, state-aware
58. **Removed the × dismiss button.** The login strip now stays visible on every page, every state — by design, so visitors always have a clear way to toggle between personalized and generic views (especially useful for testing).
59. **New placeholder copy**: "Enter your code for a personalized version" (was "Already subscribed?")
60. **Input placeholder**: "your code, email, or username" (was "your username or email")
61. **State-aware inner layout** via two wrapper divs `.dal-state-out` / `.dal-state-in` — CSS swaps between them based on `body.dal-personalized`:
    - Logged out: `[🐾]  Enter your code for a personalized version: [input] [Unlock] [View generic info]`
    - Logged in:  `[🐾]  Personalized for [username] — 🐕 [Dog name]  [View generic info]`
62. **New "View generic info" reset button** — always visible, TEMPORARY testing button (remove when ready to ship). Calls `DAL.clearSubscriber()` which removes the localStorage entry, restores all `[data-dal-slot]` originals, re-runs `initPersonalizeButton()`. When pressed with no active subscriber, shows a friendly "Already viewing the generic version" message.
63. **Updated `initPersonalizeButton`**: no longer hides the strip when logged in — only toggles the body class. Populates `.dal-login-username-txt` and `.dal-login-dog-txt` inside the strip when logged in so the user sees their status.

### index.html — Subscribe section moved to bottom
64. **Subscribe form removed from hero.** The hero now shows: eyebrow → title → byline → sub-copy → two CTAs (`Read this month →` linking to `#latest`, `Subscribe free` linking to `#subscribe` at the bottom).
65. **New `.subscribe-bottom` section** added just before `</main>` with:
    - Navy gradient background (matches site hero style)
    - "Join the Newsletter" eyebrow + "Get Dogs & Llamas, free" headline
    - Email input + Subscribe Free button (same form id + name so the existing JS handler still works)
    - Privacy policy link
    - Full responsive stacking on ≤640px
66. **Hero `id="subscribe"` moved to the bottom section.** The nav "Subscribe" CTA and any `#subscribe` anchor now scrolls to the new bottom section. The hero got `id="top"` as a cleanup.
67. **New `id="latest"`** added to the "Latest Issue" heading so the hero's first CTA scrolls there.
68. **New `.btn-secondary` + `.hero-cta-row` CSS** added to index.html style block.
69. Orphaned `.hero-form` / `.hero-note` CSS left in place as dead code (harmless; no elements reference it).

### Dog profile display in the strip
70. When logged in with a matched dog, the strip now shows: `Personalized for janedoe — 🐕 Turbo` — a concise always-visible confirmation that replaces the old in-nav badge pattern (the nav badge is still present as a fallback but visually redundant now).

*All behavior tested end-to-end in a Node stub: `devLoginAs('troy')` + `clearSubscriber()` cycle works cleanly. CSS is injected as a single `<style>` tag so no per-page edits needed.*
