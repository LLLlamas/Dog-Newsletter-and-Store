# Dogs & Llamas — Project Handoff
**Date:** April 9, 2026  
**Prepared for:** Codex / next AI session  
**Project:** Dogs & Llamas — Personal Dog-Sitting Newsletter + Curated Product Store

---

## 1. What This Project Is

A static website + email newsletter system for a professional dog sitter whose last name is **Llamas**. The brand is **"Dogs & Llamas."**

The site serves two purposes:
1. **Newsletter hub** — reconnect with past Rover clients, share availability openings, monthly dog tips, and subscriber perks. Rover-safe framing (no off-platform booking language — all bookings stay on Rover.com).
2. **Curated product store** — Amazon affiliate links for dog gear, filtered by dog size/activity/need. Personalized picks tied to specific dogs the sitter has cared for.

**Audience:** Past Rover clients and their friends. Dog/animal people — warm, friendly, community-minded.  
**Tech stack:** 100% static HTML/CSS/JS. Deployable to GitHub Pages, Netlify, or Cloudflare Pages. No backend, no framework, no build step.

---

## 2. File Structure

```
/Dog Newsletter and Store/
├── index.html                  ← Main landing page / newsletter hub
├── store.html                  ← Curated Top Picks product store
├── newsletter-template.html    ← Monthly email template (copy → monthly-issue-XX.html)
├── welcome-email.html          ← One-time welcome email for new subscribers
├── monthly-issue-01.html       ← April 2026 issue (sent/published)
├── mini-update-01.html         ← Short-form update template
├── privacy.html                ← Privacy policy page
├── _headers                    ← Netlify/Cloudflare Pages security headers
├── dogsitter_newsletter_project_brief.md  ← Original project brief
├── chatgpt takeover 4-9-2026.md          ← This file
└── media/
    ├── Turbo Outside.jpg       ← Merle Aussie outdoors (MAIN hero photo, used in store pick)
    ├── Turbo sleeping.JPG      ← Turbo napping
    ├── Troy.jpg                ← Husky with blue eyes (hero secondary)
    ├── Dakota and me.JPG       ← Sitter selfie with Sheltie
    ├── Ace.DNG                 ← RAW — needs conversion to JPG (cloudconvert.com)
    ├── Mango Outside.DNG       ← RAW — needs conversion
    └── Teddy.DNG               ← RAW — needs conversion
```

---

## 3. Design System (April 2026 Redesign)

Both `index.html` and `store.html` share a unified design system:

### Fonts (Google Fonts CDN)
- **Headings/display:** `Playfair Display` — italic serif, warm, editorial
- **Body/UI:** `DM Sans` — clean, modern, friendly

### Color Tokens (CSS custom properties)
```css
--bg:          #F9F5EF   /* warm parchment background */
--bg-2:        #F0EAE0   /* slightly darker parchment */
--surface:     #FFFFFF   /* cards */
--green:       #2C5F3F   /* primary — deep forest green */
--green-mid:   #3A7A54   /* medium green */
--green-light: #8DB897   /* soft sage */
--green-pale:  #EAF3ED   /* very light green — tag bg, hover states */
--amber:       #D4872A   /* accent — warm amber/honey — all CTAs */
--amber-light: #F5C878   /* nav accent, hero title & color */
--amber-pale:  #FDF3E0   /* coupon bar bg */
--text:        #1C1C19   /* warm near-black */
--text-2:      #5A5A52   /* body text */
--text-3:      #9A9A90   /* captions, metadata */
--border:      #DDD6C8   /* warm border */
```

### Key UI Patterns
- **Primary CTA buttons:** amber pill (`border-radius: 99px`), white text
- **Section eyebrows:** 11px uppercase DM Sans + amber underline bar via `::after`
- **Cards:** white surface, 1px warm border, `var(--shadow-sm)`, hover lifts 3px
- **Dog cards:** polaroid-style (white bg, photo, Playfair italic name below)
- **Nav:** sticky, forest green, brand in Playfair italic, amber "Subscribe" pill CTA
- **Hero bg:** radial green glow + dot grid overlay on dark gradient
- **Animations:** IntersectionObserver `.reveal` → `.visible` fade-up on scroll

