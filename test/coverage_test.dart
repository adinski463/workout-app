import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_app/data/catalog/catalog_loader.dart';
import 'package:workout_app/data/catalog/catalog_models.dart';
import 'package:workout_app/data/coverage.dart';

void main() {
  late Catalog catalog;

  setUpAll(() {
    catalog = CatalogLoader.parse(
      musclesRaw: File('assets/catalog/muscles.json').readAsStringSync(),
      exercisesRaw: File('assets/catalog/exercises.json').readAsStringSync(),
    );
  });

  CoverageReport report(List<(String, int)> plan) => CoverageReport.compute(
    catalog: catalog,
    items: [
      for (final (slug, sets) in plan)
        CoverageInput(exercise: catalog.exercise(slug)!, sets: sets),
    ],
  );

  test('primary work counts full, secondary counts half', () {
    // Bench press: primary mid chest, secondary front delts + triceps.
    final r = report([('barbell-bench-press', 4)]);

    expect(r.setsFor('chest-mid'), 4.0);
    expect(r.setsFor('delts-front'), 2.0);
    expect(r.setsFor('triceps-lateral'), 2.0);
  });

  test('volume accumulates across exercises', () {
    final r = report([
      ('barbell-bench-press', 4),
      ('incline-dumbbell-press', 3),
      ('cable-fly-mid', 3),
    ]);

    // Mid chest: 4 from bench + 3 from the fly. Upper chest: 3 from the incline.
    expect(r.setsFor('chest-mid'), 7.0);
    expect(r.setsFor('chest-upper'), 3.0);
  });

  test('an untrained muscle bands as none', () {
    final r = report([('barbell-bench-press', 4)]);
    expect(r.bandFor('lats'), CoverageBand.none);
    expect(r.setsFor('lats'), 0.0);
  });

  test('light and solid bands split at the threshold', () {
    // 4 sets of bench gives the front delts exactly 2.0 weighted sets: real
    // work, but not enough to call the muscle trained.
    final light = report([('barbell-bench-press', 4)]);
    expect(light.bandFor('delts-front'), CoverageBand.light);
    expect(light.bandFor('chest-mid'), CoverageBand.solid);

    final solid = report([('barbell-bench-press', 6)]);
    expect(solid.setsFor('delts-front'), 3.0);
    expect(solid.bandFor('delts-front'), CoverageBand.solid);
  });

  test('one token set does not make a muscle look trained', () {
    // This is the failure mode the whole feature exists to prevent.
    final r = report([('reverse-pec-deck', 1)]);
    expect(r.bandFor('delts-rear'), CoverageBand.light);
    expect(r.bandFor('delts-rear'), isNot(CoverageBand.solid));
  });

  test('hasPrimaryWork distinguishes targeted from incidental work', () {
    final r = report([('barbell-bench-press', 4)]);
    expect(r.forMuscle('chest-mid')!.hasPrimaryWork, isTrue);
    expect(r.forMuscle('delts-front')!.hasPrimaryWork, isFalse);
  });

  group('gap detection', () {
    test('flags the classic rear delt gap', () {
      // A shoulder day of pressing and lateral raises: front and side delts
      // covered, rear delts untouched. This is the headline example.
      final r = report([
        ('overhead-press', 4),
        ('dumbbell-lateral-raise', 4),
      ]);

      final shoulderGap = r.gaps.firstWhere((g) => g.group.slug == 'shoulders');
      expect(
        shoulderGap.missing.map((m) => m.slug),
        contains('delts-rear'),
      );
      expect(shoulderGap.describe(), contains('Rear Delts'));
    });

    test('does not flag groups the workout never touches', () {
      // A pure chest workout skips legs entirely, which is not a "gap" — it is
      // just a chest workout. Only partially-trained groups are interesting.
      final r = report([('barbell-bench-press', 4), ('cable-fly-mid', 3)]);

      expect(r.gaps.map((g) => g.group.slug), isNot(contains('legs')));
      expect(r.gaps.map((g) => g.group.slug), contains('chest'));
    });

    test('a complete group produces no gap', () {
      final r = report([
        ('incline-dumbbell-press', 4), // upper
        ('barbell-bench-press', 4), // mid
        ('chest-dip', 3), // lower
      ]);

      expect(r.gaps.map((g) => g.group.slug), isNot(contains('chest')));
    });

    test('gap description reads naturally for one, two and three muscles', () {
      final one = MuscleGap(
        group: catalog.muscle('shoulders')!,
        missing: [catalog.muscle('delts-rear')!],
      );
      expect(one.describe(), 'This shoulders work skips Rear Delts');

      final two = MuscleGap(
        group: catalog.muscle('chest')!,
        missing: [catalog.muscle('chest-upper')!, catalog.muscle('chest-lower')!],
      );
      expect(two.describe(), contains('Upper Chest and Lower Chest'));

      final three = MuscleGap(
        group: catalog.muscle('back')!,
        missing: [
          catalog.muscle('lats')!,
          catalog.muscle('rhomboids')!,
          catalog.muscle('erectors')!,
        ],
      );
      expect(three.describe(), contains('Lats, Rhomboids and Spinal Erectors'));
    });
  });

  test('trained list is ordered by volume', () {
    final r = report([
      ('barbell-bench-press', 4),
      ('dumbbell-lateral-raise', 6),
    ]);

    final top = r.trained.first;
    expect(top.muscle.slug, 'delts-side');
    expect(top.weightedSets, 6.0);
  });

  test('empty workout reports no coverage and no gaps', () {
    final r = report([]);
    expect(r.trained, isEmpty);
    expect(r.gaps, isEmpty);
    expect(r.totalWeightedSets, 0.0);
  });
}
