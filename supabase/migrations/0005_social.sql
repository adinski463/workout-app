-- Likes, saves, and the moderation path.
--
-- Google Play rejects user-generated-content apps without a way to report
-- objectionable content, so the report table ships with v1 rather than being
-- bolted on at review time (docs/01-plan-review.md).

create table workout_likes (
  user_id    uuid not null references profiles (id) on delete cascade,
  workout_id uuid not null references workouts (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, workout_id)
);

create table workout_saves (
  user_id    uuid not null references profiles (id) on delete cascade,
  workout_id uuid not null references workouts (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, workout_id)
);

create index workout_likes_workout_idx on workout_likes (workout_id);
create index workout_saves_user_idx    on workout_saves (user_id, created_at desc);

create table content_reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references profiles (id) on delete cascade,
  workout_id   uuid not null references workouts (id) on delete cascade,
  reason       text not null
                 check (reason in ('spam', 'harassment', 'dangerous', 'other')),
  detail       text check (char_length(detail) <= 500),
  created_at   timestamptz not null default now(),

  unique (reporter_id, workout_id)
);

-- ---------------------------------------------------------------- policies ---

alter table workout_likes   enable row level security;
alter table workout_saves   enable row level security;
alter table content_reports enable row level security;

-- Likes are public so the UI can show who liked what.
create policy "likes are world readable"
  on workout_likes for select using (true);

create policy "users manage their own likes"
  on workout_likes for insert with check (user_id = auth.uid());

create policy "users remove their own likes"
  on workout_likes for delete using (user_id = auth.uid());

-- Saves are private.
create policy "users see their own saves"
  on workout_saves for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Reports are write-only for users: you may file one, you may not read the
-- queue. Moderation reads happen through the service role.
create policy "users file their own reports"
  on content_reports for insert with check (reporter_id = auth.uid());

-- ---------------------------------------------------------- likes counter ---

create function sync_likes_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update workouts w
     set likes_count = (
           select count(*) from workout_likes l where l.workout_id = w.id
         )
   where w.id = coalesce(new.workout_id, old.workout_id);

  return null;
end;
$$;

create trigger workout_likes_sync_count
  after insert or delete on workout_likes
  for each row execute function sync_likes_count();
