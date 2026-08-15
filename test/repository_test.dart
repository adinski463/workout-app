import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_app/data/local/database.dart';
import 'package:workout_app/data/local/workout_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase db;
  late LocalWorkoutRepository repo;

  setUp(() async {
    db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repo = LocalWorkoutRepository(db);
  });

  tearDown(() => db.close());

  group('workouts', () {
    test('create, read back, and delete', () async {
      final created = await repo.createWorkout(
        title: 'Push Day',
        description: 'Chest and triceps',
      );

      final fetched = await repo.getWorkout(created.id);
      expect(fetched, isNotNull);
      expect(fetched!.title, 'Push Day');
      expect(fetched.description, 'Chest and triceps');
      expect(fetched.isPublished, isFalse);
      expect(fetched.items, isEmpty);

      await repo.deleteWorkout(created.id);
      expect(await repo.getWorkout(created.id), isNull);
    });

    test('items come back in order and renumber after removal', () async {
      final w = await repo.createWorkout(title: 'Pull Day');
      await repo.addItem(workoutId: w.id, exerciseSlug: 'pull-up');
      final second = await repo.addItem(
        workoutId: w.id,
        exerciseSlug: 'barbell-row',
      );
      await repo.addItem(workoutId: w.id, exerciseSlug: 'barbell-curl');

      var items = (await repo.getWorkout(w.id))!.items;
      expect(items.map((i) => i.exerciseSlug), [
        'pull-up',
        'barbell-row',
        'barbell-curl',
      ]);
      expect(items.map((i) => i.orderIndex), [0, 1, 2]);

      await repo.removeItem(second.id);

      items = (await repo.getWorkout(w.id))!.items;
      expect(items.map((i) => i.exerciseSlug), ['pull-up', 'barbell-curl']);
      // Gaps in order_index would break drag-to-reorder later.
      expect(items.map((i) => i.orderIndex), [0, 1]);
    });

    test('reorder moves an item and renumbers the rest', () async {
      final w = await repo.createWorkout(title: 'Leg Day');
      for (final slug in ['back-squat', 'leg-press', 'leg-extension']) {
        await repo.addItem(workoutId: w.id, exerciseSlug: slug);
      }

      await repo.reorderItem(w.id, 2, 0);

      final items = (await repo.getWorkout(w.id))!.items;
      expect(items.map((i) => i.exerciseSlug), [
        'leg-extension',
        'back-squat',
        'leg-press',
      ]);
      expect(items.map((i) => i.orderIndex), [0, 1, 2]);
    });

    test('deleting a workout cascades to its items', () async {
      final w = await repo.createWorkout(title: 'Temp');
      await repo.addItem(workoutId: w.id, exerciseSlug: 'plank');

      await repo.deleteWorkout(w.id);

      final rows = await db.db.query('workout_items');
      expect(rows, isEmpty);
    });
  });

  group('import and swap', () {
    test('import copies items and records the source', () async {
      final source = await repo.createWorkout(title: 'Creator Push Day');
      await repo.addItem(
        workoutId: source.id,
        exerciseSlug: 'barbell-bench-press',
        targetSets: 4,
        targetReps: 6,
      );
      await repo.addItem(workoutId: source.id, exerciseSlug: 'face-pull');
      final full = (await repo.getWorkout(source.id))!;

      final copy = await repo.importWorkout(full, creatorName: 'creator');

      expect(copy.id, isNot(source.id));
      expect(copy.sourceWorkoutId, source.id);
      expect(copy.sourceCreatorName, 'creator');
      expect(copy.isImported, isTrue);
      expect(copy.items.length, 2);
      // Set/rep prescription must survive the copy.
      expect(copy.items.first.targetSets, 4);
      expect(copy.items.first.targetReps, 6);
    });

    test('swapping in the copy leaves the original untouched', () async {
      final source = await repo.createWorkout(title: 'Original');
      await repo.addItem(
        workoutId: source.id,
        exerciseSlug: 'barbell-bench-press',
      );
      final full = (await repo.getWorkout(source.id))!;
      final copy = await repo.importWorkout(full);

      await repo.swapExercise(copy.items.first.id, 'dumbbell-bench-press');

      final updatedCopy = (await repo.getWorkout(copy.id))!;
      final untouched = (await repo.getWorkout(source.id))!;

      expect(updatedCopy.items.first.exerciseSlug, 'dumbbell-bench-press');
      expect(untouched.items.first.exerciseSlug, 'barbell-bench-press');
    });

    test('editing the original after import does not reach the copy', () async {
      final source = await repo.createWorkout(title: 'Original');
      await repo.addItem(workoutId: source.id, exerciseSlug: 'back-squat');
      final copy = await repo.importWorkout((await repo.getWorkout(source.id))!);

      await repo.updateWorkoutDetails(source.id, title: 'Renamed');
      await repo.removeItem((await repo.getWorkout(source.id))!.items.first.id);

      final stillThere = (await repo.getWorkout(copy.id))!;
      expect(stillThere.title, 'Original');
      expect(stillThere.items, hasLength(1));
    });
  });

  group('sessions and logging', () {
    test('a session can be started, logged to, and finished', () async {
      final w = await repo.createWorkout(title: 'Chest');
      final item = await repo.addItem(
        workoutId: w.id,
        exerciseSlug: 'barbell-bench-press',
        targetSets: 3,
      );

      final session = await repo.startSession(w.id);
      expect(session.isActive, isTrue);
      expect(await repo.activeSession(), isNotNull);

      await repo.logSet(
        sessionId: session.id,
        workoutItemId: item.id,
        setNumber: 1,
        weightKg: 80,
        repsDone: 8,
      );
      await repo.logSet(
        sessionId: session.id,
        workoutItemId: item.id,
        setNumber: 2,
        weightKg: 80,
        repsDone: 7,
      );

      final logs = await repo.logsForSession(session.id);
      expect(logs, hasLength(2));
      expect(logs.first.weightKg, 80);

      await repo.finishSession(session.id);
      expect(await repo.activeSession(), isNull);
      expect(await repo.recentSessions(), hasLength(1));
    });

    test('re-logging the same set corrects it instead of duplicating', () async {
      final w = await repo.createWorkout(title: 'Chest');
      final item = await repo.addItem(
        workoutId: w.id,
        exerciseSlug: 'barbell-bench-press',
      );
      final session = await repo.startSession(w.id);

      await repo.logSet(
        sessionId: session.id,
        workoutItemId: item.id,
        setNumber: 1,
        weightKg: 80,
        repsDone: 8,
      );
      await repo.logSet(
        sessionId: session.id,
        workoutItemId: item.id,
        setNumber: 1,
        weightKg: 82.5,
        repsDone: 6,
      );

      final logs = await repo.logsForSession(session.id);
      expect(logs, hasLength(1));
      expect(logs.single.weightKg, 82.5);
      expect(logs.single.repsDone, 6);
    });

    test('abandoning a session removes its logs', () async {
      final w = await repo.createWorkout(title: 'Chest');
      final item = await repo.addItem(
        workoutId: w.id,
        exerciseSlug: 'push-up',
      );
      final session = await repo.startSession(w.id);
      await repo.logSet(
        sessionId: session.id,
        workoutItemId: item.id,
        setNumber: 1,
        repsDone: 20,
      );

      await repo.abandonSession(session.id);

      expect(await repo.activeSession(), isNull);
      expect(await db.db.query('set_logs'), isEmpty);
    });
  });

  group('last performance', () {
    test('returns the previous session, not the current one', () async {
      final w = await repo.createWorkout(title: 'Chest');
      final item = await repo.addItem(
        workoutId: w.id,
        exerciseSlug: 'barbell-bench-press',
      );

      final first = await repo.startSession(w.id);
      await repo.logSet(
        sessionId: first.id,
        workoutItemId: item.id,
        setNumber: 1,
        weightKg: 80,
        repsDone: 8,
      );
      await repo.finishSession(first.id);

      final second = await repo.startSession(w.id);
      await repo.logSet(
        sessionId: second.id,
        workoutItemId: item.id,
        setNumber: 1,
        weightKg: 85,
        repsDone: 6,
      );

      // Mid-workout, "last time" must show 80x8 — not the 85 just entered.
      final last = await repo.lastPerformance(
        'barbell-bench-press',
        excludeSessionId: second.id,
      );
      expect(last, hasLength(1));
      expect(last.single.weightKg, 80);
      expect(last.single.repsDone, 8);
    });

    test('follows the exercise across different workouts', () async {
      // The point of keying on exercise rather than workout item: benching in
      // an imported workout still shows what you benched in your own routine.
      final own = await repo.createWorkout(title: 'My Push Day');
      final ownItem = await repo.addItem(
        workoutId: own.id,
        exerciseSlug: 'barbell-bench-press',
      );
      final s1 = await repo.startSession(own.id);
      await repo.logSet(
        sessionId: s1.id,
        workoutItemId: ownItem.id,
        setNumber: 1,
        weightKg: 100,
        repsDone: 5,
      );
      await repo.finishSession(s1.id);

      final imported = await repo.createWorkout(title: "Someone else's day");
      await repo.addItem(
        workoutId: imported.id,
        exerciseSlug: 'barbell-bench-press',
      );
      final s2 = await repo.startSession(imported.id);

      final last = await repo.lastPerformance(
        'barbell-bench-press',
        excludeSessionId: s2.id,
      );
      expect(last.single.weightKg, 100);
    });

    test('returns every set from that session, in order', () async {
      final w = await repo.createWorkout(title: 'Chest');
      final item = await repo.addItem(
        workoutId: w.id,
        exerciseSlug: 'barbell-bench-press',
      );

      final s = await repo.startSession(w.id);
      for (final (n, reps) in [(1, 8), (2, 7), (3, 6)]) {
        await repo.logSet(
          sessionId: s.id,
          workoutItemId: item.id,
          setNumber: n,
          weightKg: 80,
          repsDone: reps,
        );
      }
      await repo.finishSession(s.id);

      final last = await repo.lastPerformance('barbell-bench-press');
      expect(last.map((l) => l.setNumber), [1, 2, 3]);
      expect(last.map((l) => l.repsDone), [8, 7, 6]);
    });

    test('is empty for an exercise never performed', () async {
      expect(await repo.lastPerformance('dragon-flag'), isEmpty);
    });

    test('personal record finds the heaviest set ever', () async {
      final w = await repo.createWorkout(title: 'Chest');
      final item = await repo.addItem(
        workoutId: w.id,
        exerciseSlug: 'barbell-bench-press',
      );

      for (final (session, weight) in [(1, 80.0), (2, 95.0), (3, 90.0)]) {
        final s = await repo.startSession(w.id);
        await repo.logSet(
          sessionId: s.id,
          workoutItemId: item.id,
          setNumber: session,
          weightKg: weight,
          repsDone: 5,
        );
        await repo.finishSession(s.id);
      }

      final pr = await repo.personalRecord('barbell-bench-press');
      expect(pr!.weightKg, 95.0);
    });
  });
}
