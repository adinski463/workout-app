import 'dart:convert';

import 'package:flutter/services.dart';

import 'catalog_models.dart';

/// Loads the bundled exercise catalog.
///
/// The catalog ships as an asset rather than being fetched on demand. Two
/// reasons: search stays instant with no network in the hot path, and the app
/// keeps working in a basement gym with no signal. A future sync job can top
/// this up from a remote source without any screen changing.
class CatalogLoader {
  const CatalogLoader({this.bundle});

  final AssetBundle? bundle;

  static const _musclesPath = 'assets/catalog/muscles.json';
  static const _exercisesPath = 'assets/catalog/exercises.json';

  Future<Catalog> load() async {
    final loader = bundle ?? rootBundle;

    final musclesRaw = await loader.loadString(_musclesPath);
    final exercisesRaw = await loader.loadString(_exercisesPath);

    return parse(musclesRaw: musclesRaw, exercisesRaw: exercisesRaw);
  }

  /// Split out from [load] so tests can exercise parsing without a bundle.
  static Catalog parse({
    required String musclesRaw,
    required String exercisesRaw,
  }) {
    final musclesJson = jsonDecode(musclesRaw) as Map<String, dynamic>;
    final exercisesJson = jsonDecode(exercisesRaw) as Map<String, dynamic>;

    final muscles = (musclesJson['muscles'] as List<dynamic>)
        .map((m) => Muscle.fromJson(m as Map<String, dynamic>))
        .toList();

    final exercises = (exercisesJson['exercises'] as List<dynamic>)
        .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
        .toList();

    return Catalog(muscles: muscles, exercises: exercises);
  }
}