---

## 4. index.html — Key Sections

| Section | ID / Anchor | Notes |
|---|---|---|
| Nav | — | "Our Recent Dogs" + "Curated Picks" + "Subscribe" CTA |
| Hero + Subscribe Form | `#subscribe` | Turbo Outside (main) + Troy (secondary) polaroid cluster |
| Perks Strip | — | 4 perks: first notice, tips, PUPS10 code, store link |
| What You'll Get | — | 4 pillar cards with scroll reveal |
| Latest Issue | — | Issue preview card + archive pill links |
| Our Recent Dogs | `#our-dogs` | Photo grid: Turbo×2, Troy, Dakota, Ace/Mango/Harley placeholders |
| Testimonials | — | 3 cards — replace with real client quotes |
| Store Teaser | — | Green banner → store.html |
| Coupons | — | PUPS10 (newsletter) + SHOP10 (store) dashed-border cards |
| Share / Refer | — | Web Share API + X + Facebook |
| Footer | — | Dark forest, links to store / latest issue / subscribe / privacy |

### Subscribe Form
- Currently preventDefault + toast (no real email platform connected)
- **TODO:** Replace `action="#"` with Mailchimp or beehiiv embed URL when ready
- Form ID: `subscribe-form`, input ID: `email-input`

---

## 5. store.html — Key Sections

### Layout Flow
1. **Nav** (sticky, same as index)
2. **Affiliate disclosure bar**
3. **Hero** (smaller than index — just eyebrow, title, tagline)
4. **Coupon bar** — SHOP10 code
5. **Filter bar** (sticky at `top: 62px` = below nav)
6. **Page wrap:**
   - Sitter note
   - **Personal Picks** (2-up grid — Harley + Turbo — edit monthly)
   - "All Picks" eyebrow
   - **Product grid** (15 cards, flat, no category headers)
   - Pagination (← Prev / Page X of Y / Next →)
   - Share row
   - Subscribe banner

### Filter System
- 10 filter tags: `all`, `small`, `medium`, `large`, `puppy`, `teething`, `chewing`, `fetch`, `sleeping`, `sensitive`
- Each product card has `data-tags="..."` attribute with space-separated tag values
- **"All Picks" view** → paginated, 6 cards per page
- **Filtered view** → shows all matching cards, no pagination
- Empty state with "Show all picks" reset button
- JS is an IIFE (no global scope pollution), vanilla ES5-compatible

### Product Tag Map
| Product | data-tags |
|---|---|
| Big Barker Orthopedic Bed | `large sleeping senior` |
| MidWest iCrate | `small medium large puppy sleeping all` |
| Diggs Snooz Pad | `small medium large puppy sleeping all` |
| KONG Classic | `small medium large puppy teething chewing all` |
| Benebone Wishbone | `medium large teething chewing` |
| West Paw Hurley | `small medium large chewing` |
| Blue Buffalo Life Protection | `medium large adult` |
| Purina Pro Plan Sensitive | `medium large sensitive adult` |
| Wellness CORE Grain-Free | `medium large adult active` |
| Chuckit Ultra Ball | `small medium large fetch` |
| Chuckit Sport 26L Launcher | `large fetch active` |
| West Paw Zisc Disc | `medium large fetch active` |
| Earth Rated Wipes | `small medium large puppy sensitive all` |
| Puomue Microfiber Towel | `small medium large puppy all` |
| Sweet Paws Paw Towel | `small medium large all` |

### Personal Picks Section
- Located just above the product grid, always visible
- Currently shows: **Harley** (Big Barker bed — French Bulldog joint support) + **Turbo** (Chuckit 26L — high-energy Aussie)
- Edit monthly: update dog name, product name, reason text, Amazon link
- Harley has no photo yet (placeholder emoji shown) — add `./media/Harley.jpg` when available
- Turbo uses `./media/Turbo Outside.jpg`
- To hide entirely: add `style="display:none"` to `.picks-section`

---

## 6. Email Templates

