-- Workouts and their exercise items.
--
-- One table serves both cases (docs/01-plan-review.md, Change 4d):
--   * a private workout you built for yourself  -> is_published = false
--   * a published one others can browse         -> is_published = true
--   * a copy you imported from someone else     -> source_workout_id set
--
-- Importing copies the rows. That means the creator editing or deleting their
-- workout can never break your history or your logs.

create table workouts (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null references profiles (id) on delete cascade,
  title              text not null check (char_length(title) between 1 and 80),
  description        text check (char_length(description) <= 1000),
  is_published       boolean not null default false,
  source_workout_id  uuid references workouts (id) on delete set null,
  likes_count        int not null default 0,
  -- Denormalised for feed filtering; kept in sync by trigger from the items.
  est_minutes        int,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index workouts_owner_idx     on workouts (owner_id);
create index workouts_published_idx on workouts (is_published, created_at desc)
  where is_published;

create table workout_items (
  id            uuid primary key default gen_random_uuid(),
  workout_id    uuid not null references workouts (id)  on delete cascade,
  exercise_id   uuid not null references exercises (id) on delete restrict,
  order_index   int  not null,
  target_sets   int  not null default 3 check (target_sets between 1 and 20),
  target_reps   int  not null default 10 check (target_reps between 1 and 100),
  rest_seconds  int  not null default 90 check (rest_seconds between 0 and 600),
  note          text check (char_length(note) <= 200),

  unique (workout_id, order_index) deferrable initially deferred
);

create index workout_items_workout_idx on workout_items (workout_id);

-- ---------------------------------------------------------------- policies ---

alter table workouts      enable row level security;
alter table workout_items enable row level security;

create policy "published workouts are readable, own workouts always"
  on workouts for select
  using (is_published or owner_id = auth.uid());

create policy "users create their own workouts"
  on workouts for insert with check (owner_id = auth.uid());

create policy "users update their own workouts"
  on workouts for update
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "users delete their own workouts"
  on workouts for delete using (owner_id = auth.uid());

-- Items inherit visibility from their parent workout.
create policy "items follow workout visibility"
  on workout_items for select
  using (exists (
    select 1 from workouts w
    where w.id = workout_id
      and (w.is_published or w.owner_id = auth.uid())
  ));

create policy "users write items on their own workouts"
  on workout_items for all
  using (exists (
    select 1 from workouts w where w.id = workout_id and w.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from workouts w where w.id = workout_id and w.owner_id = auth.uid()
  ));

-- ---------------------------------------------------------------- triggers ---

create function touch_workout_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger workouts_touch_updated_at
  before update on workouts
  for each row execute function touch_workout_updated_at();

-- Rough duration estimate: working time plus rest, so the feed can offer a
-- "under 45 min" filter without scanning items on every query.
create function recalc_workout_estimate()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  target_workout uuid := coalesce(new.workout_id, old.workout_id);
begin
  update workouts w
     set est_minutes = coalesce((
           select ceil(sum(i.target_sets * (i.rest_seconds + i.target_reps * 4)) / 60.0)
             from workout_items i
            where i.workout_id = target_workout
         ), 0)
   where w.id = target_workout;

  return null;
end;
$$;

create trigger workout_items_recalc_estimate
  after insert or update or delete on workout_items
  for each row execute function recalc_workout_estimate();
