import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/core/storage/app_database.dart';
import 'package:strasse/domain/domain.dart';
import 'package:uuid/uuid.dart';

/// Statistiques personnelles calculées localement à partir de l'historique.
class TripStats {
  const TripStats({
    required this.tripCount,
    required this.totalDistanceM,
    required this.totalDurationS,
    required this.byMode,
    required this.topDestinations,
    required this.weekly,
  });

  final int tripCount;
  final double totalDistanceM;
  final double totalDurationS;

  /// Distance (m) par mode de déplacement.
  final Map<TravelMode, double> byMode;

  /// (nom, nombre de visites)
  final List<({String name, int count})> topDestinations;

  /// Distance (m) des 8 dernières semaines, de la plus ancienne à la plus récente.
  final List<double> weekly;

  double get averageDistanceM => tripCount == 0 ? 0 : totalDistanceM / tripCount;
}

/// Historique des trajets et voyages planifiés.
class TripsRepository {
  TripsRepository(this._app);

  final AppDatabase _app;
  Database get _db => _app.db;
  static const _uuid = Uuid();

  TripRecord _fromRow(Map<String, Object?> r) => TripRecord(
        id: r['id'] as String,
        startedAt: DateTime.parse(r['started_at'] as String).toLocal(),
        fromName: r['from_name'] as String,
        from: GeoPoint((r['from_lat'] as num).toDouble(), (r['from_lon'] as num).toDouble()),
        toName: r['to_name'] as String,
        to: GeoPoint((r['to_lat'] as num).toDouble(), (r['to_lon'] as num).toDouble()),
        mode: TravelMode.fromName(r['mode'] as String?),
        distanceM: (r['distance_m'] as num).toDouble(),
        durationS: (r['duration_s'] as num).toDouble(),
        shape: r['shape'] as String,
        completed: (r['completed'] as num?) == 1,
      );

  Future<void> addTrip(TripRecord t) async {
    await _db.insert(
      'history',
      {
        'id': t.id.isEmpty ? _uuid.v4() : t.id,
        'started_at': t.startedAt.toUtc().toIso8601String(),
        'from_name': t.fromName,
        'from_lat': t.from.lat,
        'from_lon': t.from.lon,
        'to_name': t.toName,
        'to_lat': t.to.lat,
        'to_lon': t.to.lon,
        'mode': t.mode.name,
        'distance_m': t.distanceM,
        'duration_s': t.durationS,
        'shape': t.shape,
        'completed': t.completed ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<TripRecord>> history({String? query, int limit = 500}) async {
    final q = (query ?? '').trim();
    final rows = q.isEmpty
        ? await _db.query('history', orderBy: 'started_at DESC', limit: limit)
        : await _db.query(
            'history',
            where: 'from_name LIKE ? OR to_name LIKE ?',
            whereArgs: ['%$q%', '%$q%'],
            orderBy: 'started_at DESC',
            limit: limit,
          );
    return rows.map(_fromRow).toList();
  }

  Future<void> deleteTrip(String id) => _db.delete('history', where: 'id = ?', whereArgs: [id]);
  Future<void> clearHistory() => _db.delete('history');

  Future<TripStats> stats({DateTime? now}) async {
    final trips = await history(limit: 100000);
    final t0 = now ?? DateTime.now();
    final byMode = <TravelMode, double>{};
    final dest = <String, int>{};
    final weekly = List<double>.filled(8, 0);
    var dist = 0.0, dur = 0.0;
    for (final t in trips) {
      dist += t.distanceM;
      dur += t.durationS;
      byMode[t.mode] = (byMode[t.mode] ?? 0) + t.distanceM;
      dest[t.toName] = (dest[t.toName] ?? 0) + 1;
      final weeksAgo = t0.difference(t.startedAt).inDays ~/ 7;
      if (weeksAgo >= 0 && weeksAgo < 8) weekly[7 - weeksAgo] += t.distanceM;
    }
    final top = dest.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return TripStats(
      tripCount: trips.length,
      totalDistanceM: dist,
      totalDurationS: dur,
      byMode: byMode,
      topDestinations: [for (final e in top.take(5)) (name: e.key, count: e.value)],
      weekly: weekly,
    );
  }

  /// Destinations visitées au moins `minCount` fois.
  Future<List<({TripRecord trip, int count})>> frequentDestinations({int minCount = 2, int limit = 5}) async {
    final trips = await history(limit: 2000);
    final groups = <String, List<TripRecord>>{};
    for (final t in trips) {
      final key = '${t.to.lat.toStringAsFixed(3)},${t.to.lon.toStringAsFixed(3)}';
      (groups[key] ??= []).add(t);
    }
    final out = [for (final g in groups.values) if (g.length >= minCount) (trip: g.first, count: g.length)];
    out.sort((a, b) => b.count.compareTo(a.count));
    return out.take(limit).toList();
  }

  // ------------------------------------------------------------ Voyages planifiés

  PlannedTrip _plannedFromRow(Map<String, Object?> r) => PlannedTrip(
        id: r['id'] as String,
        name: r['name'] as String,
        mode: TravelMode.fromName(r['mode'] as String?),
        waypoints: (jsonDecode(r['waypoints'] as String) as List)
            .map((w) => Waypoint.fromJson(Map<String, dynamic>.from(w as Map)))
            .toList(),
        prefs: RoutePrefs.fromJson(Map<String, dynamic>.from(jsonDecode(r['options'] as String) as Map)),
        updatedAt: DateTime.parse(r['updated_at'] as String).toUtc(),
        deleted: (r['deleted'] as num?) == 1,
      );

  Map<String, Object?> _plannedToRow(PlannedTrip t) => {
        'id': t.id,
        'name': t.name,
        'mode': t.mode.name,
        'waypoints': jsonEncode(t.waypoints.map((w) => w.toJson()).toList()),
        'options': jsonEncode(t.prefs.toJson()),
        'updated_at': t.updatedAt.toUtc().toIso8601String(),
        'deleted': t.deleted ? 1 : 0,
      };

  Future<List<PlannedTrip>> plannedTrips() async {
    final rows = await _db.query('planned_trips', where: 'deleted = 0', orderBy: 'updated_at DESC');
    return rows.map(_plannedFromRow).toList();
  }

  Future<PlannedTrip> savePlannedTrip(PlannedTrip t) async {
    final toSave = t.id.isEmpty
        ? PlannedTrip(
            id: _uuid.v4(),
            name: t.name,
            mode: t.mode,
            waypoints: t.waypoints,
            prefs: t.prefs,
            updatedAt: DateTime.now().toUtc(),
          )
        : t.copyWith();
    await _db.insert('planned_trips', _plannedToRow(toSave), conflictAlgorithm: ConflictAlgorithm.replace);
    return toSave;
  }

  Future<void> deletePlannedTrip(String id) async {
    await _db.update(
      'planned_trips',
      {'deleted': 1, 'updated_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<PlannedTrip>> allPlannedIncludingDeleted() async => (await _db.query('planned_trips')).map(_plannedFromRow).toList();

  Future<int> applyRemotePlanned(List<PlannedTrip> remote) async {
    var applied = 0;
    for (final r in remote) {
      final rows = await _db.query('planned_trips', where: 'id = ?', whereArgs: [r.id], limit: 1);
      if (rows.isEmpty || _plannedFromRow(rows.first).updatedAt.isBefore(r.updatedAt)) {
        await _db.insert('planned_trips', _plannedToRow(r), conflictAlgorithm: ConflictAlgorithm.replace);
        applied++;
      }
    }
    return applied;
  }
}