### newsletter-template.html
- **How to use:** Copy → `monthly-issue-XX.html`, fill in MONTHLY CONFIG comment block at top
- **Sections:** Greeting, Opening, Availability, Dog Tip, Subscriber Perk (coupon), optional Photo Strip, optional Testimonial, optional Product Spotlight, optional **Personalized Dog Pick**
- **Personalized Dog Pick:** Commented out by default. Uncomment + fill in `DOG_PICK_*` values. Shows a specific product recommendation for a named client's dog (e.g., "Just for Harley — Big Barker Bed").
- **Coupon PUPS10** always shown in the coupon reminder box.
- Checklist embedded as HTML comment at bottom of file.

### welcome-email.html
- One-time send when a new client subscribes
- "What to expect" bullet box
- Replace `[Client Name]` and `[Dog Name]` before sending

### monthly-issue-01.html
- April 2026 — first issue sent
- Topic: spring openings + hot pavement paw care tip

### mini-update-01.html
- Short-form bi-weekly format
- Use for quick availability openings between monthly issues

---

## 7. Coupon System

Honor-based (no backend required). Both codes are mentioned verbally when client reaches out on Rover.

| Code | Trigger | Discount |
|---|---|---|
| `PUPS10` | Subscribes to newsletter | 10% off next sit |
| `SHOP10` | Purchases via store affiliate link | 10% off next sit |

- One use per client, returning clients only for PUPS10, new + returning for SHOP10
- Cannot be combined with other offers

---

## 8. Security

### In HTML (works on GitHub Pages)
- `<meta name="referrer" content="strict-origin-when-cross-origin">`
- `<meta http-equiv="Permissions-Policy" content="camera=(), microphone=(), geolocation=()">`
- All external links: `rel="noopener noreferrer"`
- All Amazon affiliate links: `rel="noopener noreferrer sponsored"`
- Event listeners via `addEventListener` (no inline `onclick`)
- Forms use `preventDefault` with toast feedback

