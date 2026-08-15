# 💪 Workout Sharing App — Full Plan (Zero Budget Edition)

## The Idea in One Sentence
A community app where people post structured workouts (tagged by muscle and sub-muscle), and others can filter by what they're training today, preview exact exercise form, and import the workout into their own app with one tap.

## Your Signature Features
What makes this different from existing workout apps:

1. **Sub-muscle targeting** — workouts show they hit upper/mid/lower chest, front/side/rear delts, not just "chest & shoulders"
2. **Muscle coverage map** — a visual body diagram highlighting exactly what a workout covers, so you spot gaps instantly (e.g. "this shoulder workout skips rear delts")
3. **One-tap import** — someone else's workout becomes YOUR trackable workout for today
4. **Built-in form demos** — every exercise shows how to do it, powered by the free wger library, zero work for creators
5. **Smart exercise swap** — don't like one exercise in an imported workout? Tap it and swap it for another exercise targeting the *same sub-muscle* (e.g. swap one middle-chest exercise for another — from the library or from other creators' workouts). Your version updates, the creator's original stays untouched

---

## Tech Stack (All Free)

| Piece | Tool | Cost |
|-------|------|------|
| App (iOS + Android) | React Native + Expo | Free |
| Backend, database, auth | Supabase (free tier) | Free |
| Exercise library + images | wger API | Free, open source |
| Code hosting | GitHub | Free |
| Testing on your phone | Expo Go app | Free |
| Design/mockups | Figma (free plan) | Free |

**Only future costs:** Google Play developer account ($25 one-time), Apple ($99/year — do Android first if money is tight).

---

## How wger Fits In

wger has a free public API with hundreds of exercises including names, descriptions, muscle targets, and images.

- When a creator builds a workout, they **search and pick exercises from wger** — no free typing
- Each exercise automatically carries its muscles, instructions, and image
- You store only the wger exercise ID in your database and fetch details when needed
- **Important:** wger's muscle tags are broad (e.g. "deltoids"). For your sub-muscle feature (front/side/rear delts), you'll add your own tag layer on top — a one-time job of tagging the ~100–150 most common exercises yourself. Totally doable in a few evenings and it becomes your competitive moat.

API docs: https://wger.de/en/software/api

---

## Data Model (Simplified)

```
users          → id, username, avatar, bio
exercises      → wger_id, name, muscle_tags[] (your custom sub-muscle tags)
workouts       → id, creator_id, title, description, muscle_groups[], likes_count
workout_items  → workout_id, exercise_id, sets, reps, rest_seconds, order, note
user_plans     → user_id, workout_id (imported), scheduled_date
logs           → user_id, workout_item_id, date, set_number, weight, reps_done
likes/saves    → user_id, workout_id
```

That's genuinely all you need for v1.

**How the swap works under the hood:** when a user imports a workout, the app creates their own copy of the workout items. Swapping just replaces the exercise_id in *their copy* — matched by the same sub-muscle tag. The swap picker can show: (1) library exercises with that tag, and (2) popular exercises other creators use for that same muscle part, sorted by how often they appear in liked workouts.

---

## The Screens (MVP)

1. **Home / Browse** — feed of workout cards. Filter chips on top: muscle group, sub-muscle, duration, level, equipment
2. **Workout detail** — exercise list, sets/reps, muscle coverage map, creator info, big "Use this workout" button
3. **Exercise detail** — image/demo from wger, instructions, which muscle part it targets
4. **Workout builder** — search wger exercises, add them, set sets/reps/rest, publish
5. **My workouts / Today** — imported workouts, tap to start, log weights and reps set by set
6. **Profile** — your posted workouts, saved workouts, basic stats

---

## Roadmap — How to Actually Go About It

### Phase 0: Setup & Learning (Week 1–2)
- Install Node.js, VS Code, Expo. Create a "hello world" React Native app and run it on your phone via Expo Go
- Create free Supabase project, click around, create your first table
- Call the wger API from your app and just display a list of exercises on screen
- 🎯 Milestone: you see wger exercises inside your own app

### Phase 1: Foundation (Week 3–5)
- Auth: sign up / log in with Supabase (email or Google)
- Set up the database tables above
- Build the exercise browser: search wger, view exercise details with image
- Start your custom sub-muscle tagging (spreadsheet is fine, import later)
- 🎯 Milestone: logged-in user can browse and search exercises

### Phase 2: Core Loop (Week 6–9)
- Workout builder: pick exercises, set sets/reps/rest, save & publish
- Browse feed with filters (muscle group first, sub-muscle after)
- Workout detail page + "Use this workout" import
- **Exercise swap (basic):** tap an exercise in your imported workout → replace with another exercise that has the same sub-muscle tag
- Workout logging: check off sets, enter weight/reps
- 🎯 Milestone: **the full loop works** — one account posts a workout, another imports and logs it. This is your real MVP.

### Phase 3: Polish & Social (Week 10–12)
- Likes and saves
- **Exercise swap (smart):** swap picker also suggests what other creators use for that muscle part, ranked by popularity
- Muscle coverage map visual (even a simple colored front/back body SVG)
- Profiles with posted workouts
- Clean up design, empty states, loading states
- 🎯 Milestone: app feels like a product, not a prototype

### Phase 4: Seed & Launch (Week 13–14)
- **Create 50–100 quality workouts yourself** (chest/tri days, back/bi, legs, push/pull/legs splits, home workouts, beginner plans). This solves the empty-app problem — nobody posts in a dead app
- Get 10–20 friends/gym buddies testing via Expo
- Fix what confuses them
- Publish to Google Play ($25) — Apple later
- 🎯 Milestone: strangers are using it

### Later (v2+)
- Comments, follows, remix (copy & edit someone's workout)
- Progress charts, PRs, streaks
- Optional creator-uploaded videos
- Premium tier if it takes off (that's when money starts, not before)

---

## Weekly Rhythm Suggestion
- Build in small pieces, one screen at a time
- Every feature: make it work ugly first, make it pretty later
- Push code to GitHub every session so you never lose work
- When stuck, paste your error into Claude 😉

## Biggest Risks & How You've Dodged Them
1. **Empty app at launch** → you pre-seed 50–100 workouts
2. **Video hosting costs** → solved by wger's built-in demos
3. **iOS $99 fee** → launch Android-only first
4. **Scope creep** → the phases above are ruthlessly minimal; resist adding features before Phase 2's loop works

## Total Cost to Working MVP: $0
(+$25 when you publish to Google Play)
