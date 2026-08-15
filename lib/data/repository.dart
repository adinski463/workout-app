import 'models/workout.dart';

/// Everything the app needs from storage.
///
/// The UI depends on this interface, never on sqflite directly. Two payoffs:
/// widget tests run against a fast in-memory implementation, and the eventual
/// Supabase-backed sync layer can be introduced without touching a screen.
abstract class WorkoutRepository {
  // ------------------------------------------------------------- workouts --

  Future<List<Workout>> listWorkouts();

  Future<Workout?> getWorkout(String id);

  Future<Workout> createWorkout({required String title, String? description});

  Future<void> updateWorkoutDetails(
    String id, {
    required String title,
    String? description,
  });

  Future<void> deleteWorkout(String id);

  /// Copies a workout, mirroring the server-side `import_workout`. The copy is
  /// independent: later edits to the source never reach it.
  Future<Workout> importWorkout(Workout source, {String? creatorName});

  // ---------------------------------------------------------------- items --

  Future<WorkoutItem> addItem({
    required String workoutId,
    required String exerciseSlug,
    int targetSets,
    int targetReps,
    int restSeconds,
  });

  Future<void> updateItem(WorkoutItem item);

  /// Replaces the exercise in one item, leaving sets/reps/rest alone.
  Future<void> swapExercise(String itemId, String newExerciseSlug);

  Future<void> removeItem(String itemId);

  Future<void> reorderItem(String workoutId, int oldIndex, int newIndex);

  // ------------------------------------------------------------- sessions --

  Future<WorkoutSession> startSession(String workoutId);

  /// The session left open if the app was closed mid-workout.
  Future<WorkoutSession?> activeSession();

  Future<void> finishSession(String sessionId, {String? note});

  Future<void> abandonSession(String sessionId);

  Future<List<WorkoutSession>> recentSessions({int limit});

  // ----------------------------------------------------------- set logging --

  Future<SetLog> logSet({
    required String sessionId,
    required String workoutItemId,
    required int setNumber,
    double? weightKg,
    int? repsDone,
  });

  Future<void> deleteSetLog({
    required String sessionId,
    required String workoutItemId,
    required int setNumber,
  });

  Future<List<SetLog>> logsForSession(String sessionId);

  /// What was done last time on an exercise, excluding [excludeSessionId].
  ///
  /// Keyed on the exercise rather than the workout item so history follows the
  /// movement across workouts and across imported copies.
  Future<List<SetLog>> lastPerformance(
    String exerciseSlug, {
    String? excludeSessionId,
  });

  Future<SetLog?> personalRecord(String exerciseSlug);
}
