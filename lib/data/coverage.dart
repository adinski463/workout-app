import 'package:flutter/foundation.dart';

import 'catalog/catalog_models.dart';

/// How thoroughly a workout trains one sub-muscle.
enum CoverageBand {
  /// Not trained at all. The gaps the app exists to reveal.
  none,

  /// Touched, but not enough to drive growth on its own — typically only
  /// secondary/assisting work.
  light,

  /// Trained as a real target.
  solid,
}

/// Weighted working sets for a single sub-muscle.
@immutable
class MuscleCoverage {
  const MuscleCoverage({
    required this.muscle,
    required this.weightedSets,
    required this.hasPrimaryWork,
  });

  final Muscle muscle;

  /// Primary work counts 1.0 per set, secondary 0.5.
  ///
  /// This weighting is the whole point of the feature: a workout that merely
  /// grazes the rear delts must not look the same as one that trains them.
  final double weightedSets;

  final bool hasPrimaryWork;

  CoverageBand get band {
    if (weightedSets <= 0) return CoverageBand.none;
    if (weightedSets < solidThreshold) return CoverageBand.light;
    return CoverageBand.solid;
  }

  /// Three weighted sets in one session is the point where the work stops being
  /// incidental. Deliberately conservative — it is better to tell someone a
  /// muscle is under-trained than to let them believe a single set covered it.
  static const double solidThreshold = 3.0;
}

/// One exercise as it appears in a workout, reduced to what coverage needs.
@immutable
class CoverageInput {
  const CoverageInput({required this.exercise, required this.sets});

  final Exercise exercise;
  final int sets;
}

/// Volume-weighted coverage across the whole body.
///
/// Mirrors the `workout_coverage` SQL function so the client and the server
/// agree; the client version exists so the map renders instantly offline.
class CoverageReport {
  CoverageReport._(this._bySlug, this.catalog);

  final Map<String, MuscleCoverage> _bySlug;
  final Catalog catalog;

  factory CoverageReport.compute({
    required Catalog catalog,
    required List<CoverageInput> items,
  }) {
    final weighted = <String, double>{};
    final primary = <String>{};

    for (final item in items) {
      for (final slug in item.exercise.primaryMuscles) {
        weighted[slug] = (weighted[slug] ?? 0) + item.sets;
        primary.add(slug);
      }
      for (final slug in item.exercise.secondaryMuscles) {
        weighted[slug] = (weighted[slug] ?? 0) + item.sets * 0.5;
      }
    }

    final result = <String, MuscleCoverage>{};
    for (final muscle in catalog.allSubMuscles) {
      result[muscle.slug] = MuscleCoverage(
        muscle: muscle,
        weightedSets: weighted[muscle.slug] ?? 0,
        hasPrimaryWork: primary.contains(muscle.slug),
      );
    }

    return CoverageReport._(result, catalog);
  }

  MuscleCoverage? forMuscle(String slug) => _bySlug[slug];

  double setsFor(String slug) => _bySlug[slug]?.weightedSets ?? 0;

  CoverageBand bandFor(String slug) =>
      _bySlug[slug]?.band ?? CoverageBand.none;

  /// Sub-muscles that got some work, strongest first.
  List<MuscleCoverage> get trained =>
      _bySlug.values.where((c) => c.weightedSets > 0).toList()
        ..sort((a, b) => b.weightedSets.compareTo(a.weightedSets));

  /// The headline insight: muscle groups this workout is *partly* training,
  /// with at least one sub-muscle left untouched.
  ///
  /// A leg day that skips calves is expected and not interesting. A shoulder
  /// workout with front and side delts but nothing for the rear delts is the
  /// gap worth surfacing, so only groups already being worked are reported.
  List<MuscleGap> get gaps {
    final result = <MuscleGap>[];

    for (final group in catalog.groups) {
      final subs = catalog.subMusclesOf(group.slug);
      if (subs.isEmpty) continue;

      final missed = subs
          .where((s) => bandFor(s.slug) == CoverageBand.none)
          .toList();
      final covered = subs.length - missed.length;

      // Only flag a group that is genuinely being trained but incompletely.
      if (missed.isNotEmpty && covered > 0) {
        result.add(MuscleGap(group: group, missing: missed));
      }
    }

    return result;
  }

  /// Total weighted sets, used for the "hard sets" headline on a workout card.
  double get totalWeightedSets =>
      _bySlug.values.fold(0.0, (sum, c) => sum + c.weightedSets);
}

@immutable
class MuscleGap {
  const MuscleGap({required this.group, required this.missing});

  final Muscle group;
  final List<Muscle> missing;

  String describe() {
    final names = missing.map((m) => m.name).toList();
    final joined = switch (names.length) {
      1 => names.first,
      2 => '${names[0]} and ${names[1]}',
      _ => '${names.take(names.length - 1).join(', ')} and ${names.last}',
    };
    return 'This ${group.name.toLowerCase()} work skips $joined';
  }
}
