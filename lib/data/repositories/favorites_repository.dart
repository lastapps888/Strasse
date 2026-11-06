import 'package:sqflite/sqflite.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/core/storage/app_database.dart';
import 'package:strasse/domain/domain.dart';
import 'package:uuid/uuid.dart';

/// Favoris et collections. Les suppressions sont des « tombstones » (deleted = 1) pour pouvoir être synchronisées.
class FavoritesRepository {
  FavoritesRepository(this._app);

  final AppDatabase _app;
  Database get _db => _app.db;
  static const _uuid = Uuid();

  Favorite _fromRow(Map<String, Object?> r) => Favorite(
        id: r['id'] as String,
        name: r['name'] as String,
        address: r['address'] as String?,
        category: r['category'] as String?,
        point: GeoPoint((r['lat'] as num).toDouble(), (r['lon'] as num).toDouble()),
        kind: FavoriteKind.values.firstWhere((k) => k.name == r['kind'], orElse: () => FavoriteKind.place),
        collectionId: r['collection_id'] as String?,
        note: r['note'] as String?,
        position: (r['position'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.parse(r['updated_at'] as String).toUtc(),
        deleted: (r['deleted'] as num?) == 1,
      );

  Map<String, Object?> _toRow(Favorite f) => {
        'id': f.id,
        'name': f.name,
        'address': f.address,
        'category': f.category,
        'lat': f.point.lat,
        'lon': f.point.lon,
        'kind': f.kind.name,
        'collection_id': f.collectionId,
        'note': f.note,
        'position': f.position,
        'updated_at': f.updatedAt.toUtc().toIso8601String(),
        'deleted': f.deleted ? 1 : 0,
      };

  PlaceCollection _collFromRow(Map<String, Object?> r) => PlaceCollection(
        id: r['id'] as String,
        name: r['name'] as String,
        description: r['description'] as String?,
        position: (r['position'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.parse(r['updated_at'] as String).toUtc(),
        deleted: (r['deleted'] as num?) == 1,
      );

  Map<String, Object?> _collToRow(PlaceCollection c) => {
        'id': c.id,
        'name': c.name,
        'description': c.description,
        'position': c.position,
        'updated_at': c.updatedAt.toUtc().toIso8601String(),
        'deleted': c.deleted ? 1 : 0,
      };

  // ------------------------------------------------------------------ Favoris

  Future<List<Favorite>> all() async {
    final rows = await _db.query('favorites', where: 'deleted = 0', orderBy: 'position ASC, name COLLATE NOCASE ASC');
    return rows.map(_fromRow).toList();
  }

  Future<Favorite?> byKind(FavoriteKind kind) async {
    final rows = await _db.query('favorites', where: 'deleted = 0 AND kind = ?', whereArgs: [kind.name], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// Favori existant à moins de 30 m du lieu (évite les doublons).
  Future<Favorite?> findNear(GeoPoint p) async {
    for (final f in await all()) {
      if (f.kind == FavoriteKind.place && distanceM(f.point, p) < 30) return f;
    }
    return null;
  }

  Future<Favorite> addPlace(Place place, {String? collectionId, FavoriteKind kind = FavoriteKind.place}) async {
    final existing = await findNear(place.point);
    if (existing != null && kind == FavoriteKind.place) return existing;
    final now = DateTime.now().toUtc();
    final fav = Favorite(
      id: _uuid.v4(),
      name: place.title,
      address: place.address,
      category: place.category,
      point: place.point,
      kind: kind,
      collectionId: collectionId,
      updatedAt: now,
    );
    await _db.insert('favorites', _toRow(fav));
    return fav;
  }

  /// Définit (ou remplace) le domicile ou le travail.
  Future<Favorite> setSpecial(FavoriteKind kind, Place place) async {
    assert(kind != FavoriteKind.place);
    final current = await byKind(kind);
    final now = DateTime.now().toUtc();
    final fav = Favorite(
      id: current?.id ?? _uuid.v4(),
      name: kind == FavoriteKind.home ? 'Domicile' : 'Travail',
      address: place.address ?? place.title,
      category: place.category,
      point: place.point,
      kind: kind,
      updatedAt: now,
    );
    await _db.insert('favorites', _toRow(fav), conflictAlgorithm: ConflictAlgorithm.replace);
    return fav;
  }

  Future<void> update(Favorite f) async {
    await _db.insert('favorites', _toRow(f.copyWith()), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    await _db.update(
      'favorites',
      {'deleted': 1, 'updated_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> restore(String id) async {
    await _db.update(
      'favorites',
      {'deleted': 0, 'updated_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // -------------------------------------------------------------- Collections

  Future<List<PlaceCollection>> collections() async {
    final rows = await _db.query('collections', where: 'deleted = 0', orderBy: 'position ASC, name COLLATE NOCASE ASC');
    return rows.map(_collFromRow).toList();
  }

  Future<PlaceCollection> createCollection(String name, {String? description}) async {
    final existing = await collections();
    final c = PlaceCollection(
      id: _uuid.v4(),
      name: name.trim(),
      description: (description?.trim().isEmpty ?? true) ? null : description!.trim(),
      position: existing.length,
      updatedAt: DateTime.now().toUtc(),
    );
    await _db.insert('collections', _collToRow(c));
    return c;
  }

  Future<void> updateCollection(PlaceCollection c) async {
    await _db.insert('collections', _collToRow(c), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Supprime une collection ; ses favoris sont conservés (ils redeviennent « sans collection »).
  Future<void> deleteCollection(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      await txn.update('collections', {'deleted': 1, 'updated_at': now}, where: 'id = ?', whereArgs: [id]);
      await txn.update('favorites', {'collection_id': null, 'updated_at': now}, where: 'collection_id = ?', whereArgs: [id]);
    });
  }

  /// Réorganise les collections selon l'ordre donné.
  Future<void> reorderCollections(List<PlaceCollection> ordered) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final batch = _db.batch();
    for (var i = 0; i < ordered.length; i++) {
      batch.update('collections', {'position': i, 'updated_at': now}, where: 'id = ?', whereArgs: [ordered[i].id]);
    }
    await batch.commit(noResult: true);
  }

  // ----------------------------------------------------------- Synchronisation

  Future<List<Favorite>> allIncludingDeleted() async => (await _db.query('favorites')).map(_fromRow).toList();
  Future<List<PlaceCollection>> allCollectionsIncludingDeleted() async => (await _db.query('collections')).map(_collFromRow).toList();

  /// Applique des éléments reçus du serveur : le plus récent gagne.
  Future<int> applyRemoteFavorites(List<Favorite> remote) async {
    var applied = 0;
    for (final r in remote) {
      final rows = await _db.query('favorites', where: 'id = ?', whereArgs: [r.id], limit: 1);
      if (rows.isEmpty || _fromRow(rows.first).updatedAt.isBefore(r.updatedAt)) {
        await _db.insert('favorites', _toRow(r), conflictAlgorithm: ConflictAlgorithm.replace);
        applied++;
      }
    }
    return applied;
  }

  Future<int> applyRemoteCollections(List<PlaceCollection> remote) async {
    var applied = 0;
    for (final r in remote) {
      final rows = await _db.query('collections', where: 'id = ?', whereArgs: [r.id], limit: 1);
      if (rows.isEmpty || _collFromRow(rows.first).updatedAt.isBefore(r.updatedAt)) {
        await _db.insert('collections', _collToRow(r), conflictAlgorithm: ConflictAlgorithm.replace);
        applied++;
      }
    }
    return applied;
  }
}
