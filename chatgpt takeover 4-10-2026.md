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
├── dal-subscriber.js             ← Shared subscriber/personalization system (NEW)
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

## 9. Subscriber & Personalization System (`dal-subscriber.js`)

### Overview

A zero-backend localStorage-based subscriber system shipping in **v1 (April 2026)**. Supabase can replace localStorage in v2 for cross-device sync.

### How it works

1. User enters email in any subscribe form → calls `DAL.handleSubscribe(email)`
2. **Username** = email prefix before `@`, stripped to `[a-z0-9]` and lowercased
   - `jane.doe@gmail.com` → `janedoe`
3. **Discount code** = username uppercased (e.g., `JANEDOE`) — Lorenzo & Catalina apply it manually on Rover
4. Data stored in `localStorage['dal_subscriber']` as JSON: `{ email, username, discountCode, dogName, subscribedAt }`
5. On every page load, `DAL.initPersonalizeButton()` reads localStorage and shows/hides the `🐾 [username]` nav button
6. Clicking the nav button toggles `.dal-personalized` on `<body>` and `.dal-active` on the button
7. Elements with class `.dal-personal-only` are shown/hidden by the toggle
8. `store.html` has a `.dal-welcome-bar` that populates with username + discount code when personalized

### Mailchimp setup

In `dal-subscriber.js`, set:
```javascript
var CONFIG = {
  mailchimpUrl: 'https://yoursite.us1.list-manage.com/subscribe/post?u=XXXX&id=XXXX'
};
```
Get this URL from Mailchimp → Audience → Signup forms → Embedded forms → copy the `form action` URL.

### Upgrading to Supabase (v2)

1. Create a `subscribers` table: `{ id, email, username, dog_name, subscribed_at }`
2. Add Supabase JS SDK: `<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>`
3. Replace `safeSet/safeGet` calls in `dal-subscriber.js` with `supabase.from('subscribers').insert/select`
4. For personalized picks: add a `dog_profiles` table mapped to `username` and query picks accordingly

### CSS hooks

```css
/* Always available for personalization: */
body.dal-personalized .dal-personal-only { display: block; }
button.dal-personalize-btn.dal-active { background: rgba(212,160,23,.38); color: #fff; }
```

---

## 10. Coupons

Honor-based. The username-derived code is automatically generated; `SHOP10` is static.

| Code | Trigger | Discount |
|---|---|---|
| `[username]` | Subscribes to newsletter (auto-generated from email) | Personal code — apply on Rover at booking |
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
- [ ] **Connect Mailchimp**: set `CONFIG.mailchimpUrl` in `dal-subscriber.js` (see §9)
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
*Next: connect Mailchimp URL in dal-subscriber.js, then optionally add Supabase for cross-device sync.*
