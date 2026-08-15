-- Exercise catalog: muscles, exercises, and the link between them.
--
-- Design notes (see docs/01-plan-review.md, Change 4):
--   * exercises.id is our own uuid. `source`/`source_id` record where a row came
--     from, so the catalog is never locked to a single upstream provider.
--   * Muscles are a real table with a parent link, not a string array, so
--     sub-muscle filtering and the coverage map are plain joins.
--   * exercise_muscles.role distinguishes primary from secondary work. Without
--     it the coverage map cannot tell a rear-delt row from a rear-delt graze.
--
-- The whole catalog is world-readable and writable only by the service role
-- (the sync job). No user-facing write policies exist, so RLS denies writes.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------- muscles ---

create table muscles (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,
  name        text not null,
  parent_id   uuid references muscles (id) on delete cascade,
  -- Which side of the body diagram this region is drawn on.
  body_side   text not null check (body_side in ('front', 'back')),
  sort_order  int  not null default 0
);

comment on table muscles is
  'Hierarchical muscle taxonomy. Rows with parent_id set are sub-muscles.';

create index muscles_parent_idx on muscles (parent_id);

-- -------------------------------------------------------------- exercises ---

create table exercises (
  id          uuid primary key default gen_random_uuid(),
  source      text not null default 'manual'
                check (source in ('manual', 'wger', 'free-exercise-db')),
  source_id   text,
  slug        text not null unique,
  name        text not null,
  description text,
  equipment   text not null default 'other'
                check (equipment in ('barbell', 'dumbbell', 'machine', 'cable',
                                     'bodyweight', 'kettlebell', 'band', 'other')),
  mechanic    text check (mechanic in ('compound', 'isolation')),
  difficulty  text check (difficulty in ('beginner', 'intermediate', 'advanced')),
  -- Nullable on purpose: upstream image coverage is uneven, so the UI must
  -- degrade gracefully rather than show a broken image box.
  image_url   text,
  created_at  timestamptz not null default now(),

  unique (source, source_id)
);

create index exercises_name_idx on exercises using gin (to_tsvector('english', name));

-- ------------------------------------------------------- exercise_muscles ---

create table exercise_muscles (
  exercise_id uuid not null references exercises (id) on delete cascade,
  muscle_id   uuid not null references muscles (id)   on delete cascade,
  role        text not null check (role in ('primary', 'secondary')),

  primary key (exercise_id, muscle_id)
);

create index exercise_muscles_muscle_idx on exercise_muscles (muscle_id);

-- ---------------------------------------------------------------- policies ---

alter table muscles          enable row level security;
alter table exercises        enable row level security;
alter table exercise_muscles enable row level security;

create policy "catalog is world readable"
  on muscles for select using (true);

create policy "catalog is world readable"
  on exercises for select using (true);

create policy "catalog is world readable"
  on exercise_muscles for select using (true);
