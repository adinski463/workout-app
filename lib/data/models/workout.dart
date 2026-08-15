import 'package:flutter/foundation.dart';

/// A workout, whether private, published, or imported from someone else.
///
/// One type covers all three cases (see docs/01-plan-review.md, Change 4d):
/// importing copies the rows and records [sourceWorkoutId], so a creator
/// editing their original can never mutate your copy or break your history.
@immutable
class Workout {
  const Workout({
    required this.id,
    required this.title,
    required this.createdAt,
    this.description,
    this.isPublished = false,
    this.sourceWorkoutId,
    this.sourceCreatorName,
    this.items = const [],
  });

  final String id;
  final String title;
  final String? description;
  final bool isPublished;
  final String? sourceWorkoutId;

  /// Kept for attribution on imported workouts: "from @someone".
  final String? sourceCreatorName;

  final DateTime createdAt;
  final List<WorkoutItem> items;

  bool get isImported => sourceWorkoutId != null;

  int get totalSets => items.fold(0, (sum, i) => sum + i.targetSets);

  /// Rough wall-clock estimate: working time plus rest. Matches the SQL
  /// estimate so the feed and the local list agree.
  int get estimatedMinutes {
    if (items.isEmpty) return 0;
    final seconds = items.fold<int>(
      0,
      (sum, i) => sum + i.targetSets * (i.restSeconds + i.targetReps * 4),
    );
    return (seconds / 60).ceil();
  }

  Workout copyWith({
    String? title,
    String? description,
    bool? isPublished,
    List<WorkoutItem>? items,
  }) => Workout(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    isPublished: isPublished ?? this.isPublished,
    sourceWorkoutId: sourceWorkoutId,
    sourceCreatorName: sourceCreatorName,
    createdAt: createdAt,
    items: items ?? this.items,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'title': title,
    'description': description,
    'is_published': isPublished ? 1 : 0,
    'source_workout_id': sourceWorkoutId,
    'source_creator_name': sourceCreatorName,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory Workout.fromRow(
    Map<String, Object?> row, {
    List<WorkoutItem> items = const [],
  }) => Workout(
    id: row['id'] as String,
    title: row['title'] as String,
    description: row['description'] as String?,
    isPublished: (row['is_published'] as int? ?? 0) == 1,
    sourceWorkoutId: row['source_workout_id'] as String?,
    sourceCreatorName: row['source_creator_name'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    items: items,
  );
}

/// One exercise slot in a workout.
///
/// Holds the exercise *slug*, not a copy of the exercise, so a swap is a single
/// field update and the catalog stays the single source of truth.
@immutable
class WorkoutItem {
  const WorkoutItem({
    required this.id,
    required this.workoutId,
    required this.exerciseSlug,
    required this.orderIndex,
    this.targetSets = 3,
    this.targetReps = 10,
    this.restSeconds = 90,
    this.note,
  });

  final String id;
  final String workoutId;
  final String exerciseSlug;
  final int orderIndex;
  final int targetSets;
  final int targetReps;
  final int restSeconds;
  final String? note;

  WorkoutItem copyWith({
    String? exerciseSlug,
    int? orderIndex,
    int? targetSets,
    int? targetReps,
    int? restSeconds,
    String? note,
  }) => WorkoutItem(
    id: id,
    workoutId: workoutId,
    exerciseSlug: exerciseSlug ?? this.exerciseSlug,
    orderIndex: orderIndex ?? this.orderIndex,
    targetSets: targetSets ?? this.targetSets,
    targetReps: targetReps ?? this.targetReps,
    restSeconds: restSeconds ?? this.restSeconds,
    note: note ?? this.note,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'workout_id': workoutId,
    'exercise_slug': exerciseSlug,
    'order_index': orderIndex,
    'target_sets': targetSets,
    'target_reps': targetReps,
    'rest_seconds': restSeconds,
    'note': note,
  };

  factory WorkoutItem.fromRow(Map<String, Object?> row) => WorkoutItem(
    id: row['id'] as String,
    workoutId: row['workout_id'] as String,
    exerciseSlug: row['exercise_slug'] as String,
    orderIndex: row['order_index'] as int,
    targetSets: row['target_sets'] as int,
    targetReps: row['target_reps'] as int,
    restSeconds: row['rest_seconds'] as int,
    note: row['note'] as String?,
  );
}

/// One visit to the gym.
@immutable
class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.workoutId,
    required this.startedAt,
    this.finishedAt,
    this.note,
  });

  final String id;
  final String workoutId;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? note;

  bool get isActive => finishedAt == null;

  Duration get duration =>
      (finishedAt ?? DateTime.now()).difference(startedAt);

  Map<String, Object?> toRow() => {
    'id': id,
    'workout_id': workoutId,
    'started_at': startedAt.millisecondsSinceEpoch,
    'finished_at': finishedAt?.millisecondsSinceEpoch,
    'note': note,
  };

  factory WorkoutSession.fromRow(Map<String, Object?> row) => WorkoutSession(
    id: row['id'] as String,
    workoutId: row['workout_id'] as String,
    startedAt: DateTime.fromMillisecondsSinceEpoch(row['started_at'] as int),
    finishedAt: row['finished_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['finished_at'] as int),
    note: row['note'] as String?,
  );
}

/// A single completed set.
///
/// Weight is always kilograms. Display conversion happens at the edge from the
/// user's unit preference — a mixed-unit column is miserable to migrate later.
@immutable
class SetLog {
  const SetLog({
    required this.id,
    required this.sessionId,
    required this.workoutItemId,
    required this.setNumber,
    required this.completedAt,
    this.weightKg,
    this.repsDone,
  });

  final String id;
  final String sessionId;
  final String workoutItemId;
  final int setNumber;
  final double? weightKg;
  final int? repsDone;
  final DateTime completedAt;

  Map<String, Object?> toRow() => {
    'id': id,
    'session_id': sessionId,
    'workout_item_id': workoutItemId,
    'set_number': setNumber,
    'weight_kg': weightKg,
    'reps_done': repsDone,
    'completed_at': completedAt.millisecondsSinceEpoch,
  };

  factory SetLog.fromRow(Map<String, Object?> row) => SetLog(
    id: row['id'] as String,
    sessionId: row['session_id'] as String,
    workoutItemId: row['workout_item_id'] as String,
    setNumber: row['set_number'] as int,
    weightKg: (row['weight_kg'] as num?)?.toDouble(),
    repsDone: row['reps_done'] as int?,
    completedAt: DateTime.fromMillisecondsSinceEpoch(
      row['completed_at'] as int,
    ),
  );
}
