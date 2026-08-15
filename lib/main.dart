import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/catalog/catalog_loader.dart';
import 'data/local/database.dart';
import 'data/local/workout_repository.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catalog and database are built once here and injected as overrides, so no
  // screen has to unwrap an AsyncValue just to read an exercise name.
  final catalog = await const CatalogLoader().load();

  final directory = await getApplicationDocumentsDirectory();
  final database = await AppDatabase.open(
    path: p.join(directory.path, 'workout.db'),
  );

  runApp(
    ProviderScope(
      overrides: [
        catalogProvider.overrideWithValue(catalog),
        repositoryProvider.overrideWithValue(LocalWorkoutRepository(database)),
      ],
      child: const WorkoutApp(),
    ),
  );
}
