-- The two server-side operations behind the signature features:
--   * import_workout  — one-tap import, as a copy
--   * workout_coverage — volume-weighted sub-muscle coverage for the body map

-- ------------------------------------------------------------------ import ---

-- Copies a workout and its items to the calling user. The copy is private and
-- records where it came from. Because it is a copy, a later edit by the creator
-- never mutates the importer's version, and swapping an exercise touches only
-- the importer's row.
create function import_workout(p_source_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_new_id uuid;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  -- Re-check visibility inside the function: this runs as definer, so it must
  -- not rely on the caller's RLS to keep unpublished workouts private.
  if not exists (
    select 1 from workouts w
     where w.id = p_source_id
       and (w.is_published or w.owner_id = v_user)
  ) then
    raise exception 'workout not found or not available';
  end if;

  insert into workouts (owner_id, title, description, is_published, source_workout_id)
  select v_user, w.title, w.description, false, w.id
    from workouts w
   where w.id = p_source_id
  returning id into v_new_id;

  insert into workout_items (
    workout_id, exercise_id, order_index, target_sets, target_reps, rest_seconds, note
  )
  select v_new_id, i.exercise_id, i.order_index, i.target_sets, i.target_reps,
         i.rest_seconds, i.note
    from workout_items i
   where i.workout_id = p_source_id;

  return v_new_id;
end;
$$;

revoke all on function import_workout(uuid) from public, anon;
grant execute on function import_workout(uuid) to authenticated;

-- ---------------------------------------------------------------- coverage ---

-- Working sets per sub-muscle. A primary muscle earns the full set count, a
-- secondary one earns half — so a workout that merely grazes the rear delts
-- cannot look the same as one that trains them (Change 6).
create function workout_coverage(p_workout_id uuid)
returns table (muscle_id uuid, muscle_slug text, weighted_sets numeric)
language sql
stable
security invoker
as $$
  select m.id,
         m.slug,
         sum(i.target_sets * case em.role when 'primary' then 1.0 else 0.5 end)
    from workout_items i
    join exercise_muscles em on em.exercise_id = i.exercise_id
    join muscles m           on m.id = em.muscle_id
   where i.workout_id = p_workout_id
   group by m.id, m.slug;
$$;

-- ------------------------------------------------------------ swap picker ---

-- Candidate replacements for an exercise: anything sharing at least one primary
-- muscle with it. Ordered so better-documented exercises surface first — at
-- launch there are no likes to rank by, so popularity ranking waits for traffic.
create function swap_candidates(p_exercise_id uuid)
returns table (id uuid, name text, slug text, equipment text, image_url text,
               shared_primaries int)
language sql
stable
security invoker
as $$
  with source_primaries as (
    select muscle_id from exercise_muscles
     where exercise_id = p_exercise_id and role = 'primary'
  )
  select e.id, e.name, e.slug, e.equipment, e.image_url,
         count(*)::int as shared_primaries
    from exercises e
    join exercise_muscles em on em.exercise_id = e.id and em.role = 'primary'
    join source_primaries sp on sp.muscle_id = em.muscle_id
   where e.id <> p_exercise_id
   group by e.id, e.name, e.slug, e.equipment, e.image_url
   order by shared_primaries desc,
            (e.image_url is not null) desc,
            e.name;
$$;
