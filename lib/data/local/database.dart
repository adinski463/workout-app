import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// The on-device database.
///
/// This is the source of truth while you are in the gym. Everything the logging
/// screen does is a local write that returns immediately, because gym signal is
/// unreliable and a set must never fail to record because an HTTP request did.
/// Syncing to Supabase is a separate, later concern layered on top.
///
/// The shape deliberately mirrors `supabase/migrations/`, with one difference:
/// exercises are referenced by slug rather than uuid, because the catalog ships
/// as a bundled asset on device. Slug is unique in the remote catalog too, so
/// the mapping at sync time is direct.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const _version = 1;

  /// Opens the database at [path]. Pass `inMemoryDatabasePath` in tests.
  static Future<AppDatabase> open({
    required String path,
    DatabaseFactory? factory,
  }) async {
    final f = factory ?? databaseFactory;
    final database = await f.openDatabase(
      path == inMemoryDatabasePath ? path : p.normalize(path),
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
      ),
    );
    return AppDatabase._(database);
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE workouts (
        id                  TEXT PRIMARY KEY,
        title               TEXT NOT NULL,
        description         TEXT,
        is_published        INTEGER NOT NULL DEFAULT 0,
        source_workout_id   TEXT,
        source_creator_name TEXT,
        created_at          INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE workout_items (
        id            TEXT PRIMARY KEY,
        workout_id    TEXT NOT NULL REFERENCES workouts (id) ON DELETE CASCADE,
        exercise_slug TEXT NOT NULL,
        order_index   INTEGER NOT NULL,
        target_sets   INTEGER NOT NULL DEFAULT 3,
        target_reps   INTEGER NOT NULL DEFAULT 10,
        rest_seconds  INTEGER NOT NULL DEFAULT 90,
        note          TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX workout_items_workout_idx ON workout_items (workout_id)',
    );

    await db.execute('''
      CREATE TABLE workout_sessions (
        id          TEXT PRIMARY KEY,
        workout_id  TEXT NOT NULL REFERENCES workouts (id) ON DELETE CASCADE,
        started_at  INTEGER NOT NULL,
        finished_at INTEGER,
        note        TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX workout_sessions_started_idx '
      'ON workout_sessions (started_at DESC)',
    );

    await db.execute('''
      CREATE TABLE set_logs (
        id              TEXT PRIMARY KEY,
        session_id      TEXT NOT NULL
                          REFERENCES workout_sessions (id) ON DELETE CASCADE,
        workout_item_id TEXT NOT NULL
                          REFERENCES workout_items (id) ON DELETE CASCADE,
        set_number      INTEGER NOT NULL,
        weight_kg       REAL,
        reps_done       INTEGER,
        completed_at    INTEGER NOT NULL,
        UNIQUE (session_id, workout_item_id, set_number)
      )
    ''');
    await db.execute(
      'CREATE INDEX set_logs_item_idx ON set_logs (workout_item_id, completed_at DESC)',
    );
  }

  Future<void> close() => db.close();
}
