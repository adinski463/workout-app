-- Workout sessions and set logs.
--
-- A session is one visit to the gym. Set logs hang off the session, not off the
-- workout, which is what makes "what did I lift last time?" a cheap query and
-- keeps today's log distinct from last month's.
--
-- Weight is stored in kilograms, always. Display conversion happens in the app
-- from profiles.unit_pref. Migrating a mixed-unit column later is miserable.

create table workout_sessions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references profiles (id) on delete cascade,
  workout_id   uuid not null references workouts (id) on delete cascade,
  started_at   timestamptz not null default now(),
  finished_at  timestamptz,
  note         text check (char_length(note) <= 500)
);

create index workout_sessions_user_idx
  on workout_sessions (user_id, started_at desc);

create table set_logs (
  id               uuid primary key default gen_random_uuid(),
  session_id       uuid not null references workout_sessions (id) on delete cascade,
  workout_item_id  uuid not null references workout_items (id) on delete cascade,
  set_number       int  not null check (set_number between 1 and 20),
  weight_kg        numeric(6, 2) check (weight_kg >= 0),
  reps_done        int check (reps_done between 0 and 200),
  completed_at     timestamptz not null default now(),

  unique (session_id, workout_item_id, set_number)
);

create index set_logs_item_idx on set_logs (workout_item_id, completed_at desc);

-- ---------------------------------------------------------------- policies ---

alter table workout_sessions enable row level security;
alter table set_logs         enable row level security;

create policy "users see only their own sessions"
  on workout_sessions for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "users see only their own set logs"
  on set_logs for all
  using (exists (
    select 1 from workout_sessions s
    where s.id = session_id and s.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from workout_sessions s
    where s.id = session_id and s.user_id = auth.uid()
  ));

-- ------------------------------------------------------------- last session ---

-- The numbers shown inline while logging ("last time: 80 kg x 8"). Without this
-- the tracker is worse than a notes app, which is why it is core and not polish.
create function last_performance(p_workout_item_id uuid)
returns table (set_number int, weight_kg numeric, reps_done int, performed_at timestamptz)
language sql
stable
security invoker
as $$
  with last_session as (
    select l.session_id, max(l.completed_at) as at
      from set_logs l
      join workout_sessions s on s.id = l.session_id
     where l.workout_item_id = p_workout_item_id
       and s.user_id = auth.uid()
     group by l.session_id
     order by at desc
     limit 1
  )
  select l.set_number, l.weight_kg, l.reps_done, l.completed_at
    from set_logs l
    join last_session ls on ls.session_id = l.session_id
   where l.workout_item_id = p_workout_item_id
   order by l.set_number;
$$;
