import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/core/storage/app_database.dart';
import 'package:strasse/domain/domain.dart';

/// Lieux consultés récemment et requêtes de recherche mémorisées (localement, sur demande de l'utilisateur).
class PlacesRepository {
  PlacesRepository(this._app);

  final AppDatabase _app;
  Database get _db => _app.db;

  Future<void> addRecent(Place place) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await _db.query('recent_places', where: 'id = ?', whereArgs: [place.id], limit: 1);
    final count = rows.isEmpty ? 1 : ((rows.first['use_count'] as num?)?.toInt() ?? 1) + 1;
    await _db.insert(
      'recent_places',
      {'id': place.id, 'json': jsonEncode(place.toJson()), 'used_at': now, 'use_count': count},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Conserve les 60 plus récents.
    await _db.execute(
      'DELETE FROM recent_places WHERE id NOT IN (SELECT id FROM recent_places ORDER BY used_at DESC LIMIT 60)',
    );
  }

  Future<List<Place>> recents({int limit = 20}) async {
    final rows = await _db.query('recent_places', orderBy: 'used_at DESC', limit: limit);
    final out = <Place>[];
    for (final r in rows) {
      try {
        out.add(Place.fromJson(Map<String, dynamic>.from(jsonDecode(r['json'] as String) as Map)).copyWith(source: 'history'));
      } catch (_) {
        // entrée illisible : ignorée
      }
    }
    return out;
  }

  Future<void> removeRecent(String id) => _db.delete('recent_places', where: 'id = ?', whereArgs: [id]);
  Future<void> clearRecents() => _db.delete('recent_places');

  Future<void> addQuery(String query) async {
    final q = query.trim();
    if (q.length < 2) return;
    await _db.insert(
      'search_queries',
      {'query': q, 'used_at': DateTime.now().toUtc().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _db.execute(
      'DELETE FROM search_queries WHERE query NOT IN (SELECT query FROM search_queries ORDER BY used_at DESC LIMIT 30)',
    );
  }

  Future<List<String>> queries({int limit = 10}) async {
    final rows = await _db.query('search_queries', orderBy: 'used_at DESC', limit: limit);
    return rows.map((r) => r['query'] as String).toList();
  }

  Future<void> removeQuery(String q) => _db.delete('search_queries', where: 'query = ?', whereArgs: [q]);
  Future<void> clearQueries() => _db.delete('search_queries');

  /// Recherche locale tolérante aux accents et à la casse dans les lieux récents.
  Future<List<Place>> searchRecents(String query, {int limit = 5}) async {
    final q = foldText(query.trim());
    if (q.isEmpty) return const [];
    final all = await recents(limit: 60);
    return all
        .where((p) => foldText('${p.title} ${p.address ?? ''}').contains(q))
        .take(limit)
        .toList();
  }
}
