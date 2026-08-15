# Plan Review — What to Keep, What to Change

Review of `00-original-plan.md` before any code is written.

**Verdict: the concept is sound and the stack is right. Don't rewrite the plan — patch it.**
There are about six changes worth making, and two of them (build order, and the
Google Play tester requirement) affect the schedule badly if discovered late.

---

## Keep as-is

- **The core thesis.** Sub-muscle targeting + coverage map + one-tap import is a real
  gap in the market. Most workout apps are either loggers (Strong, Hevy) or content
  feeds — few let you *import someone else's structured workout and then log it*.
- **Flutter + Supabase.** (Plan says React Native + Expo; the decision is Flutter — see
  "Stack: Flutter" below.) Either works; Flutter is arguably the better fit here.
- **Android first, iOS later.** Right call. $99/year for an app with no users is waste.
- **Pre-seeding 50–100 workouts.** This is the single most important non-code task in
  the plan, and most first-time founders skip it. Keep it.
- **Phase discipline / anti-scope-creep.** Keep the ruthlessness.
- **A custom sub-muscle tag layer on top of a free exercise library.** This is the moat.
  Correct instinct.

---

## Change 1 — Build the tracker for yourself first, the social layer second

**This is the most important change.**

The current order makes the app useless to any single person until the end of Phase 2
(week 9). Nothing you build before then is something you'd actually open at the gym.
That's a motivation killer, and it means every design decision until week 9 is guesswork
because you've never used the thing.

Flip it:

1. Browse/search exercises (already Phase 1)
2. **Build a workout for yourself** and save it privately
3. **Log it at the gym** — sets, reps, weight, rest timer
4. *Then* add publish / browse feed / import

The creator flow and the personal flow are **the same code**. A "published workout" is
just a private workout with `is_published = true`. So this reordering costs you nothing
and buys you: a tool you personally use from week ~5, real dogfooding, and a fallback
outcome that isn't zero if the community never materializes.

## Change 2 — Start Google Play closed testing in week 6, not week 13

New **personal** Google Play developer accounts (created after 13 Nov 2023) must run a
closed test with **12 testers continuously opted in for 14 days** before you can apply
for production access. Organization accounts are exempt; personal ones are not.

Consequences for the plan:

- The $25 account should be bought **early**, not at launch, so the clock can start.
- The "10–20 friends testing via Expo" step in Phase 4 *is* your tester cohort — but they
  need to be opted in via **Play closed testing**, not Expo Go, or the days don't count.
- 12 people who stay opted in for 14 consecutive days is harder than it sounds. Recruit
  ~18 to land 12. Opting out and back in resets the streak.
- Realistically add 3–6 weeks of buffer between "app is done" and "app is public".

Move the store setup to roughly the start of Phase 3.

## Change 3 — Don't trust "every exercise has a form demo"

The plan says built-in demos are free and "zero work for creators". That's the assumption
most likely to be wrong.

- wger's exercise catalog is community-contributed and **image coverage is uneven** —
  a substantial share of exercises have no image at all, and video coverage is much
  thinner still. Multilingual entries are inconsistent in quality.
- The data is **CC-BY-SA 4.0**. That's fine for your use, but it means you must show
  attribution in-app, and derivative distributions of the catalog inherit ShareAlike.
  Your *own* sub-muscle tags are a separate layer — keep them in your own table so
  there's no ambiguity about what's yours.

What to do instead:

- Treat "has an image" as a **quality filter**, not a guarantee. When you pick your
  ~120 exercises to tag, prefer the ones that already have decent images.
- Have a designed empty state for image-less exercises (icon + text instructions), not a
  broken image box.
- Keep the exercise source **swappable** (see Change 4). `free-exercise-db` is public
  domain with ~800 exercises and images, and there are hosted GIF-based catalogs; you may
  want to blend sources later. Don't hard-couple to wger.

## Change 4 — Fix the data model before you create the first table

The sketch in the plan has four issues that are cheap now and expensive in month three.

### 4a. Don't use `wger_id` as your primary key

```
exercises → id (your own uuid PK)
            source        ('wger' | 'manual' | 'free-exercise-db')
            source_id     (nullable, unique per source)
            name, description, image_url, equipment
```

Otherwise you can never add an exercise that isn't in wger, and you're locked to one
provider forever.

### 4b. Mirror the exercise catalog into your own database — don't fetch on demand

The plan says "store only the wger exercise ID and fetch details when needed." Don't.
On a phone, on gym wifi, that's a slow screen and a third-party dependency in your hot
path — and it hammers a free community API you don't control.

Instead: run a periodic sync job that copies the catalog into your Supabase tables, and
serve everything from your own DB. Your app then works even if wger is down, and search
becomes a fast local query instead of an HTTP round-trip.

### 4c. Muscles need to be a real table, not a string array

`muscle_tags[]` on the exercise can't express *primary vs secondary*, and a coverage map
built on it will lie — an exercise that grazes the rear delts will look identical to one
that targets them.

