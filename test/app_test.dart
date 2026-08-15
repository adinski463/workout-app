import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_app/app.dart';
import 'package:workout_app/data/catalog/catalog_loader.dart';
import 'package:workout_app/data/catalog/catalog_models.dart';
import 'package:workout_app/features/coverage/body_map.dart';
import 'package:workout_app/providers.dart';

import 'support/fake_repository.dart';

/// Boots the real app against an in-memory repository, so these exercise the
/// same widgets, providers and navigation the phone runs.
void main() {
  late Catalog catalog;

  setUpAll(() {
    catalog = CatalogLoader.parse(
      musclesRaw: File('assets/catalog/muscles.json').readAsStringSync(),
      exercisesRaw: File('assets/catalog/exercises.json').readAsStringSync(),
    );
  });

  late FakeWorkoutRepository repo;

  setUp(() => repo = FakeWorkoutRepository());

  Future<void> pumpApp(WidgetTester tester) async {
    // The default 800x600 test surface is shorter than any phone, which pushes
    // list content out of the tree and makes finders miss widgets that render
    // fine in reality. Use a tall portrait surface instead.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProvider.overrideWithValue(catalog),
          repositoryProvider.overrideWithValue(repo),
        ],
        child: const WorkoutApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('starts on an empty workout list', (tester) async {
    await pumpApp(tester);

    expect(find.text('My workouts'), findsOneWidget);
    expect(find.text('No workouts yet'), findsOneWidget);
    expect(find.text('Build your first workout'), findsOneWidget);
  });

  testWidgets('a workout can be created from the empty state', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Build your first workout'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Push Day');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // Lands on the new workout, ready to add exercises.
    expect(find.text('Push Day'), findsWidgets);
    expect(find.text('Add your first exercise'), findsOneWidget);

    expect(await repo.listWorkouts(), hasLength(1));
  });

  testWidgets('the exercise library is browsable and filterable', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Exercises'));
    await tester.pumpAndSettle();

    expect(find.text('Barbell Bench Press'), findsOneWidget);

    // Filtering to legs must drop the chest exercises.
    await tester.tap(find.widgetWithText(FilterChip, 'Legs'));
    await tester.pumpAndSettle();

    expect(find.text('Barbell Bench Press'), findsNothing);
    expect(find.text('Back Squat'), findsOneWidget);

    // The sub-muscle row appears once a group is chosen — the layer that makes
    // this app different from every other exercise browser. (The row scrolls
    // horizontally, so assert on its first entry rather than a later one.)
    expect(find.widgetWithText(FilterChip, 'Rectus Femoris'), findsOneWidget);

    // Narrowing to a single sub-muscle drops leg work that does not train it.
    await tester.tap(find.widgetWithText(FilterChip, 'Rectus Femoris'));
    await tester.pumpAndSettle();

    expect(find.text('Leg Extension'), findsOneWidget);
    expect(find.text('Adductor Machine'), findsNothing);
  });

  testWidgets('search narrows the library', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Exercises'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'face pull');
    await tester.pumpAndSettle();

    expect(find.text('Face Pull'), findsOneWidget);
    expect(find.text('Back Squat'), findsNothing);
  });

  testWidgets('exercise detail shows sub-muscle tags', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Exercises'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'face pull');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Face Pull'));
    await tester.pumpAndSettle();

    expect(find.text('Muscles worked'), findsOneWidget);
    // Face pull is primarily a rear delt movement.
    expect(find.text('Rear Delts'), findsWidgets);
    expect(find.text('Trains the same thing'), findsOneWidget);
  });

  testWidgets('a workout with exercises renders the coverage map', (
    tester,
  ) async {
    final workout = await repo.createWorkout(title: 'Shoulder Day');
    await repo.addItem(
      workoutId: workout.id,
      exerciseSlug: 'overhead-press',
      targetSets: 4,
    );
    await repo.addItem(
      workoutId: workout.id,
      exerciseSlug: 'dumbbell-lateral-raise',
      targetSets: 4,
    );

    await pumpApp(tester);
    await tester.tap(find.text('Shoulder Day'));
    await tester.pumpAndSettle();

    expect(find.text('Muscle coverage'), findsOneWidget);

    await tester.scrollUntilVisible(find.byType(BodyMap), 200);
    await tester.pumpAndSettle();
    expect(find.byType(BodyMap), findsOneWidget);

    // The gap callout is the payoff: this workout never trains rear delts.
    await tester.scrollUntilVisible(
      find.textContaining('skips Rear Delts'),
      200,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('skips Rear Delts'), findsOneWidget);
  });

  testWidgets('logging a set records it and starts the rest timer', (
    tester,
  ) async {
    final workout = await repo.createWorkout(title: 'Chest Day');
    await repo.addItem(
      workoutId: workout.id,
      exerciseSlug: 'barbell-bench-press',
      targetSets: 2,
    );

    await pumpApp(tester);
    await tester.tap(find.text('Chest Day'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();

    expect(find.text('Barbell Bench Press'), findsOneWidget);

    // Enter 80 x 8 on the first set and tick it off.
    final weightFields = find.widgetWithText(TextField, 'kg');
    await tester.enterText(weightFields.first, '80');
    await tester.enterText(find.widgetWithText(TextField, 'reps').first, '8');
    await tester.tap(find.byTooltip('Log set').first);
    // Not pumpAndSettle: the rest countdown schedules frames continuously, so
    // "settled" never arrives while it runs.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final session = await repo.activeSession();
    final logs = await repo.logsForSession(session!.id);
    expect(logs, hasLength(1));
    expect(logs.single.weightKg, 80);
    expect(logs.single.repsDone, 8);

    // Completing a set starts the rest countdown automatically.
    expect(find.textContaining('Rest'), findsOneWidget);

    // Stop the timer so no periodic callback outlives the test.
    await tester.tap(find.text('Skip'));
    await tester.pump();
  });

  testWidgets('last session numbers appear on the next workout', (
    tester,
  ) async {
    final workout = await repo.createWorkout(title: 'Chest Day');
    final item = await repo.addItem(
      workoutId: workout.id,
      exerciseSlug: 'barbell-bench-press',
      targetSets: 1,
    );

    // A completed session from "last week".
    final previous = await repo.startSession(workout.id);
    await repo.logSet(
      sessionId: previous.id,
      workoutItemId: item.id,
      setNumber: 1,
      weightKg: 75,
      repsDone: 9,
    );
    await repo.finishSession(previous.id);

    await pumpApp(tester);
    await tester.tap(find.text('Chest Day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();

    // The whole reason this beats a notes app.
    expect(find.text('75 kg × 9'), findsOneWidget);
  });
}
