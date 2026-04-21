# Dogs & Llamas Site Audit And Revenue Plan

Date: April 21, 2026

## What I Fixed In Code

- Fixed the homepage booking modal so `Dog Walking` and `House Sitting` submit valid backend service values instead of invalid ones.
- Added a usable mobile nav menu to `index.html`, `about.html`, and `store.html` so visitors are not left with only a lone `Book` button on smaller screens.
- Replaced the dead store product CTA buttons with working outbound Amazon search links so the shop flow is no longer a visual dead end.

## High-Priority Issues Still Open

### 1. Public admin security is too weak

The schedule/admin system is protected by a hardcoded PIN pattern in the public SQL and is callable by `anon`. Even if the PIN changes from `1234`, the underlying pattern is still too weak for a public site.

What this means:

- A motivated person could discover or brute-force the admin flow.
- Booking requests, approvals, cancellations, and payment-marking are more exposed than they should be.
- This is the biggest non-design risk in the repo.

Recommended direction:

- Move admin actions behind real auth, not a public PIN.
- At minimum, remove public admin operations from the GitHub Pages surface until auth is tightened.

### 2. Published site appears behind local files

The current live GitHub Pages HTML does not exactly match the local `index.html`, `store.html`, or `schedule.html`, so some fixes and content in the repo are not fully reflected on the public site yet.

## Conversion And UX Observations

### Store monetization is still early

The store feels more like a thoughtful recommendation wall than a real shopping flow. That is not a bad foundation, but it needs a stronger conversion structure.

Best next improvements:

- Use real product photos instead of mostly letter/glyph placeholders.
- Add direct tagged affiliate links, not generic search links, once your affiliate setup is ready.
- Group products into travel-ready bundles:
  - `Weekend Away Pack`
  - `Anxious First Boarding Pack`
  - `Heavy Puller Walk Pack`
  - `Senior Comfort Pack`
- Add one-line “why this matters before a trip” copy under each bundle.

### The design language splits in two

`index.html`, `about.html`, and `store.html` have a warmer, more human brand voice. `schedule.html` and `privacy.html` shift into a cooler blue utility style. That makes the experience feel less cohesive and slightly more template-driven.

Best next improvements:

- Keep the warm navy, cream, gold base.
- Pull `schedule.html` and `privacy.html` closer to that palette.
- Use fewer cool clinical blues.
- Keep one accent family only: warm gold + terracotta works better than adding new blue emphasis everywhere.

### Some of the UI still reads a little “AI-designed”

The strongest content on this site is the real dog photography and specific dog stories. The parts that feel less human are the overly polished badges, repeated all-caps mono labels, and decorative treatment density.

To make it feel warmer and more premium:

- Let the candid dog photos do more of the work.
- Reduce repeated badge/chip treatments by 20-30%.
- Keep the serif headlines, but simplify some of the micro-labels.
- Add more plain-English trust copy around vacation concerns:
  - pickup timing
  - medication handling
  - apartment environment
  - update frequency
  - how anxious dogs settle

## Messaging Recommendations For Dog Owners Who Travel

Your highest-intent audience is not “people who like dogs.” It is:

- dog owners planning a trip
- dog owners who travel for work
- dog owners who worry about leaving an anxious dog
- owners willing to spend for safety, updates, and peace of mind

That means the homepage should lean harder into:

- “Leave town without worrying.”
- “Real updates while you’re away.”
- “Direct booking, repeat-client perks, no platform fees.”
- “Calm apartment, neighborhood walks, sitter-tested routines.”

Strong homepage angle:

- `The sitter for dog owners who actually worry on vacation.`

Strong store angle:

- `What we actually recommend after caring for 25+ dogs in real apartments, real walks, and real overnight stays.`

## Best Revenue Opportunities

### 1. Direct bookings

This is still the highest-value conversion on the site. The store should support bookings, not distract from them.

Use the store to reinforce:

- expertise
- repeat-client trust
- subscriber capture
- post-stay follow-up offers

### 2. Affiliate revenue

Best path:

- Join Amazon Associates or another pet-friendly affiliate program.
- Replace search links with exact tagged links.
- Put 3-5 highest-confidence products first.
- Add post-stay follow-up emails with dog-specific picks.

### 3. Subscriber-driven offers

Create a simple funnel:

- free email capture
- “vacation prep for dogs” checklist
- monthly dog notes
- rebooking perk
- featured store picks tied to boarding behavior

## Social And Traffic Recommendations

Worth prioritizing:

- Google Business Profile: probably the best local trust channel after Rover.
- Instagram Reels: dog arrivals, calm apartment moments, pack walks, “what we packed for this pup.”
- TikTok: short sitter-tested gear reviews and “what this dog taught us” clips.
- Local Facebook / Nextdoor / Queens groups: useful for travel-season demand and referrals.

Best content angles:

- `What I pack for a dog boarding for 3 nights`
- `3 products that actually help anxious dogs settle`
- `What dog owners forget before vacation`
- `What worked for a puller like Pretzel`
- `What we used for a tiny nervous dog like Teddy`

## Suggested Next Build Steps

1. Lock down or redesign the public admin/auth flow.
2. Normalize the schedule/privacy page design into the warmer main brand.
3. Replace placeholder shop visuals with real product imagery.
4. Add exact affiliate links and one “best for travel” bundle section.
5. Add a lightweight vacation-prep lead magnet tied to the newsletter.
6. Add stronger Google review / Rover proof blocks near booking CTAs.
