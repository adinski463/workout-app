import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'data/catalog/catalog_loader.dart';
import 'data/local/database.dart';
import 'data/local/workout_repository.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _registerDesktopDatabase();

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

/// sqflite ships a native implementation for Android and iOS only. On desktop
/// the FFI factory has to be registered explicitly, otherwise opening the
/// database throws on the first launch.
///
/// Running on Windows is the fastest way to iterate on the UI without a phone
/// or emulator attached, so this is worth the six lines.
void _registerDesktopDatabase() {
  if (kIsWeb) return;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