```
muscles           → id, name, parent_muscle_id   (deltoid → front/side/rear delt)
exercise_muscles  → exercise_id, muscle_id, role ('primary' | 'secondary')
```

This makes all three signature features trivial queries instead of array gymnastics:
filtering by sub-muscle, the coverage map, and the swap picker ("same primary muscle").

### 4d. The import/logging tables contradict each other

The plan says importing creates a *copy* of the workout items, but the schema only has
`user_plans → user_id, workout_id`, and `logs → workout_item_id`. With that schema, your
log rows point at the **creator's** items, so if the creator edits or deletes their
workout your history breaks — and a swap has nowhere to be stored.

Make the copy explicit, and add a session concept so you can tell today's log from last
month's:

```
workouts           → id, owner_id, title, description, is_published,
                     source_workout_id (nullable — what it was imported from),
                     likes_count
workout_items      → id, workout_id, exercise_id, order_index,
                     target_sets, target_reps, rest_seconds, note
workout_sessions   → id, user_id, workout_id, started_at, finished_at
set_logs           → id, session_id, workout_item_id, set_number,
                     weight_kg, reps_done, completed_at
```

One `workouts` table serves both cases. Import = copy the row + its items with
`source_workout_id` set. Swap = update `exercise_id` on the user's copy. Nothing to
special-case.

Two details worth locking in now because migrating them later is miserable:
- **Store weight in kg always**, convert to lbs at display time from a user preference.
- **Row Level Security policies from day one.** Supabase tables are exposed directly to
  the client; without RLS, anyone with your anon key can read and write every row. This
  is not optional and it is the single most common way small Supabase apps get burned.

## Change 5 — Two features are missing that decide whether the logger is usable

Both belong in the core loop, not in "polish":

1. **Show last session's numbers inline while logging.** "Last time: 80 kg × 8" next to
   the input. Without it your logger is worse than the notes app people already use.
   It's the reason anyone opens a tracker twice. Cheap to build once `workout_sessions`
   exists (Change 4d) — which is another reason to fix the schema first.
2. **Rest timer.** Auto-starts when a set is checked off. Small, expected, noticeable
   when absent.

And one thing to design for early even if implemented simply: **gyms have terrible
signal**. Logging must not fail when the network drops. At minimum, write optimistically
to local state and sync in the background; never block a set from being recorded on an
HTTP response.

## Change 6 — Make the coverage map volume-aware

As specified, the map answers "is this muscle touched?" — so one throwaway set of rear
delt flies makes a workout look complete. That's the exact failure mode the feature
exists to prevent.

Colour by **number of working sets** hitting each sub-muscle (primary sets count 1,
secondary count 0.5), with three bands: none / light / solid. Same amount of SVG work,
dramatically more honest, and it's what makes the feature screenshot-worthy — which
matters, because a coverage map is the thing people will share.

---

---

## Stack: Flutter (decided — replaces React Native + Expo in the original plan)

Flutter is a good choice for this app, and for two of the signature features it's the
better one. Nothing in Changes 1–6 above depends on the framework — the schema, the build
order, the Play Store timeline and the compliance work are all identical either way.

### Where Flutter is actively better for *this* app

- **The muscle coverage map.** This is your headline feature and it's a custom-drawn,
  volume-shaded body diagram. Flutter's `CustomPaint`/`Canvas` (plus `flutter_svg` for the
  body outline) is a first-class drawing surface — you get precise control over per-region
  fills and hit-testing without fighting the platform. In React Native the equivalent runs
  through a bridge-backed SVG library and is fiddlier.
- **Offline logging.** Change 5 requires logging that survives dead gym wifi. Flutter's
  local-database story (**Drift**, or `sqflite` if you want it simpler) is mature and
  type-safe, which makes "write locally first, sync to Supabase in the background" a
  well-trodden pattern rather than an improvisation.
- **One coherent toolchain.** For a first-time solo developer this matters more than
  people admit: one official SDK, one widget library, one `flutter doctor` telling you
  what's wrong. The RN ecosystem is more fragmented and more prone to version-mismatch
  rabbit holes that eat entire evenings.
- **Dart is easy to pick up** — if you know any C-family or JS-like language you'll be
  productive within days, and it's statically typed, which catches a whole class of bug
  before it reaches your phone.

### What you give up

- **iOS needs a Mac — or CI.** Expo's cloud builds let you ship iOS from a Windows/Linux
  machine. With Flutter you either need macOS, or a CI service: **Codemagic's free tier
  includes ~500 macOS build minutes/month**, which is plenty for a solo project. Note the
  caveat — CI can *build and ship* iOS, but debugging on an iOS simulator or device still
  needs a Mac. Since the plan is Android-first this is deferred, not blocking. Just don't
  promise anyone an iOS build before you've solved it.
- **Slightly larger APK** (a few MB of engine). Irrelevant for this app.
- **Marginally smaller pool of copy-pasteable answers** than RN for niche problems.
  In practice both are extremely well covered.

### Concrete package choices

