-- RLS and business-logic tests.
--
-- Every assertion below is a thing that, if wrong, leaks one user's data to
-- another or lets someone edit content they do not own. Run with:
--     supabase/test/run.sh

\set ON_ERROR_STOP on
set client_min_messages = warning;

-- Supabase grants these by default; the shim database needs them explicitly so
-- the tests exercise policies rather than raw table privileges.
grant usage on schema public to anon, authenticated;
grant all on all tables in schema public to anon, authenticated;
grant all on all sequences in schema public to anon, authenticated;

-- ------------------------------------------------------------- fixtures ----

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.com');

insert into muscles (id, slug, name, parent_id, body_side) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'chest', 'Chest', null, 'front'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'chest-mid', 'Mid Chest',
     'aaaaaaaa-0000-0000-0000-000000000001', 'front'),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'delts', 'Deltoids', null, 'front'),
  ('aaaaaaaa-0000-0000-0000-000000000004', 'delts-rear', 'Rear Delts',
     'aaaaaaaa-0000-0000-0000-000000000003', 'back');

insert into exercises (id, slug, name, equipment) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'bench-press', 'Bench Press', 'barbell'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'db-press', 'Dumbbell Press', 'dumbbell'),
  ('bbbbbbbb-0000-0000-0000-000000000003', 'face-pull', 'Face Pull', 'cable');

insert into exercise_muscles (exercise_id, muscle_id, role) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002', 'primary'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000003', 'secondary'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', 'primary'),
  ('bbbbbbbb-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000004', 'primary');

-- Profiles are created by the signup trigger; confirm that actually fired.
do $$
begin
  if (select count(*) from profiles) <> 2 then
    raise exception 'FAIL: signup trigger did not create profiles (got %)',
      (select count(*) from profiles);
  end if;
end
$$;

-- Alice: one private workout, one published.
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

