import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/workout.dart';
import '../repository.dart';
import 'database.dart';

/// All reads and writes the app performs while training.
///
/// Every method here is local and synchronous-ish by design — see the note in
/// [AppDatabase]. Nothing in the logging path awaits the network.
class LocalWorkoutRepository implements WorkoutRepository {
  LocalWorkoutRepository(this._app, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _app;
  final Uuid _uuid;

  Database get _db => _app.db;

  // ------------------------------------------------------------- workouts --

  @override
  Future<List<Workout>> listWorkouts() async {
    final rows = await _db.query('workouts', orderBy: 'created_at DESC');
    return Future.wait(rows.map((r) async {
      final items = await _itemsFor(r['id'] as String);
      return Workout.fromRow(r, items: items);
    }));
  }

  @override
  Future<Workout?> getWorkout(String id) async {
    final rows = await _db.query('workouts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Workout.fromRow(rows.first, items: await _itemsFor(id));
  }

  Future<List<WorkoutItem>> _itemsFor(String workoutId) async {
    final rows = await _db.query(
      'workout_items',
      where: 'workout_id = ?',
      whereArgs: [workoutId],
      orderBy: 'order_index ASC',
    );
    return rows.map(WorkoutItem.fromRow).toList();
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
    await _db.insert('workouts', workout.toRow());
    return workout;
  }

  @override
  Future<void> updateWorkoutDetails(
    String id, {
    required String title,
    String? description,
  }) async {
    await _db.update(
      'workouts',
      {'title': title, 'description': description},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteWorkout(String id) async {
    await _db.delete('workouts', where: 'id = ?', whereArgs: [id]);
  }

  /// Copies a workout, the same way the server-side `import_workout` does.
  ///
  /// Used both for "use this workout" and for duplicating your own. The copy is
  /// independent: later edits to the source never reach it.
  @override
  Future<Workout> importWorkout(
    Workout source, {
    String? creatorName,
  }) async {
    final newId = _uuid.v4();

    final copy = Workout(
      id: newId,
      title: source.title,
      description: source.description,
      sourceWorkoutId: source.id,
      sourceCreatorName: creatorName ?? source.sourceCreatorName,
      createdAt: DateTime.now(),
      items: [
        for (final item in source.items)
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
      ],
    );

    await _db.transaction((txn) async {
      await txn.insert('workouts', copy.toRow());
      for (final item in copy.items) {
        await txn.insert('workout_items', item.toRow());
      }
    });

    return copy;
  }

  // ---------------------------------------------------------------- items --

  @override
  Future<WorkoutItem> addItem({
    required String workoutId,
    required String exerciseSlug,
    int targetSets = 3,
    int targetReps = 10,
    int restSeconds = 90,
  }) async {
    final existing = await _itemsFor(workoutId);
    final item = WorkoutItem(
      id: _uuid.v4(),
      workoutId: workoutId,
      exerciseSlug: exerciseSlug,
      orderIndex: existing.length,
      targetSets: targetSets,
      targetReps: targetReps,
      restSeconds: restSeconds,
    );
    await _db.insert('workout_items', item.toRow());
    return item;
  }

  @override
  Future<void> updateItem(WorkoutItem item) async {
    await _db.update(
      'workout_items',
      item.toRow(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  /// Swaps the exercise in a single item, leaving sets/reps/rest alone.
  ///
  /// Because imported workouts are copies, this only ever touches the user's
  /// own version — the creator's original is untouched.
  @override
  Future<void> swapExercise(String itemId, String newExerciseSlug) async {
    await _db.update(
      'workout_items',
      {'exercise_slug': newExerciseSlug},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  @override
  Future<void> removeItem(String itemId) async {
    final rows = await _db.query(
      'workout_items',
      columns: ['workout_id'],
      where: 'id = ?',
      whereArgs: [itemId],
    );
    if (rows.isEmpty) return;
    final workoutId = rows.first['workout_id'] as String;

    await _db.transaction((txn) async {
      await txn.delete('workout_items', where: 'id = ?', whereArgs: [itemId]);
      await _renumber(txn, workoutId);
    });
  }

  /// Moves an item to a new position, renumbering the rest.
  @override
  Future<void> reorderItem(
    String workoutId,
    int oldIndex,
    int newIndex,
  ) async {
    final items = await _itemsFor(workoutId);
    if (oldIndex < 0 || oldIndex >= items.length) return;

    final moved = items.removeAt(oldIndex);
    items.insert(newIndex.clamp(0, items.length), moved);

    await _db.transaction((txn) async {
      for (var i = 0; i < items.length; i++) {
        await txn.update(
          'workout_items',
          {'order_index': i},
          where: 'id = ?',
          whereArgs: [items[i].id],
        );
      }
    });
  }

  Future<void> _renumber(DatabaseExecutor txn, String workoutId) async {
    final rows = await txn.query(
      'workout_items',
      where: 'workout_id = ?',
      whereArgs: [workoutId],
      orderBy: 'order_index ASC',
    );
    for (var i = 0; i < rows.length; i++) {
      await txn.update(
        'workout_items',
        {'order_index': i},
        where: 'id = ?',
        whereArgs: [rows[i]['id']],
      );
    }
  }

  // ------------------------------------------------------------- sessions --

  @override
  Future<WorkoutSession> startSession(String workoutId) async {
    final session = WorkoutSession(
      id: _uuid.v4(),
      workoutId: workoutId,
      startedAt: DateTime.now(),
    );
    await _db.insert('workout_sessions', session.toRow());
    return session;
  }

  /// The session left open, if the app was closed mid-workout.
  @override
  Future<WorkoutSession?> activeSession() async {
    final rows = await _db.query(
      'workout_sessions',
      where: 'finished_at IS NULL',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : WorkoutSession.fromRow(rows.first);
  }

  @override
  Future<void> finishSession(String sessionId, {String? note}) async {
    await _db.update(
      'workout_sessions',
      {'finished_at': DateTime.now().millisecondsSinceEpoch, 'note': note},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Discards a session and its logs — used when the user starts a workout by
  /// accident and backs straight out.
  @override
  Future<void> abandonSession(String sessionId) async {
    await _db.delete(
      'workout_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  @override
  Future<List<WorkoutSession>> recentSessions({int limit = 30}) async {
    final rows = await _db.query(
      'workout_sessions',
      where: 'finished_at IS NOT NULL',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(WorkoutSession.fromRow).toList();
  }

  // ----------------------------------------------------------- set logging --

  /// Records one set. Re-logging the same set number overwrites it, so tapping
  /// a set twice corrects it rather than creating a duplicate.
  @override
  Future<SetLog> logSet({
    required String sessionId,
    required String workoutItemId,
    required int setNumber,
    double? weightKg,
    int? repsDone,
  }) async {
    final log = SetLog(
      id: _uuid.v4(),
      sessionId: sessionId,
      workoutItemId: workoutItemId,
      setNumber: setNumber,
      weightKg: weightKg,
      repsDone: repsDone,
      completedAt: DateTime.now(),
    );

    await _db.insert(
      'set_logs',
      log.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return log;
  }

  @override
  Future<void> deleteSetLog({
    required String sessionId,
    required String workoutItemId,
    required int setNumber,
  }) async {
    await _db.delete(
      'set_logs',
      where: 'session_id = ? AND workout_item_id = ? AND set_number = ?',
      whereArgs: [sessionId, workoutItemId, setNumber],
    );
  }

  @override
  Future<List<SetLog>> logsForSession(String sessionId) async {
    final rows = await _db.query(
      'set_logs',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'set_number ASC',
    );
    return rows.map(SetLog.fromRow).toList();
  }

  /// What you did last time on this exercise — the numbers shown inline while
  /// logging.
  ///
  /// Keyed on the *exercise*, not the workout item, so history follows the
  /// movement across different workouts and across imported copies. Bench press
  /// in a workout you imported yesterday still shows what you benched last
  /// month in your own routine.
  @override
  Future<List<SetLog>> lastPerformance(
    String exerciseSlug, {
    String? excludeSessionId,
  }) async {
    final rows = await _db.rawQuery(
      '''
      SELECT l.* FROM set_logs l
        JOIN workout_items i ON i.id = l.workout_item_id
       WHERE i.exercise_slug = ?
         AND l.session_id <> COALESCE(?, '')
         AND l.session_id = (
           SELECT l2.session_id FROM set_logs l2
             JOIN workout_items i2 ON i2.id = l2.workout_item_id
            WHERE i2.exercise_slug = ?
              AND l2.session_id <> COALESCE(?, '')
            ORDER BY l2.completed_at DESC
            LIMIT 1
         )
       ORDER BY l.set_number ASC
      ''',
      [exerciseSlug, excludeSessionId, exerciseSlug, excludeSessionId],
    );
    return rows.map(SetLog.fromRow).toList();
  }

  /// Heaviest set ever recorded for an exercise, for the personal-record badge.
  @override
  Future<SetLog?> personalRecord(String exerciseSlug) async {
    final rows = await _db.rawQuery(
      '''
      SELECT l.* FROM set_logs l
        JOIN workout_items i ON i.id = l.workout_item_id
       WHERE i.exercise_slug = ? AND l.weight_kg IS NOT NULL
       ORDER BY l.weight_kg DESC, l.reps_done DESC
       LIMIT 1
      ''',
      [exerciseSlug],
    );
    return rows.isEmpty ? null : SetLog.fromRow(rows.first);
  }
}
