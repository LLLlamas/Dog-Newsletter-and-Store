# Dogs & Llamas — Project Handoff
**Date:** April 10, 2026
**Prepared for:** Codex / next AI session
**Project:** Dogs & Llamas — Lorenzo Llamas's dog-sitting newsletter, booking/availability hub, photo gallery, about page, and curated product store.

---

## 1. What This Project Is

A static multi-page website + email newsletter system for **Lorenzo Llamas**, a **Rover Star Sitter** currently earning his dog training certification. Brand: **"Dogs & Llamas."** Rover profile: <https://www.rover.com/sit/lorenl45629>.

The site has **six public pages** plus email templates:

| Page | Purpose |
|---|---|
| `index.html` | Newsletter hub, hero + subscribe, dog grid, testimonials, store teaser, coupons |
| `schedule.html` | 3-month availability calendar (clients view; sitter edits via PIN-gated admin mode) |
| `gallery.html` | Masonry photo gallery with filter + lightbox, "photography services coming soon" teaser |
| `about.html` | Sitter bio, Rover Star Sitter + dog training certification badges, values, dog chips, Rover CTA |
| `store.html` | Curated Amazon affiliate product picks with filter + pagination |
| `privacy.html` | Privacy policy (same design system, blue/yellow, shared nav) |

**Rover-safe framing**: all bookings are directed to Rover.com. The schedule page is **view-only for clients** and links to Rover for booking requests.

**Audience:** Past and prospective Rover clients. Dog/animal people — warm, friendly, community-minded.
**Tech stack:** 100% static HTML + CSS + vanilla JS. No framework, no build step. Deployable to GitHub Pages, Netlify, Cloudflare Pages.

---

## 2. File Structure

```
/Dog Newsletter and Store/
├── index.html                    ← Newsletter hub / landing
├── schedule.html                 ← Availability calendar (NEW — admin editable via PIN)
├── gallery.html                  ← Photo gallery (NEW — masonry + lightbox + filter)
├── about.html                    ← About Lorenzo (NEW — Star Sitter, training cert)
├── store.html                    ← Curated Amazon picks
├── privacy.html                  ← Privacy policy
├── newsletter-template.html      ← Monthly email template (copy to monthly-issue-XX.html)
├── welcome-email.html            ← One-time welcome email for new subscribers
├── monthly-issue-01.html         ← April 2026 issue (first one)
├── mini-update-01.html           ← Short-form mid-month template
├── _headers                      ← Netlify/Cloudflare security headers
├── dogsitter_newsletter_project_brief.md
├── chatgpt takeover 4-9-2026.md  ← Previous handoff
├── chatgpt takeover 4-10-2026.md ← THIS FILE
└── media/
    ├── Turbo Outside.jpg         ← Merle Aussie outdoors (hero main, store pick 2)
    ├── Turbo sleeping.JPG        ← Turbo napping (gallery)
    ├── Troy.jpg                  ← Husky with blue eyes (hero secondary, dogs grid)
    ├── Dakota and me.JPG         ← Sitter selfie with Sheltie (about hero, gallery)
    ├── Ace.DNG                   ← RAW — convert via cloudconvert.com
    ├── Mango Outside.DNG         ← RAW — convert
    └── Teddy.DNG                 ← RAW — convert
```

---

## 3. Design System (Blue & Yellow — Dog Vision Palette)

Inspired by research that dogs primarily see in shades of blue, yellow, and gray.

### Fonts (Google Fonts CDN)
- **Headings/display:** `Playfair Display` — italic serif, warm editorial feel
- **Body/UI:** `DM Sans` — clean, modern, friendly

