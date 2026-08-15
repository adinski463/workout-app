import 'package:flutter/foundation.dart';

/// Which half of the body diagram a muscle is drawn on.
enum BodySide { front, back }

enum MuscleRole { primary, secondary }

/// A muscle or sub-muscle. Sub-muscles carry a [parentSlug]; groups do not.
///
/// The sub-muscle layer is the point of the app — it is what lets a workout say
/// "rear delts" instead of "shoulders".
@immutable
class Muscle {
  const Muscle({
    required this.slug,
    required this.name,
    required this.parentSlug,
    required this.side,
    required this.sortOrder,
  });

  final String slug;
  final String name;
  final String? parentSlug;
  final BodySide side;
  final int sortOrder;

  bool get isGroup => parentSlug == null;

  factory Muscle.fromJson(Map<String, dynamic> json) => Muscle(
    slug: json['slug'] as String,
    name: json['name'] as String,
    parentSlug: json['parent'] as String?,
    side: json['side'] == 'back' ? BodySide.back : BodySide.front,
    sortOrder: json['order'] as int,
  );
}

enum Equipment {
  barbell,
  dumbbell,
  machine,
  cable,
  bodyweight,
  kettlebell,
  band,
  other;

  static Equipment parse(String value) => Equipment.values.firstWhere(
    (e) => e.name == value,
    orElse: () => Equipment.other,
  );

  String get label => switch (this) {
    Equipment.barbell => 'Barbell',
    Equipment.dumbbell => 'Dumbbell',
    Equipment.machine => 'Machine',
    Equipment.cable => 'Cable',
    Equipment.bodyweight => 'Bodyweight',
    Equipment.kettlebell => 'Kettlebell',
    Equipment.band => 'Band',
    Equipment.other => 'Other',
  };
}

enum Difficulty { beginner, intermediate, advanced }

@immutable
class Exercise {
  const Exercise({
    required this.slug,
    required this.name,
    required this.equipment,
    required this.primaryMuscles,
    required this.secondaryMuscles,
    this.description,
    this.difficulty,
    this.isCompound = true,
    this.imageUrl,
  });

  final String slug;
  final String name;
  final Equipment equipment;

  /// Sub-muscle slugs. Primary movers carry full weight in coverage maths,
  /// secondary ones count half.
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;

  final String? description;
  final Difficulty? difficulty;
  final bool isCompound;

  /// Nullable on purpose: upstream image coverage is uneven, so every surface
  /// that shows an exercise must degrade gracefully.
  final String? imageUrl;

  Iterable<String> get allMuscles => [...primaryMuscles, ...secondaryMuscles];

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    slug: json['slug'] as String,
    name: json['name'] as String,
    equipment: Equipment.parse(json['equipment'] as String? ?? 'other'),
    primaryMuscles: (json['p'] as List<dynamic>).cast<String>(),
    secondaryMuscles: (json['s'] as List<dynamic>? ?? const []).cast<String>(),
    description: json['description'] as String?,
    difficulty: switch (json['difficulty']) {
      'beginner' => Difficulty.beginner,
      'intermediate' => Difficulty.intermediate,
      'advanced' => Difficulty.advanced,
      _ => null,
    },
    isCompound: json['mechanic'] != 'isolation',
    imageUrl: json['image_url'] as String?,
  );
}

/// The loaded catalog, with the lookups the UI needs precomputed.
class Catalog {
  Catalog({required this.muscles, required this.exercises})
    : _muscleBySlug = {for (final m in muscles) m.slug: m},
      _exerciseBySlug = {for (final e in exercises) e.slug: e};

  final List<Muscle> muscles;
  final List<Exercise> exercises;

  final Map<String, Muscle> _muscleBySlug;
  final Map<String, Exercise> _exerciseBySlug;

  Muscle? muscle(String slug) => _muscleBySlug[slug];
  Exercise? exercise(String slug) => _exerciseBySlug[slug];

  List<Muscle> get groups =>
      muscles.where((m) => m.isGroup).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<Muscle> subMusclesOf(String groupSlug) =>
      muscles.where((m) => m.parentSlug == groupSlug).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<Muscle> get allSubMuscles =>
      muscles.where((m) => !m.isGroup).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// The group a sub-muscle belongs to, or the muscle itself if it is a group.
  Muscle? groupOf(String slug) {
    final m = _muscleBySlug[slug];
    if (m == null) return null;
    return m.isGroup ? m : _muscleBySlug[m.parentSlug];
  }

  /// Search and filter, all optional. [muscleSlug] accepts either a group
  /// (matches any of its sub-muscles) or a single sub-muscle.
  List<Exercise> filter({
    String query = '',
    String? muscleSlug,
    Equipment? equipment,
    bool primaryOnly = false,
  }) {
    final q = query.trim().toLowerCase();

    Set<String>? wanted;
    if (muscleSlug != null) {
      final m = _muscleBySlug[muscleSlug];
      wanted = m == null
          ? {muscleSlug}
          : m.isGroup
          ? subMusclesOf(m.slug).map((s) => s.slug).toSet()
          : {m.slug};
    }

    return exercises.where((e) {
      if (q.isNotEmpty && !e.name.toLowerCase().contains(q)) return false;
      if (equipment != null && e.equipment != equipment) return false;
      if (wanted != null) {
        final pool = primaryOnly ? e.primaryMuscles : e.allMuscles;
        if (!pool.any(wanted.contains)) return false;
      }
      return true;
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Replacement candidates for [slug]: exercises sharing at least one primary
  /// sub-muscle, best overlap first. Mirrors `swap_candidates` in SQL.
  ///
  /// Popularity ranking waits until there is real traffic to rank by — at
  /// launch there are no likes, so overlap and equipment variety decide.
  List<Exercise> swapCandidates(String slug) {
    final source = _exerciseBySlug[slug];
    if (source == null) return const [];
    final targets = source.primaryMuscles.toSet();

    final scored = <(Exercise, int)>[];
    for (final e in exercises) {
      if (e.slug == slug) continue;
      final overlap = e.primaryMuscles.where(targets.contains).length;
      if (overlap > 0) scored.add((e, overlap));
    }

    scored.sort((a, b) {
      final byOverlap = b.$2.compareTo(a.$2);
      if (byOverlap != 0) return byOverlap;
      return a.$1.name.compareTo(b.$1.name);
    });

    return scored.map((s) => s.$1).toList();
  }
}
