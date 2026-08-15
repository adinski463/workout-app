import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_app/data/catalog/catalog_loader.dart';
import 'package:workout_app/data/catalog/catalog_models.dart';

/// Guards the hand-authored catalog. A typo in a muscle slug silently breaks
/// filtering, the coverage map and the swap picker at once, so it is worth
/// failing the build over.
void main() {
  late Catalog catalog;

  setUpAll(() {
    catalog = CatalogLoader.parse(
      musclesRaw: File('assets/catalog/muscles.json').readAsStringSync(),
      exercisesRaw: File('assets/catalog/exercises.json').readAsStringSync(),
    );
  });

  test('taxonomy has groups and sub-muscles', () {
    expect(catalog.groups, isNotEmpty);
    expect(catalog.allSubMuscles.length, greaterThan(25));

    for (final group in catalog.groups) {
      expect(
        catalog.subMusclesOf(group.slug),
        isNotEmpty,
        reason: '${group.slug} is a group with no sub-muscles',
      );
    }
  });

  test('every muscle slug is unique', () {
    final slugs = catalog.muscles.map((m) => m.slug).toList();
    expect(slugs.toSet().length, slugs.length);
  });

  test('every exercise references only real sub-muscles', () {
    final subSlugs = catalog.allSubMuscles.map((m) => m.slug).toSet();

    for (final exercise in catalog.exercises) {
      expect(
        exercise.primaryMuscles,
        isNotEmpty,
        reason: '${exercise.slug} has no primary muscle',
      );

      for (final slug in exercise.allMuscles) {
        expect(
          subSlugs,
          contains(slug),
          reason: '${exercise.slug} references unknown sub-muscle "$slug"',
        );
      }
    }
  });

  test('no exercise lists a muscle as both primary and secondary', () {
    for (final exercise in catalog.exercises) {
      final overlap = exercise.primaryMuscles.toSet().intersection(
        exercise.secondaryMuscles.toSet(),
      );
      expect(overlap, isEmpty, reason: '${exercise.slug} double-counts $overlap');
    }
  });

  test('every sub-muscle has at least two exercises that target it', () {
    // One is not enough: a coverage gap must be fixable inside the app, and a
    // swap must always have somewhere to go. A sub-muscle with a single
    // exercise is a dead end in both features.
    final targeted = <String, int>{};
    for (final e in catalog.exercises) {
      for (final slug in e.primaryMuscles) {
        targeted[slug] = (targeted[slug] ?? 0) + 1;
      }
    }

    for (final muscle in catalog.allSubMuscles) {
      expect(
        targeted[muscle.slug] ?? 0,
        greaterThanOrEqualTo(2),
        reason: 'only ${targeted[muscle.slug] ?? 0} exercise(s) primarily '
            'train ${muscle.slug}',
      );
    }
  });

  group('filtering', () {
    test('by group matches any of its sub-muscles', () {
      final chest = catalog.filter(muscleSlug: 'chest');
      expect(chest, isNotEmpty);
      expect(
        chest.every(
          (e) => e.allMuscles.any((m) => m.startsWith('chest-')),
        ),
        isTrue,
      );
    });

    test('by sub-muscle is narrower than by group', () {
      final allChest = catalog.filter(muscleSlug: 'chest');
      final upperOnly = catalog.filter(muscleSlug: 'chest-upper');

      expect(upperOnly.length, lessThan(allChest.length));
      expect(
        upperOnly.every((e) => e.allMuscles.contains('chest-upper')),
        isTrue,
      );
    });

    test('primaryOnly excludes exercises that merely assist', () {
      final any = catalog.filter(muscleSlug: 'delts-front');
      final primary = catalog.filter(
        muscleSlug: 'delts-front',
        primaryOnly: true,
      );

      expect(primary.length, lessThan(any.length));
      // The bench press hits the front delts, but is not a shoulder exercise.
      expect(any.map((e) => e.slug), contains('barbell-bench-press'));
      expect(primary.map((e) => e.slug), isNot(contains('barbell-bench-press')));
    });

    test('query and equipment filters combine', () {
      final result = catalog.filter(query: 'press', equipment: Equipment.dumbbell);
      expect(result, isNotEmpty);
      expect(
        result.every(
          (e) =>
              e.name.toLowerCase().contains('press') &&
              e.equipment == Equipment.dumbbell,
        ),
        isTrue,
      );
    });

    test('unknown query returns empty rather than throwing', () {
      expect(catalog.filter(query: 'zzzzz-not-an-exercise'), isEmpty);
    });
  });

  group('swap candidates', () {
    test('suggests exercises sharing a primary muscle', () {
      final candidates = catalog.swapCandidates('barbell-bench-press');
      expect(candidates, isNotEmpty);

      // Bench press is primarily mid chest; every suggestion must train it too.
      expect(
        candidates.every((e) => e.primaryMuscles.contains('chest-mid')),
        isTrue,
      );
    });

    test('never suggests the exercise being replaced', () {
      final candidates = catalog.swapCandidates('lat-pulldown');
      expect(candidates.map((e) => e.slug), isNot(contains('lat-pulldown')));
    });

    test('does not suggest an unrelated muscle group', () {
      final candidates = catalog.swapCandidates('seated-calf-raise')
          .map((e) => e.slug);
      expect(candidates, isNot(contains('barbell-curl')));
    });

    test('every exercise has at least one alternative', () {
      for (final exercise in catalog.exercises) {
        expect(
          catalog.swapCandidates(exercise.slug),
          isNotEmpty,
          reason: '${exercise.slug} has no swap candidate',
        );
      }
    });
  });
}
