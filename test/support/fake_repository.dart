import 'package:uuid/uuid.dart';
import 'package:workout_app/data/models/workout.dart';
import 'package:workout_app/data/repository.dart';

/// In-memory [WorkoutRepository] for widget tests.
///
/// `testWidgets` runs inside a fake async zone, where sqflite's real file I/O
/// never completes and every screen would sit on a spinner forever. This keeps
/// widget tests about widgets; the sqflite implementation is covered directly
/// by `repository_test.dart` against the same interface.
class FakeWorkoutRepository implements WorkoutRepository {
  FakeWorkoutRepository({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  final List<Workout> _workouts = [];
  final List<WorkoutItem> _items = [];
  final List<WorkoutSession> _sessions = [];
  final List<SetLog> _logs = [];

  Workout _hydrate(Workout w) => w.copyWith(
    items: _items.where((i) => i.workoutId == w.id).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex)),
  );

  @override
  Future<List<Workout>> listWorkouts() async {
    final sorted = [..._workouts]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.map(_hydrate).toList();
  }

  @override
  Future<Workout?> getWorkout(String id) async {
    final match = _workouts.where((w) => w.id == id).firstOrNull;
    return match == null ? null : _hydrate(match);
  }

  @override
  Future<Workout> createWorkout({
    required String title,
    String? description,
  }) async {
    final workout = Workout(
      id: _uuid.v4(),
      title: title,
      description: description,
      createdAt: DateTime.now(),
    );
    _workouts.add(workout);
    return workout;
  }

  @override
  Future<void> updateWorkoutDetails(
    String id, {
    required String title,
    String? description,
  }) async {
    final index = _workouts.indexWhere((w) => w.id == id);
    if (index == -1) return;
    _workouts[index] = _workouts[index].copyWith(
      title: title,
      description: description,
    );
  }

  @override
  Future<void> deleteWorkout(String id) async {
    _workouts.removeWhere((w) => w.id == id);
    final removed = _items.where((i) => i.workoutId == id).map((i) => i.id).toSet();
    _items.removeWhere((i) => i.workoutId == id);
    final sessions = _sessions.where((s) => s.workoutId == id).map((s) => s.id).toSet();
    _sessions.removeWhere((s) => s.workoutId == id);
    _logs.removeWhere(
      (l) => removed.contains(l.workoutItemId) || sessions.contains(l.sessionId),
    );
  }

  @override
  Future<Workout> importWorkout(Workout source, {String? creatorName}) async {
    final newId = _uuid.v4();
    final copy = Workout(
      id: newId,
      title: source.title,
      description: source.description,
      sourceWorkoutId: source.id,
      sourceCreatorName: creatorName ?? source.sourceCreatorName,
      createdAt: DateTime.now(),
    );

    _workouts.add(copy);
    for (final item in source.items) {
      _items.add(
        WorkoutItem(
          id: _uuid.v4(),
          workoutId: newId,
          exerciseSlug: item.exerciseSlug,
          orderIndex: item.orderIndex,
          targetSets: item.targetSets,
          targetReps: item.targetReps,
          restSeconds: item.restSeconds,
          note: item.note,
        ),
      );
    }

    return _hydrate(copy);
  }

  @override
  Future<WorkoutItem> addItem({
    required String workoutId,
    required String exerciseSlug,
    int targetSets = 3,
    int targetReps = 10,
    int restSeconds = 90,
  }) async {
    final item = WorkoutItem(
      id: _uuid.v4(),
      workoutId: workoutId,
      exerciseSlug: exerciseSlug,
      orderIndex: _items.where((i) => i.workoutId == workoutId).length,
      targetSets: targetSets,
      targetReps: targetReps,
      restSeconds: restSeconds,
    );
    _items.add(item);
    return item;
  }