### Color Tokens (CSS custom properties — identical across all 6 pages)
```css
:root {
  --bg:          #F2F5FB;   /* cool, soft ice blue */
  --bg-2:        #E4EAFA;
  --surface:     #FFFFFF;
  --blue:        #1B4F8C;   /* primary deep navy */
  --blue-mid:    #2B6CB0;
  --blue-light:  #6BA3D6;
  --blue-pale:   #E4F0FB;
  --yellow:      #D4A017;   /* accent — all CTAs */
  --yellow-light:#F5CC4A;   /* nav accent, hero highlights */
  --yellow-pale: #FEF9E7;   /* coupon bar */
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

> Note: The schedule, store, gallery, and about pages use the token names `--blue` / `--yellow`. The original `index.html` + the earlier versions kept legacy `--green` / `--amber` variable names but remapped their values to the blue/yellow palette for zero-touch compatibility. Both styles render identically.

### Hero gradient (shared)
```css
background: linear-gradient(150deg, #0A1E3D 0%, #1B4F8C 55%, #2B6CB0 100%);
```
Plus a radial dot overlay via `::before` (24px spacing).

### Footer (shared)
```css
background: #081529;
```

### UI patterns (shared)
- **Primary CTA buttons**: amber pill (`border-radius: 99px`), white/dark text
- **Section eyebrows**: 11px uppercase DM Sans + amber underline bar via `::after`
- **Cards**: white surface, 1px warm border, `var(--shadow-sm)`, hover lifts 3px
- **Scroll reveal**: IntersectionObserver `.reveal` → `.visible` fade-up (disabled under `prefers-reduced-motion`)

---

## 4. Shared Navigation

All 6 HTML pages use an **identical nav component** with 4 main tabs + Subscribe CTA. The nav is sticky-top, deep navy, with a hamburger that kicks in at `max-width: 820px`.

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

JS (shared):
```javascript
document.getElementById('nav-toggle').addEventListener('click', function () {
  var links = document.getElementById('nav-links');
  var open = links.classList.toggle('open');
  this.setAttribute('aria-expanded', String(open));
});
```

---

## 5. Responsive Breakpoints (applied to all main pages)

Three-tier mobile-first scaling:

| Breakpoint | Range | Behavior |
|---|---|---|
| Desktop (default) | `>= 961px` | Full nav, multi-column grids, large hero |
| Tablet | `<= 960px` | Tighter padding, 2-col grids, moderate hero |
| Mobile | `<= 820px` | Hamburger menu, single/2-col grids, stacked hero |
| Small mobile | `<= 480px` | Single-column, reduced type, stacked forms |

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

`index.html` additionally has a **skip-to-main-content** link for keyboard users.

---

## 6. Page-by-Page Notes

### index.html
- Hero with Lorenzo's name + "Rover Star Sitter" byline
- Polaroid Turbo (main) + Troy (secondary) photos rotating in hero
- Perks strip, What You'll Get pillars, Latest Issue preview, archive links
- **Our Recent Dogs** section (`#our-dogs`): Turbo, Troy, Dakota + Ace/Mango/Harley placeholders. Duplicate Turbo has been removed.
- 3 testimonial placeholder cards
- Store teaser (→ store.html), coupon cards (PUPS10, SHOP10)
- Share/refer row
- Footer links to all 6 pages + privacy

### schedule.html  *(NEW)*
- 3-month forward-looking calendar grid (today + 2 more months), rendered dynamically in JS
- Status colors: `available` = deep blue, `booked` = gray strike, `unavailable` = light gray
- Today highlighted with amber ring
- Services grid: Boarding, Drop-in Visits, Dog Walking, House Sitting (rate placeholders `$[RATE]`)
- **Admin mode**: ⚙ FAB button → PIN modal (default PIN `1234` — CHANGE THIS)
- `localStorage` keys: `dal_schedule` (JSON map `{ "YYYY-MM-DD": "available"|"booked"|"unavailable" }`) and `dal_admin` (auth token)
- Click future date in admin mode → cycles status: available → booked → unavailable → available
- Rover booking CTA → rover.com/sit/lorenl45629
- "Exit admin mode" button when authenticated

### gallery.html  *(NEW)*
- CSS masonry via `columns: 4 240px; column-gap: 14px`
- 4 filter buttons: All, Outdoors, Action, Portraits, Rest & Play
- Each item has `data-tags`, `data-name`, `data-caption`
- Hover caption overlay + click-to-open full-size lightbox (ESC/click-outside closes)
- 4 real photos + 4 "coming soon" placeholders for Ace, Mango, Harley, extra slot
- "Photography services coming soon" banner at bottom
- Tablet: 3 columns; mobile: 2 columns; small: 2 narrow

### about.html  *(NEW)*
- Lorenzo Llamas hero with polaroid photo (currently `Dakota and me.JPG` — replace with solo portrait)
- **Badge row** under title:
  1. ⭐ Rover Star Sitter (linear gradient highlighted)
  2. 🎓 Dog Training Cert (In Progress)
  3. 🛡️ Background Checked
- Stat bar: Happy Dogs `[X]`, Rover Star Sitter, 5-Star Reviews `[X]`, Stays Completed `[X]+`
- Bio: "Why I do this" + Rover Star Sitter paragraph + training certification paragraph
- **Certification callout card** with gold accent — reiterates the in-progress credential
- 6 value cards including new "Training-Informed" card replacing "Pet First Aid Aware"
- Dog chip list: Turbo, Troy, Dakota, Harley, Ace, Mango
- Rover profile CTA card (navy bg, yellow button)

### store.html
- Affiliate disclosure bar + coupon bar (`SHOP10`)
- Sticky filter bar at `top: var(--nav-h)` with 10 filter tags
- **Personal Picks** (2-up): Harley (Big Barker) + Turbo (Chuckit 26L)
- All Picks product grid with JS pagination (6 per page on "All", show-all for filters)
- 15 products, each with ASIN comment in HTML + `rel="sponsored noopener noreferrer"`
- Subscribe banner + share row at bottom
- Product grid auto-fits: desktop 272px min / tablet 240px / mobile 200px / narrow mobile 1-col

### privacy.html  *(REBUILT in session)*
- Now matches blue/yellow design system + shared nav
- Intro card with italic Playfair quote
- Sections: Info Collected, Email Use, Affiliate Links, Rover Bookings, Unsubscribing, External Links, Contact
- Links Rover TOS + Rover privacy policy
- Contact line: "Reach out on my Rover profile" → rover.com/sit/lorenl45629

---

## 7. Email Templates

**These are still in the original green/warm serif style** — they haven't been rebranded to blue/yellow. Monthly/welcome emails render fine in inboxes as-is, but if the user wants a fully unified brand, these three files need updating:
- `newsletter-template.html`
- `welcome-email.html`
- `monthly-issue-01.html`
- `mini-update-01.html`

All files now sign off as **"Lorenzo Llamas"** (all `[First Name] Llamas` references have been updated). The recipient greeting `Hi [First Name],` is still a placeholder since it's filled in per-recipient by the email platform.

`newsletter-template.html` includes an OPTIONAL PERSONALIZED DOG PICK section (commented out by default) for "Just for [Dog Name]" style product recs tied to specific clients.

---

## 8. Coupon System

Honor-based, no backend.

| Code | Trigger | Discount |
|---|---|---|
| `PUPS10` | Subscribes to newsletter | 10% off next sit (returning clients) |
| `SHOP10` | Purchases via store affiliate link | 10% off next sit (new + returning) |

Both mentioned verbally when the client reaches out on Rover.

---

## 9. Security

### In HTML (works everywhere including GitHub Pages)
- `<meta name="referrer" content="strict-origin-when-cross-origin">`
- `<meta http-equiv="Permissions-Policy" content="camera=(), microphone=(), geolocation=()">`
- All external links: `rel="noopener noreferrer"`
- All Amazon affiliate links: `rel="noopener noreferrer sponsored"`
- Event listeners via `addEventListener` (no inline `onclick`)
- Subscribe form uses `preventDefault` with toast feedback
- Schedule admin PIN is **hashed** in localStorage (simple polynomial hash, not cryptographic — this is a soft lock, not a real security boundary)

### `_headers` file (Netlify / Cloudflare only)
- X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, CSP
- Cache: HTML = 1hr, `/media/*` = 30 days immutable
- GitHub Pages ignores this file; HTML meta tags cover what they can

---

## 10. Amazon Affiliate Links

All current product links use direct Amazon URLs with real ASINs. The sitter will replace them with personal `amzn.to/XXXXX` short links once their affiliate program is approved.

Every product card has an HTML comment with the ASIN:
```html
<!-- AFFILIATE LINK: replace href with your amzn.to link | ASIN: B009G9Y5UC -->
```

**ASINs on file:**
- Big Barker 7″ Bed: `B009G9Y5UC`
- MidWest iCrate 42″: `B000OX64P8`
- KONG Classic: `B0002AR0I8`
- Benebone Wishbone: `B00CPDWT2M`
- Chuckit Ultra Ball: `B00UNLOWK0`
- Chuckit Sport 26L: `B001B4TV1I`
- West Paw Zisc 8.5″: `B004A7X29U`
- Blue Buffalo Life Protection 30lb: `B0009YWKUA`
- Purina Pro Plan Sensitive 30lb: `B01EY9KQ2Y`
- Earth Rated Wipes 100ct: `B07NHL31CC`
- Puomue Towel 2-Pack: `B0BY57YF6B`

---

## 11. Placeholders Still to Fill Before Launch

| Placeholder | Where | Replace With |
|---|---|---|
| `[X]` stat numbers | `about.html` stat bar | Actual Rover stats from Lorenzo's profile |
| `[X]+` stays completed | `about.html` | Actual count |
| `$[RATE]` | `schedule.html` services grid | Actual rates for boarding, drop-in, walking, house sitting |
| Default PIN `1234` | `schedule.html` | Personal admin PIN |
| `[YOUR-GITHUB-USERNAME]` `[REPO-NAME]` | OG meta tags in all pages | Actual deployment URL |
| `[YOUR-SITE]` | Share links | Live site URL |
| `https://amzn.to/XXXXX` | All 15 product cards | Personal amzn.to affiliate links |
| Solo portrait photo | `about.html` hero | Replace `Dakota and me.JPG` with a solo shot |
| Harley photo | `store.html` personal pick + gallery | Add `./media/Harley.jpg` when available |
| Testimonial content | `index.html` | 3 real client quotes (with written permission) |

---

## 12. Known Issues / Pending Work

### Immediate (before launch)
- [ ] Fill in Rover stats on `about.html` (Lorenzo will need to share screenshots of his profile)
- [ ] Pick rates for schedule services grid
- [ ] Change schedule admin PIN from default `1234`
- [ ] Replace testimonial placeholders with real client quotes
- [ ] Convert `Ace.DNG`, `Mango Outside.DNG`, `Teddy.DNG` to JPG (cloudconvert.com → place in `/media`, swap placeholder divs for `<img>`)
- [ ] Connect subscribe form `action="#"` to Mailchimp / beehiiv / Buttondown
- [ ] Replace Amazon product URLs with personal amzn.to affiliate short links

### Short-term
- [ ] Rebrand email templates (newsletter-template, welcome-email, monthly-issue-01, mini-update-01) to blue/yellow to match the website
- [ ] Add a solo portrait photo to `about.html` hero
- [ ] Add more dogs to the "Our Recent Dogs" grid as photos come in
- [ ] Send welcome email to existing client list
- [ ] Publish `monthly-issue-01.html` to subscribers

### Medium-term
- [ ] Add a breed filter or "best for your breed" section to the store
- [ ] Consider a small testimonial carousel for the about page once real reviews come in
- [ ] Create `monthly-issue-02.html` for May using the template
- [ ] UTM-tag Amazon affiliate links for click-through tracking

### Long-term
- [ ] Once dog training certification is earned, swap "In Progress" badge for a full credential card
- [ ] Consider upgrading to a build step (Astro, 11ty, or Vite) if the site grows beyond 10+ pages
- [ ] Add a simple JSON-driven schedule sync via a GitHub-based workflow if client demand grows (currently localStorage-only per-device)

---

## 13. Deployment

### GitHub Pages
1. Push repo to GitHub
2. Settings → Pages → Source: `main` branch, `/ (root)`
3. Site live at `https://<username>.github.io/<repo-name>/`
4. Replace OG meta placeholders with the real URL

### Netlify / Cloudflare Pages
1. Connect repo
2. Build command: *(none — static)*
3. Publish directory: `/` (root)
4. `_headers` file activates automatically

### Email platform (not yet connected)
- Subscribe forms in `index.html` and `store.html` currently `preventDefault` + toast
- Replace `action="#"` with Mailchimp / beehiiv embed URL or connect via Formspree/Netlify Forms
- Recommended: **beehiiv** (simple, free tier)

---

## 14. Brand Voice

- **Personal, warm, never corporate.** One person who genuinely loves dogs.
- **Rover-safe.** All bookings stay on Rover — never "book with me directly."
- **Honest.** Products and tips come from real experience.
- **Minimal.** Less text, not more. One tip. One product. One clear CTA.
- **Credentialed but humble.** Star Sitter is a quiet badge of pride, not a sales lever. Training certification is shared with genuine enthusiasm.
- **Dog people talk to dog people.** Reference specific dogs by name. Say why.

---

## 15. Changes from April 9 handoff → April 10

1. Sitter name corrected: **Loren → Lorenzo** (all files)
2. Added **Rover Star Sitter** badge prominently on about page (hero badge row, stat bar, index hero byline, footers, privacy + welcome email sign-off)
3. Added **Dog Training Certification (In Progress)** badge + callout card on about page; new "Training-Informed" value card
4. **privacy.html** fully rebuilt in blue/yellow design system + shared nav
5. **All `[First Name]` placeholders** updated to `Lorenzo` throughout site and email templates (kept `[First Name]` as the recipient placeholder in newsletter-template + mini-update + monthly-issue since it's filled in per-recipient by the email platform)
6. **Three-tier responsive breakpoints** on all main pages: desktop (default), tablet (≤960), mobile (≤820), small mobile (≤480). Nav hamburger now consistently triggers at 820px across all pages.
7. **Accessibility enhancements**: global `:focus-visible` rings, `prefers-reduced-motion` support, skip-to-main-content link on index
8. **Store.html** product grid now reflows from 4→3→2→1 columns across breakpoints (was 640px-only before)
9. **Index.html** hero now properly stacks on mobile with form wrap, perks strip stacks vertically, pillars collapse 4→2→1, testimonials 3→2→1, dogs grid adapts

---

*Handoff prepared by Claude Code — session date April 10, 2026.*
*All 6 pages are functional and consistent. Remaining work is content (real stats, rates, testimonials, photos, affiliate links) and email platform integration.*