### `_headers` file (Netlify / Cloudflare Pages only)
- X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, Content-Security-Policy
- Cache rules: HTML = 1hr, /media/* = 30 days immutable
- GitHub Pages ignores this file; HTML meta tags serve as fallback

---

## 9. Affiliate Links

All Amazon links currently use direct product URLs with real ASINs where found. The user will replace all of these with their personal `https://amzn.to/XXXXX` short affiliate links.

Every product card has an HTML comment:
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

## 10. Photos in /media

| File | Description | Status | Used In |
|---|---|---|---|
| `Turbo Outside.jpg` | Merle Aussie happy on grass | ✅ Web-ready | Hero (main), Store pick 2, Dogs grid |
| `Turbo sleeping.JPG` | Turbo napping | ✅ Web-ready | Dogs grid |
| `Troy.jpg` | Husky with blue eyes | ✅ Web-ready | Hero (secondary), Dogs grid |
| `Dakota and me.JPG` | Sitter + Sheltie selfie | ✅ Web-ready | Dogs grid |
| `Ace.DNG` | Unknown breed | ❌ RAW — needs conversion | Placeholder in grid |
| `Mango Outside.DNG` | Unknown breed | ❌ RAW — needs conversion | Placeholder in grid |
| `Teddy.DNG` | Unknown breed | ❌ RAW — needs conversion | Not yet in grid |

**To convert DNG files:** Use [cloudconvert.com](https://cloudconvert.com) (free, no install). Convert to JPG, place in `/media`, then replace the placeholder div in the dogs grid with `<img src="./media/Filename.jpg" class="dog-card-photo" loading="lazy">`.

---

## 11. Deployment

### GitHub Pages
1. Push repo to GitHub
2. Settings → Pages → Source: `main` branch, `/ (root)`
3. Site live at `https://[username].github.io/[repo-name]/`
4. Replace `[YOUR-GITHUB-USERNAME]` and `[REPO-NAME]` in OG meta tags in both HTML files

### Netlify / Cloudflare Pages
1. Connect repo
2. Build command: *(none — static site)*
3. Publish directory: `/` (root)
4. `_headers` file activates automatically for security headers

### Email platform (not yet connected)
- Replace `action="#"` in subscribe forms with Mailchimp or beehiiv embed URL
- Recommended: **beehiiv** (simple, free tier, good analytics for small lists)
- Monthly newsletter HTML files can be pasted into any platform's Custom HTML email block

---

## 12. Known Placeholders to Fill In Before Going Live

| Placeholder | Where | What to Replace With |
|---|---|---|
| `[First Name] Llamas` | All files | Sitter's actual first name |
| `[Your City]` | Footer | City/region (optional) |
| `[Rover profile link]` | Email templates, footer | Actual Rover profile URL |
| `[YOUR-GITHUB-USERNAME]` | OG meta tags | GitHub username |
| `[REPO-NAME]` | OG meta tags | Repository name |
| `[YOUR-SITE]` | Share links in store.html | Live site URL |
| `https://amzn.to/XXXXX` | All product cards | Personal affiliate short links |

---

## 13. Pending Work / Future Scope

### Immediate (before launch)
- [ ] Fill in all `[First Name]` and `[Rover profile link]` placeholders
- [ ] Connect subscribe forms to Mailchimp or beehiiv
- [ ] Replace all Amazon product links with personal `amzn.to` affiliate links
- [ ] Convert `Ace.DNG`, `Mango Outside.DNG`, `Teddy.DNG` to JPG and add to dogs grid
- [ ] Replace placeholder testimonials with real client quotes (get written permission)
- [ ] Update GitHub Pages OG meta tags with real URL

### Short-term improvements
- [ ] Add real photos of Harley to trigger the personal pick card in store.html
- [ ] Add more dog entries to the "Our Recent Dogs" grid as photos come in
- [ ] Send `welcome-email.html` to existing client list via Mailchimp/beehiiv
- [ ] Publish `monthly-issue-01.html` to newsletter subscribers
- [ ] Add more filter tags as needed (user mentioned more coming)

### Medium-term
- [ ] Create `monthly-issue-02.html` (May 2026) using `newsletter-template.html`
- [ ] Add real booking link to nav CTA when comfortable taking off-Rover bookings
- [ ] Consider adding a simple "Book a Stay" page (currently stays Rover-only)
- [ ] Add more products to store as affiliate program grows
- [ ] Add a dog breed filter or "best for your breed" section

### Long-term / monetization
- [ ] Connect email platform for real subscriber tracking
- [ ] Consider moving from GitHub Pages to Netlify for `_headers` security support
- [ ] Track affiliate click-through with UTM parameters on Amazon links
- [ ] Consider a simple Tip Jar or Ko-fi link for newsletter supporters
- [ ] Consider a referral tracking link (e.g., `?ref=sarah`) so word-of-mouth is measurable

---

## 14. How Each File Is Meant to Be Used

```
index.html          ← The "home base." Subscribe here. See dogs. Browse issues.
store.html          ← Browse gear. Filter by dog. Click Amazon links.
newsletter-template ← Copy this each month. Fill in config. Send via email platform.
monthly-issue-XX    ← Archived issues. Link from index.html's archive list.
welcome-email       ← Send once to new subscribers. Never reuse.
mini-update-01      ← For quick mid-month availability pings (optional).
privacy.html        ← Linked from all footers. Required for CAN-SPAM compliance.
_headers            ← Auto-used by Netlify/Cloudflare. Ignore on GitHub Pages.
```

---

## 15. Tone & Brand Voice

- **Personal, warm, never corporate.** This is one person who genuinely loves dogs.
- **Rover-safe.** Never say "book with me directly." Always direct to Rover for actual bookings.
- **Honest.** Products are real recommendations from real experience — not filler.
- **Minimal.** Less text, not more. One tip. One product. One clear CTA.
- **Dog people talk to dog people.** Reference specific dogs by name. Say why.

---

*Handoff prepared by Claude Code — session date April 9, 2026.*  
*Pick up from here: both `index.html` and `store.html` are fully redesigned and functional. The next task is filling in real content (names, links, affiliate codes) and connecting the email subscribe form to a real platform.*