  @override
  Future<void> updateItem(WorkoutItem item) async {
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index != -1) _items[index] = item;
  }

  @override
  Future<void> swapExercise(String itemId, String newExerciseSlug) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index != -1) {
      _items[index] = _items[index].copyWith(exerciseSlug: newExerciseSlug);
    }
  }

  @override
  Future<void> removeItem(String itemId) async {
    final item = _items.where((i) => i.id == itemId).firstOrNull;
    if (item == null) return;

    _items.removeWhere((i) => i.id == itemId);
    _logs.removeWhere((l) => l.workoutItemId == itemId);
    _renumber(item.workoutId);
  }

  @override
  Future<void> reorderItem(String workoutId, int oldIndex, int newIndex) async {
    final ordered = _items.where((i) => i.workoutId == workoutId).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    if (oldIndex < 0 || oldIndex >= ordered.length) return;

    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex.clamp(0, ordered.length), moved);

    for (var i = 0; i < ordered.length; i++) {
      final index = _items.indexWhere((item) => item.id == ordered[i].id);
      _items[index] = _items[index].copyWith(orderIndex: i);
    }
  }

  void _renumber(String workoutId) {
    final ordered = _items.where((i) => i.workoutId == workoutId).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    for (var i = 0; i < ordered.length; i++) {
      final index = _items.indexWhere((item) => item.id == ordered[i].id);
      _items[index] = _items[index].copyWith(orderIndex: i);
    }
  }

  @override
  Future<WorkoutSession> startSession(String workoutId) async {
    final session = WorkoutSession(
      id: _uuid.v4(),
      workoutId: workoutId,
      startedAt: DateTime.now(),
    );
    _sessions.add(session);
    return session;
  }

  @override
  Future<WorkoutSession?> activeSession() async {
    final open = _sessions.where((s) => s.isActive).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return open.firstOrNull;
  }

  @override
  Future<void> finishSession(String sessionId, {String? note}) async {
    final index = _sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;
    final s = _sessions[index];
    _sessions[index] = WorkoutSession(
      id: s.id,
      workoutId: s.workoutId,
      startedAt: s.startedAt,
      finishedAt: DateTime.now(),
      note: note,
    );
  }

  @override
  Future<void> abandonSession(String sessionId) async {
    _sessions.removeWhere((s) => s.id == sessionId);
    _logs.removeWhere((l) => l.sessionId == sessionId);
  }

  @override
  Future<List<WorkoutSession>> recentSessions({int limit = 30}) async {
    final done = _sessions.where((s) => !s.isActive).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return done.take(limit).toList();
  }

  @override
  Future<SetLog> logSet({
    required String sessionId,
    required String workoutItemId,
    required int setNumber,
    double? weightKg,
    int? repsDone,
  }) async {
    _logs.removeWhere(
      (l) =>
          l.sessionId == sessionId &&
          l.workoutItemId == workoutItemId &&
          l.setNumber == setNumber,
    );

    final log = SetLog(
      id: _uuid.v4(),
      sessionId: sessionId,
      workoutItemId: workoutItemId,
      setNumber: setNumber,
      weightKg: weightKg,
      repsDone: repsDone,
      completedAt: DateTime.now(),
    );
    _logs.add(log);
    return log;
  }

  @override
  Future<void> deleteSetLog({
    required String sessionId,
    required String workoutItemId,
    required int setNumber,
  }) async {
    _logs.removeWhere(
      (l) =>
          l.sessionId == sessionId &&
          l.workoutItemId == workoutItemId &&
          l.setNumber == setNumber,
    );
  }

  @override
  Future<List<SetLog>> logsForSession(String sessionId) async {
    return _logs.where((l) => l.sessionId == sessionId).toList()
      ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
  }

  @override
  Future<List<SetLog>> lastPerformance(
    String exerciseSlug, {
    String? excludeSessionId,
  }) async {
    final itemIds = _items
        .where((i) => i.exerciseSlug == exerciseSlug)
        .map((i) => i.id)
        .toSet();

    final candidates = _logs
        .where(
          (l) =>
              itemIds.contains(l.workoutItemId) &&
              l.sessionId != excludeSessionId,
        )
        .toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

    if (candidates.isEmpty) return [];

    final sessionId = candidates.first.sessionId;
    return candidates.where((l) => l.sessionId == sessionId).toList()
      ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
  }

  @override
  Future<SetLog?> personalRecord(String exerciseSlug) async {
    final itemIds = _items
        .where((i) => i.exerciseSlug == exerciseSlug)
        .map((i) => i.id)
        .toSet();

    final withWeight = _logs
        .where((l) => itemIds.contains(l.workoutItemId) && l.weightKg != null)
        .toList()
      ..sort((a, b) => b.weightKg!.compareTo(a.weightKg!));

    return withWeight.firstOrNull;
  }
}
