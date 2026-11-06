import 'package:sqflite/sqflite.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/core/storage/app_database.dart';
import 'package:strasse/domain/domain.dart';

/// Métadonnées des régions de carte téléchargées (les tuiles elles-mêmes sont gérées par le moteur cartographique).
class OfflineRepository {
  OfflineRepository(this._app);

  final AppDatabase _app;
  Database get _db => _app.db;

  OfflineRegionInfo _fromRow(Map<String, Object?> r) => OfflineRegionInfo(
        id: r['id'] as String,
        name: r['name'] as String,
        bounds: GeoBounds(
          south: (r['south'] as num).toDouble(),
          west: (r['west'] as num).toDouble(),
          north: (r['north'] as num).toDouble(),
          east: (r['east'] as num).toDouble(),
        ),
        minZoom: (r['min_zoom'] as num).toInt(),
        maxZoom: (r['max_zoom'] as num).toInt(),
        status: OfflineStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => OfflineStatus.failed),
        nativeId: (r['native_id'] as num?)?.toInt(),
        sizeBytes: (r['size_bytes'] as num?)?.toInt() ?? 0,
        requiredResources: (r['required_resources'] as num?)?.toInt() ?? 0,
        completedResources: (r['completed_resources'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.parse(r['updated_at'] as String).toLocal(),
        error: r['error'] as String?,
        progress: (r['status'] == 'complete') ? 100 : 0,
      );

  Future<List<OfflineRegionInfo>> all() async => (await _db.query('offline_regions', orderBy: 'updated_at DESC')).map(_fromRow).toList();

  Future<OfflineRegionInfo?> byId(String id) async {
    final rows = await _db.query('offline_regions', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<void> save(OfflineRegionInfo r) async {
    await _db.insert(
      'offline_regions',
      {
        'id': r.id,
        'name': r.name,
        'south': r.bounds.south,
        'west': r.bounds.west,
        'north': r.bounds.north,
        'east': r.bounds.east,
        'min_zoom': r.minZoom,
        'max_zoom': r.maxZoom,
        'status': r.status.name,
        'native_id': r.nativeId,
        'size_bytes': r.sizeBytes,
        'required_resources': r.requiredResources,
        'completed_resources': r.completedResources,
        'updated_at': r.updatedAt.toUtc().toIso8601String(),
        'error': r.error,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) => _db.delete('offline_regions', where: 'id = ?', whereArgs: [id]);

  /// Région téléchargée qui couvre entièrement `bounds` (pour éviter les doublons).
  Future<OfflineRegionInfo?> coveringRegion(GeoBounds bounds, int maxZoom) async {
    for (final r in await all()) {
      if (r.isComplete &&
          r.maxZoom >= maxZoom &&
          r.bounds.south <= bounds.south &&
          r.bounds.west <= bounds.west &&
          r.bounds.north >= bounds.north &&
          r.bounds.east >= bounds.east) {
        return r;
      }
    }
    return null;
  }
}
