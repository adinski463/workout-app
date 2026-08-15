# Workout App

A community app for structured workouts tagged by **sub-muscle** — upper/mid/lower
chest, front/side/rear delts — so you can see exactly what a session trains, spot
what it misses, import someone else's workout, and log it at the gym.

Flutter + Supabase. See [`docs/01-plan-review.md`](docs/01-plan-review.md) for the
reasoning behind the architecture and the build order.

---

## What works today

The app runs entirely on-device, with no backend required. That is deliberate: the
build order puts a tool you personally use ahead of the social layer.

- **Exercise library** — 125 exercises, each tagged with primary and secondary
  sub-muscles. Search, filter by muscle group, then narrow to a single sub-muscle,
  filter by equipment, or restrict to exercises that *directly* target a muscle
  rather than merely assisting.
- **Workout builder** — assemble exercises, set sets/reps/rest, reorder, and swap
  any exercise for another that trains the same primary muscles.
- **Session logging** — set-by-set weight and reps, with **last session's numbers
  shown inline** and pre-filled, an automatic **rest timer**, and correction by
  re-tapping a set. An interrupted workout can be resumed.
- **Muscle coverage map** — front and back body diagrams shaded by weighted
  working sets (primary counts 1.0 per set, secondary 0.5), with tappable regions
  and automatic **gap detection**: a shoulder day of presses and lateral raises is
  told, in words, that it skips the rear delts.
- **History** — past sessions with the sets recorded in each, kg/lb toggle.

Everything is local-first: no screen blocks on the network, because gym signal is
unreliable and a set must never fail to record because a request did.

## What is built but not yet wired up

The **backend schema is complete and tested**, but the app does not talk to it yet.
`supabase/migrations/` defines the catalog, profiles, workouts, session logging, the
social layer (likes, saves, reports) and moderation, with row level security on
every table and server-side functions for `import_workout`, `workout_coverage` and
`swap_candidates`.

`supabase/test/run.sh` applies those migrations to a throwaway Postgres and asserts
the security boundaries actually hold — that one user cannot read or write another's
data, that an import produces an independent copy, and that a `SECURITY DEFINER`
function cannot be used to reach an unpublished workout.

Connecting the Flutter client to it (auth, publishing, the browse feed, remote
import) is the next phase.

## Not started

Auth, the public feed, likes/saves, profiles, catalog sync from an upstream library,
and the Play Store compliance work (privacy policy, account deletion, reporting UI).
The roadmap in `docs/01-plan-review.md` covers the ordering, including the Google
Play closed-testing requirement that needs starting well before launch.

---

## Running it

Requires the Flutter SDK (3.29+) and, for a device build, Android Studio's SDK.

```bash
flutter pub get
flutter run          # with a device or emulator attached
```

### Tests

```bash
flutter analyze      # static analysis — currently clean
flutter test         # 49 tests: catalog, coverage maths, repository, widgets
```

The widget tests boot the real app against an in-memory repository and drive it the
way a user would: create a workout, filter the library, log a set, read the coverage
map.

### Database tests

Needs a local Postgres. No Supabase project required — the shim stands in for the
parts Supabase would provide.

```bash
supabase/test/run.sh
```

### Applying the schema to a real Supabase project

Run the files in `supabase/migrations/` in numeric order in the SQL editor, then
seed the catalog from `assets/catalog/` (the muscles and exercises tables mirror
those JSON files; `slug` is the join key).

---

## Layout

```
lib/
  core/          theme, unit conversion (weight is always stored in kg)
  data/
    catalog/     the exercise library and its sub-muscle tags
    local/       sqflite database and the on-device repository
    models/      workouts, items, sessions, set logs
    repository.dart   the interface every screen depends on
    coverage.dart     volume-weighted coverage maths
  features/
    browse/      exercise library and detail
    builder/     exercise and swap pickers
    workouts/    workout list and detail/builder
    logging/     the gym screen and rest timer
    coverage/    the body map (CustomPaint) and its readout
    history/     past sessions
assets/catalog/  muscles.json, exercises.json — the hand-authored tag layer
supabase/        migrations and their tests
docs/            the original plan and the pre-build review
```

The UI depends on the `WorkoutRepository` interface, never on sqflite directly, so
the Supabase-backed sync layer can be added without touching a screen.

## A note on the exercise data

`assets/catalog/exercises.json` is hand-authored. The sub-muscle tags are the thing
no free exercise API provides, and they are what the coverage map, the filters and
the swap picker all depend on — so they are covered by tests that fail the build on
a bad muscle reference, a muscle listed as both primary and secondary, or a
sub-muscle with fewer than two exercises training it (which would leave a coverage
gap unfixable inside the app).

Merging an upstream library later is expected: `exercises` carries `source` and
`source_id` columns so the catalog is never locked to one provider. Any upstream
content pulled in keeps its own licence and attribution requirements — wger's
catalog, for example, is CC-BY-SA 4.0 and needs an attribution notice in-app.
