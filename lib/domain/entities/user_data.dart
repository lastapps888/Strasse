import 'package:strasse/core/core.dart';
import 'routing.dart';
import 'place.dart';

enum FavoriteKind { home, work, place }

/// Lieu enregistré par l'utilisateur. `updatedAt` et `deleted` servent à la synchronisation facultative.
class Favorite {
  const Favorite({
    required this.id,
    required this.name,
    required this.point,
    required this.updatedAt,
    this.address,
    this.category,
    this.kind = FavoriteKind.place,
    this.collectionId,
    this.note,
    this.position = 0,
    this.deleted = false,
  });

  final String id;
  final String name;
  final GeoPoint point;
  final DateTime updatedAt;
  final String? address;
  final String? category;
  final FavoriteKind kind;
  final String? collectionId;
  final String? note;
  final int position;
  final bool deleted;

  Favorite copyWith({
    String? name,
    String? address,
    String? category,
    FavoriteKind? kind,
    String? collectionId,
    bool clearCollection = false,
    String? note,
    int? position,
    bool? deleted,
    DateTime? updatedAt,
  }) =>
      Favorite(
        id: id,
        name: name ?? this.name,
        point: point,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
        address: address ?? this.address,
        category: category ?? this.category,
        kind: kind ?? this.kind,
        collectionId: clearCollection ? null : (collectionId ?? this.collectionId),
        note: note ?? this.note,
        position: position ?? this.position,
        deleted: deleted ?? this.deleted,
      );

  /// Forme échangée avec le serveur de synchronisation (contrat d'API).
  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'name': name,
        'address': address,
        'category': category,
        'lat': point.lat,
        'lon': point.lon,
        'kind': kind.name,
        'collectionId': collectionId,
        'note': note,
        'position': position,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deleted': deleted,
      };

  factory Favorite.fromSyncJson(Map<String, dynamic> j) => Favorite(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        address: j['address'] as String?,
        category: j['category'] as String?,
        point: GeoPoint((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        kind: FavoriteKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => FavoriteKind.place),
        collectionId: j['collectionId'] as String?,
        note: j['note'] as String?,
        position: (j['position'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.parse(j['updatedAt'] as String).toUtc(),
        deleted: j['deleted'] == true,
      );
}

class PlaceCollection {
  const PlaceCollection({
    required this.id,
    required this.name,
    required this.updatedAt,
    this.description,
    this.position = 0,
    this.deleted = false,
  });

  final String id;
  final String name;
  final String? description;
  final int position;
  final DateTime updatedAt;
  final bool deleted;

  PlaceCollection copyWith({String? name, String? description, int? position, bool? deleted}) => PlaceCollection(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        position: position ?? this.position,
        updatedAt: DateTime.now().toUtc(),
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'name': name,
        'description': description,
        'position': position,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deleted': deleted,
      };

  factory PlaceCollection.fromSyncJson(Map<String, dynamic> j) => PlaceCollection(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        description: j['description'] as String?,
        position: (j['position'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.parse(j['updatedAt'] as String).toUtc(),
        deleted: j['deleted'] == true,
      );
}

/// Trajet effectué, enregistré localement si l'historique est activé.
class TripRecord {
  const TripRecord({
    required this.id,
    required this.startedAt,
    required this.fromName,
    required this.from,
    required this.toName,
    required this.to,
    required this.mode,
    required this.distanceM,
    required this.durationS,
    required this.shape,
    this.completed = true,
  });

  final String id;
  final DateTime startedAt;
  final String fromName;
  final GeoPoint from;
  final String toName;
  final GeoPoint to;
  final TravelMode mode;
  final double distanceM;
  final double durationS;

  /// Polyligne encodée (précision 6).
  final String shape;
  final bool completed;
}

class Waypoint {
  const Waypoint({required this.name, required this.point});

  final String name;
  final GeoPoint point;

  Map<String, dynamic> toJson() => {'name': name, 'lat': point.lat, 'lon': point.lon};

  factory Waypoint.fromJson(Map<String, dynamic> j) =>
      Waypoint(name: (j['name'] as String?) ?? '', point: GeoPoint((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()));
}

/// Voyage planifié : plusieurs étapes, un mode et des préférences.
class PlannedTrip {
  const PlannedTrip({
    required this.id,
    required this.name,
    required this.mode,
    required this.waypoints,
    required this.prefs,
    required this.updatedAt,
    this.deleted = false,
  });

  final String id;
  final String name;
  final TravelMode mode;
  final List<Waypoint> waypoints;
  final RoutePrefs prefs;
  final DateTime updatedAt;
  final bool deleted;

  PlannedTrip copyWith({String? name, TravelMode? mode, List<Waypoint>? waypoints, RoutePrefs? prefs, bool? deleted}) => PlannedTrip(
        id: id,
        name: name ?? this.name,
        mode: mode ?? this.mode,
        waypoints: waypoints ?? this.waypoints,
        prefs: prefs ?? this.prefs,
        updatedAt: DateTime.now().toUtc(),
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'name': name,
        'mode': mode.name,
        'waypoints': waypoints.map((w) => w.toJson()).toList(),
        'options': prefs.toJson(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deleted': deleted,
      };

  factory PlannedTrip.fromSyncJson(Map<String, dynamic> j) => PlannedTrip(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        mode: TravelMode.fromName(j['mode'] as String?),
        waypoints: ((j['waypoints'] as List?) ?? const [])
            .map((w) => Waypoint.fromJson(Map<String, dynamic>.from(w as Map)))
            .toList(),
        prefs: RoutePrefs.fromJson(j['options'] is Map ? Map<String, dynamic>.from(j['options'] as Map) : null),
        updatedAt: DateTime.parse(j['updatedAt'] as String).toUtc(),
        deleted: j['deleted'] == true,
      );
}

extension FavoriteToPlace on Favorite {
  /// Lieu correspondant, utilisable pour un itinéraire ou l'affichage sur la carte.
  Place toPlace() => Place(
        id: 'favorite:$id',
        name: name,
        point: point,
        address: address,
        category: category,
        source: 'favorite',
      );
}