insert into workouts (id, owner_id, title, is_published) values
  ('cccccccc-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'Alice private chest day', false),
  ('cccccccc-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111', 'Alice published push day', true);

insert into workout_items (workout_id, exercise_id, order_index, target_sets) values
  ('cccccccc-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000001', 0, 4),
  ('cccccccc-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000003', 1, 3),
  ('cccccccc-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', 0, 3);

-- ------------------------------------------------- test: workout visibility --

reset role;
set role authenticated;
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

do $$
declare n int;
begin
  select count(*) into n from workouts;
  if n <> 1 then
    raise exception 'FAIL: Bob should see exactly 1 (published) workout, saw %', n;
  end if;

  select count(*) into n from workouts
   where id = 'cccccccc-0000-0000-0000-000000000001';
  if n <> 0 then
    raise exception 'FAIL: Bob can read Alice''s PRIVATE workout';
  end if;

  -- Items must inherit the parent's visibility, not be independently readable.
  select count(*) into n from workout_items
   where workout_id = 'cccccccc-0000-0000-0000-000000000001';
  if n <> 0 then
    raise exception 'FAIL: Bob can read items of Alice''s private workout';
  end if;

  select count(*) into n from workout_items
   where workout_id = 'cccccccc-0000-0000-0000-000000000002';
  if n <> 2 then
    raise exception 'FAIL: Bob should see 2 items of the published workout, saw %', n;
  end if;
end
$$;

-- ------------------------------------------------------ test: write denial --

do $$
declare n int;
begin
  -- Silently affecting zero rows is the correct RLS outcome for UPDATE.
  update workouts set title = 'hijacked'
   where id = 'cccccccc-0000-0000-0000-000000000002';
  get diagnostics n = row_count;
  if n <> 0 then
    raise exception 'FAIL: Bob updated Alice''s workout';
  end if;

  delete from workouts where id = 'cccccccc-0000-0000-0000-000000000002';
  get diagnostics n = row_count;
  if n <> 0 then
    raise exception 'FAIL: Bob deleted Alice''s workout';
  end if;
end
$$;

-- Inserting a workout owned by someone else must be refused outright.
do $$
begin
  begin
    insert into workouts (owner_id, title)
    values ('11111111-1111-1111-1111-111111111111', 'forged');
    raise exception 'FAIL: Bob created a workout owned by Alice';
  exception
    when insufficient_privilege then null;  -- expected
  end;
end
$$;

-- Adding an item to someone else's workout must be refused too.
do $$
begin
  begin
    insert into workout_items (workout_id, exercise_id, order_index)
    values ('cccccccc-0000-0000-0000-000000000002',
            'bbbbbbbb-0000-0000-0000-000000000002', 9);
    raise exception 'FAIL: Bob added an item to Alice''s workout';
  exception
    when insufficient_privilege then null;  -- expected
  end;
end
$$;

-- ------------------------------------------------------------ test: import --

do $$
declare
  v_copy uuid;
  n int;
begin
  v_copy := import_workout('cccccccc-0000-0000-0000-000000000002');

  select count(*) into n from workouts
   where id = v_copy
     and owner_id = '22222222-2222-2222-2222-222222222222'
     and is_published = false
     and source_workout_id = 'cccccccc-0000-0000-0000-000000000002';
  if n <> 1 then
    raise exception 'FAIL: import did not produce a private copy owned by Bob';
  end if;

  select count(*) into n from workout_items where workout_id = v_copy;
  if n <> 2 then
    raise exception 'FAIL: import copied % items, expected 2', n;
  end if;

  -- The copy must be independent: swapping an exercise in Bob's version must
  -- not touch Alice's original.
  update workout_items
     set exercise_id = 'bbbbbbbb-0000-0000-0000-000000000002'
   where workout_id = v_copy and order_index = 0;

  select count(*) into n from workout_items
   where workout_id = 'cccccccc-0000-0000-0000-000000000002'
     and exercise_id = 'bbbbbbbb-0000-0000-0000-000000000001';
  if n <> 1 then
    raise exception 'FAIL: swapping in the copy mutated the original';
  end if;
end
$$;

-- Importing a workout you cannot see must fail, even though import_workout is
-- SECURITY DEFINER and therefore bypasses RLS internally.
do $$
begin
  begin
    perform import_workout('cccccccc-0000-0000-0000-000000000001');
    raise exception 'FAIL: Bob imported Alice''s private workout';
  exception
    when others then
      if sqlerrm not like '%not found or not available%' then raise; end if;
  end;
end
$$;

-- ----------------------------------------------------------- test: logging --

do $$
declare
  v_session uuid;
  v_item    uuid;
  v_copy    uuid;
begin
  select id into v_copy from workouts
   where owner_id = '22222222-2222-2222-2222-222222222222' limit 1;
  select id into v_item from workout_items where workout_id = v_copy limit 1;

  insert into workout_sessions (user_id, workout_id)
  values ('22222222-2222-2222-2222-222222222222', v_copy)
  returning id into v_session;

  insert into set_logs (session_id, workout_item_id, set_number, weight_kg, reps_done)
  values (v_session, v_item, 1, 80.0, 8),
         (v_session, v_item, 2, 80.0, 7);
end
$$;

-- Alice must not see Bob's sessions or set logs.
reset role;
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$
declare n int;
begin
  select count(*) into n from workout_sessions;
  if n <> 0 then
    raise exception 'FAIL: Alice can see Bob''s sessions (% rows)', n;
  end if;

  select count(*) into n from set_logs;
  if n <> 0 then
    raise exception 'FAIL: Alice can see Bob''s set logs (% rows)', n;
  end if;
end
$$;

-- ---------------------------------------------------------- test: coverage --

-- 4 sets of bench (primary mid-chest, secondary delts) + 3 sets of face pull
-- (primary rear delts) => mid-chest 4.0, delts 2.0, rear delts 3.0.
do $$
declare
  v_chest numeric;
  v_delts numeric;
  v_rear  numeric;
begin
  select weighted_sets into v_chest from workout_coverage('cccccccc-0000-0000-0000-000000000002') where muscle_slug = 'chest-mid';
  select weighted_sets into v_delts from workout_coverage('cccccccc-0000-0000-0000-000000000002') where muscle_slug = 'delts';
  select weighted_sets into v_rear  from workout_coverage('cccccccc-0000-0000-0000-000000000002') where muscle_slug = 'delts-rear';

  if v_chest <> 4.0 then raise exception 'FAIL: mid-chest coverage % expected 4.0', v_chest; end if;
  if v_delts <> 2.0 then raise exception 'FAIL: secondary delt coverage % expected 2.0 (half of 4 sets)', v_delts; end if;
  if v_rear  <> 3.0 then raise exception 'FAIL: rear delt coverage % expected 3.0', v_rear; end if;
end
$$;

-- ------------------------------------------------------ test: swap picker ---

do $$
declare v_top text;
begin
  -- Bench press shares its primary (mid chest) with the dumbbell press, and
  -- must not suggest the face pull, which trains something else entirely.
  select name into v_top from swap_candidates('bbbbbbbb-0000-0000-0000-000000000001') limit 1;
  if v_top <> 'Dumbbell Press' then
    raise exception 'FAIL: top swap candidate for bench was %, expected Dumbbell Press', v_top;
  end if;

  if exists (
    select 1 from swap_candidates('bbbbbbbb-0000-0000-0000-000000000001')
     where name = 'Face Pull'
  ) then
    raise exception 'FAIL: swap picker suggested an unrelated muscle group';
  end if;
end
$$;

-- ------------------------------------------------------ test: catalog is RO --

do $$
begin
  begin
    insert into exercises (slug, name) values ('hacked', 'Hacked Exercise');
    raise exception 'FAIL: a normal user wrote to the exercise catalog';
  exception
    when insufficient_privilege then null;  -- expected
  end;
end
$$;

reset role;
select 'ALL RLS AND LOGIC TESTS PASSED' as result;