| Need | Package | Note |
|------|---------|------|
| Backend / auth / DB | `supabase_flutter` | Official, actively maintained, v2+ |
| State management | `riverpod` | Compile-safe, good async handling; `provider` if you want the gentlest curve |
| Local DB (offline logs) | `drift` | Type-safe SQLite; `sqflite` is the simpler fallback |
| Body diagram | `flutter_svg` + `CustomPaint` | Coverage map |
| Navigation | `go_router` | Deep links matter later for sharing workouts |
| HTTP (catalog sync) | `dio` or `http` | Only needed for the sync job |
| Errors / analytics | `sentry_flutter`, `posthog_flutter` | Add before the test phase |
| iOS builds later | Codemagic free tier | Or GitHub Actions with a macOS runner |

### Two Flutter-specific things to get right early

1. **Deep links from day one-ish.** "Share this workout" is the growth mechanism for a
   community app. Set up `go_router` with a URL scheme early so a shared link opens the
   workout in-app rather than nowhere. Retrofitting routing is annoying.
2. **Keep Supabase calls out of your widgets.** Put them behind a repository class that
   your Riverpod providers call. That's what makes the offline-first layer in Change 5
   droppable in later without rewriting every screen.

---

## Smaller notes

- **"Smart swap ranked by popularity in liked workouts" needs data you won't have.**
  At launch there are no likes to rank by. Ship the library-based swap (same primary
  muscle, sorted by how well-documented the exercise is) and let popularity ranking
  switch on later once there's traffic. Don't build the ranking infrastructure in Phase 3.
- **Distribute test builds as an APK or via Play closed testing.** With Flutter this is
  the default path anyway — there is no Expo Go equivalent to get wrong.
- **Supabase free tier pauses a project after 7 days with no API requests**, caps at
  500 MB database and 2 active projects. Fine for this app's data volume — workouts and
  set logs are tiny — but once real testers are on it, know that an idle week takes you
  offline until you manually resume.
- **Add error reporting and basic analytics before the test phase** (Sentry / PostHog,
  both free at this scale). "Fix what confuses them" in Phase 4 is blind without knowing
  where people drop off or what crashed.
- **Auth: start with email magic link only.** Google/Apple sign-in add configuration
  overhead and Apple Sign-In becomes *mandatory* on iOS if you offer other social logins.
- **Three compliance items block release, so don't discover them in week 14:**
  - a privacy policy at a public URL (required by Play);
  - **in-app account deletion plus a web-accessible deletion request URL** — required for
    any app with accounts, and a common rejection reason;
  - for user-generated content, a **report/block mechanism** and a moderation path. Play
    rejects UGC apps without safeguards. A "report workout" button and a flag column is
    enough to start.
  - Also add a plain health disclaimer. You're distributing exercise instructions.
- **Timeline.** 14 weeks assumes no learning curve. For a first Flutter project built
  in evenings, roughly double is normal. This isn't a reason to change the plan — just
  track **milestones, not weeks**, so slipping doesn't feel like failure and cause you to
  cut the parts that matter.

---

## Revised roadmap

Same shape, resequenced around the changes above.

### Phase 0 — Setup
Flutter SDK + Android Studio, `flutter doctor` clean, hello-world running on your own
phone over USB/wireless debugging. Supabase project created. One exercise-API call
rendering a `ListView`.
🎯 Real exercises visible inside your own app, on your own phone.

### Phase 1 — Foundation
- Auth (email magic link) + **RLS policies on every table**
- Full schema from Change 4, including muscles/exercise_muscles
- **Catalog sync job**: mirror the exercise library into Supabase
- Exercise browser: search, detail view, image with a proper empty state
- Begin sub-muscle tagging (spreadsheet → import). Target ~120 exercises, primary +
  secondary, prioritising ones with usable images
🎯 Logged-in user can search a locally-served exercise catalog.

### Phase 2 — The loop that serves *one* user (the big reorder)
- Workout builder → saves privately
- **Logging: sessions, set-by-set weight/reps, last-session numbers inline, rest timer**
- Optimistic/offline-tolerant writes
🎯 **You use this app at the gym yourself.** This is the real first milestone.

### Phase 3 — The social layer
- Publish (`is_published`), browse feed, filters (muscle group → sub-muscle)
- Workout detail + one-tap import (copy rows, set `source_workout_id`)
- Exercise swap, library-based
- Coverage map, volume-aware
- **Buy the Play account and start closed testing here** — the 14-day clock runs in
  parallel with development
🎯 One account posts, another imports and logs it.

### Phase 4 — Polish, compliance, seed
- Likes/saves, profiles, empty and loading states, design pass
- Privacy policy, account deletion (in-app + web URL), report/moderation, health
  disclaimer, wger attribution
- Sentry + analytics
- Seed 50–100 workouts yourself
- 12+ testers held for 14 consecutive days → apply for production
🎯 Strangers are using it.

### Later (v2+)
Comments, follows, remix, progress charts and PRs, popularity-ranked swap, creator video,
iOS, premium.

---

## Total cost

Still $0 to a working MVP, +$25 for Play. That part of the plan holds up completely.
