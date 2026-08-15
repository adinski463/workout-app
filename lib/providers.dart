import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/units.dart';
import 'data/catalog/catalog_models.dart';
import 'data/coverage.dart';
import 'data/repository.dart';
import 'data/models/workout.dart';

/// Catalog and repository are built once during startup and injected as
/// overrides in `main`, so every screen can read them synchronously instead of
/// unwrapping an AsyncValue on every build.
final catalogProvider = Provider<Catalog>(
  (ref) => throw UnimplementedError('catalogProvider must be overridden'),
);

final repositoryProvider = Provider<WorkoutRepository>(
  (ref) => throw UnimplementedError('repositoryProvider must be overridden'),
);

final unitProvider = StateProvider<WeightUnit>((ref) => WeightUnit.kg);

// ----------------------------------------------------------------- workouts --

class WorkoutListNotifier extends AsyncNotifier<List<Workout>> {
  @override
  Future<List<Workout>> build() =>
      ref.watch(repositoryProvider).listWorkouts();

  Future<void> refresh() async {
    state = AsyncValue.data(await ref.read(repositoryProvider).listWorkouts());
  }

  Future<Workout> create({required String title, String? description}) async {
    final workout = await ref
        .read(repositoryProvider)
        .createWorkout(title: title, description: description);
    await refresh();
    return workout;
  }

  Future<void> delete(String id) async {
    await ref.read(repositoryProvider).deleteWorkout(id);
    await refresh();
  }

  Future<Workout> import(Workout source, {String? creatorName}) async {
    final copy = await ref
        .read(repositoryProvider)
        .importWorkout(source, creatorName: creatorName);
    await refresh();
    return copy;
  }
}

final workoutListProvider =
    AsyncNotifierProvider<WorkoutListNotifier, List<Workout>>(
      WorkoutListNotifier.new,
    );

/// A single workout with its items. Invalidate this after any edit.
final workoutProvider = FutureProvider.family<Workout?, String>(
  (ref, id) => ref.watch(repositoryProvider).getWorkout(id),
);

/// Coverage for a workout, computed on device so the map renders offline.
final coverageProvider = FutureProvider.family<CoverageReport, String>((
  ref,
  workoutId,
) async {
  final catalog = ref.watch(catalogProvider);
  final workout = await ref.watch(workoutProvider(workoutId).future);

  final items = <CoverageInput>[];
  for (final item in workout?.items ?? const <WorkoutItem>[]) {
    final exercise = catalog.exercise(item.exerciseSlug);
    if (exercise != null) {
      items.add(CoverageInput(exercise: exercise, sets: item.targetSets));
    }
  }

  return CoverageReport.compute(catalog: catalog, items: items);
});

// ----------------------------------------------------------------- sessions --

/// The session left open if the app was killed mid-workout, so the user can
/// pick up where they left off instead of losing the log.
final activeSessionProvider = FutureProvider<WorkoutSession?>(
  (ref) => ref.watch(repositoryProvider).activeSession(),
);

final recentSessionsProvider = FutureProvider<List<WorkoutSession>>(
  (ref) => ref.watch(repositoryProvider).recentSessions(),
);

/// Sets already logged in a session, keyed by `itemId:setNumber`.
final sessionLogsProvider = FutureProvider.family<Map<String, SetLog>, String>((
  ref,
  sessionId,
) async {
  final logs = await ref.watch(repositoryProvider).logsForSession(sessionId);
  return {for (final l in logs) '${l.workoutItemId}:${l.setNumber}': l};
});

/// What the user did last time on an exercise, excluding the session in
/// progress. The inline hint that makes the logger worth opening twice.
final lastPerformanceProvider =
    FutureProvider.family<List<SetLog>, ({String exerciseSlug, String? sessionId})>(
      (ref, args) => ref
          .watch(repositoryProvider)
          .lastPerformance(args.exerciseSlug, excludeSessionId: args.sessionId),
    );

// ----------------------------------------------------------- browse filters --

@immutable
class ExerciseFilter {
  const ExerciseFilter({
    this.query = '',
    this.muscleSlug,
    this.equipment,
    this.primaryOnly = false,
  });

  final String query;
  final String? muscleSlug;
  final Equipment? equipment;
  final bool primaryOnly;

  bool get isEmpty =>
      query.isEmpty && muscleSlug == null && equipment == null && !primaryOnly;

  ExerciseFilter copyWith({
    String? query,
    String? Function()? muscleSlug,
    Equipment? Function()? equipment,
    bool? primaryOnly,
  }) => ExerciseFilter(
    query: query ?? this.query,
    muscleSlug: muscleSlug != null ? muscleSlug() : this.muscleSlug,
    equipment: equipment != null ? equipment() : this.equipment,
    primaryOnly: primaryOnly ?? this.primaryOnly,
  );
}

final exerciseFilterProvider = StateProvider<ExerciseFilter>(
  (ref) => const ExerciseFilter(),
);

final filteredExercisesProvider = Provider<List<Exercise>>((ref) {
  final catalog = ref.watch(catalogProvider);
  final filter = ref.watch(exerciseFilterProvider);

  return catalog.filter(
    query: filter.query,
    muscleSlug: filter.muscleSlug,
    equipment: filter.equipment,
    primaryOnly: filter.primaryOnly,
  );
});
