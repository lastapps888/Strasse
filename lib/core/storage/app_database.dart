import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Base SQLite locale : favoris, collections, historique, voyages, lieux récents, régions hors ligne.
class AppDatabase {
  AppDatabase._(this.db, {this.recoveredFromCorruption = false});

  final Database db;

  /// Vrai si la base existante était illisible et a été remplacée (l'ancienne est conservée en `.corrupt`).
  final bool recoveredFromCorruption;

  static const _version = 1;
  static const _fileName = 'strasse.db';

  static Future<AppDatabase> open({String? overridePath}) async {
    final dir = overridePath != null ? null : await getApplicationSupportDirectory();
    final path = overridePath ?? p.join(dir!.path, _fileName);
    try {
      final db = await _openAt(path);
      // Vérification d'intégrité rapide.
      final check = await db.rawQuery('PRAGMA quick_check');
      final ok = check.isNotEmpty && check.first.values.first == 'ok';
      if (!ok) throw const FormatException('quick_check a échoué');
      return AppDatabase._(db);
    } catch (_) {
      // Données locales corrompues : on met l'ancien fichier de côté et on repart d'une base saine.
      final f = File(path);
      if (await f.exists()) {
        try {
          await f.rename('$path.corrupt');
        } catch (_) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
      final db = await _openAt(path);
      return AppDatabase._(db, recoveredFromCorruption: true);
    }
  }

  static Future<Database> _openAt(String path) => openDatabase(
        path,
        version: _version,
        onCreate: _create,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      );

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE favorites (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT,
        category TEXT,
        lat REAL NOT NULL,
        lon REAL NOT NULL,
        kind TEXT NOT NULL DEFAULT 'place',
        collection_id TEXT,
        note TEXT,
        position INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('CREATE INDEX favorites_kind_idx ON favorites(kind, deleted)');
    await db.execute('''
      CREATE TABLE collections (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        position INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE history (
        id TEXT PRIMARY KEY,
        started_at TEXT NOT NULL,
        from_name TEXT NOT NULL,
        from_lat REAL NOT NULL,
        from_lon REAL NOT NULL,
        to_name TEXT NOT NULL,
        to_lat REAL NOT NULL,
        to_lon REAL NOT NULL,
        mode TEXT NOT NULL,
        distance_m REAL NOT NULL,
        duration_s REAL NOT NULL,
        shape TEXT NOT NULL,
        completed INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute('CREATE INDEX history_started_idx ON history(started_at)');
    await db.execute('''
      CREATE TABLE planned_trips (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        mode TEXT NOT NULL,
        waypoints TEXT NOT NULL,
        options TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE recent_places (
        id TEXT PRIMARY KEY,
        json TEXT NOT NULL,
        used_at TEXT NOT NULL,
        use_count INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute('''
      CREATE TABLE search_queries (
        query TEXT PRIMARY KEY,
        used_at TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE offline_regions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        south REAL NOT NULL,
        west REAL NOT NULL,
        north REAL NOT NULL,
        east REAL NOT NULL,
        min_zoom INTEGER NOT NULL,
        max_zoom INTEGER NOT NULL,
        status TEXT NOT NULL,
        native_id INTEGER,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        required_resources INTEGER NOT NULL DEFAULT 0,
        completed_resources INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        error TEXT
      )''');
  }

  /// Supprime toutes les données utilisateur (favoris, historique, voyages, recherches, régions).
  Future<void> wipeAll() async {
    final batch = db.batch();
    for (final t in ['favorites', 'collections', 'history', 'planned_trips', 'recent_places', 'search_queries', 'offline_regions']) {
      batch.delete(t);
    }
    await batch.commit(noResult: true);
  }

  Future<void> close() => db.close();
}
