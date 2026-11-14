import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/navigation/speed_limits.dart';

/// Client du moteur d'itinéraires Valhalla (API HTTP `/route`).
class ValhallaClient {
  ValhallaClient(this.baseUrl, {Dio? dio, String userAgent = ''})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 20),
              headers: {'Accept': 'application/json', if (userAgent.isNotEmpty) 'User-Agent': userAgent},
            ));

  final String baseUrl;
  final Dio _dio;

  bool get configured => baseUrl.isNotEmpty;

  /// Calcule un ou plusieurs itinéraires passant par `points` (départ, étapes, arrivée).
  Future<List<RouteOption>> route(
    List<GeoPoint> points,
    TravelMode mode,
    RoutePrefs prefs, {
    int alternates = 2,
    Set<int> viaIndexes = const {},
    CancelToken? cancel,
  }) async {
    if (!configured) throw Failure.notConfigured('Le calcul d\'itinéraires');
    if (points.length < 2) throw const Failure(FailureKind.client, 'Il faut au moins un départ et une arrivée.');
    if (mode == TravelMode.transit) {
      throw const Failure(FailureKind.client, 'Les transports en commun utilisent un autre fournisseur.');
    }
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '/route',
        data: buildRequest(points, mode, prefs, alternates: alternates, viaIndexes: viaIndexes),
        cancelToken: cancel,
      );
      final routes = parseResponse(r.data ?? const {}, mode);
      if (routes.isEmpty) throw const Failure(FailureKind.client, 'Aucun itinéraire trouvé entre ces points.');
      labelRoutes(routes);
      return routes;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Limites de vitesse connues le long d'un itinéraire déjà calculé par ce serveur (`/trace_attributes`, mode edge_walk).
  /// Retourne une carte vide si le serveur ne les fournit pas : l'interface n'affiche alors aucune limite.
  Future<SpeedLimitMap> speedLimits(List<GeoPoint> shape, TravelMode mode, RoutePrefs prefs, {CancelToken? cancel}) async {
    if (!configured || shape.length < 2 || mode == TravelMode.transit) return SpeedLimitMap.empty;
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '/trace_attributes',
        data: {
          'encoded_polyline': encodePolyline(shape, precision: 6),
          'costing': costingFor(mode, prefs),
          'shape_match': 'edge_walk',
          'filters': {
            'attributes': ['edge.speed_limit', 'edge.begin_shape_index', 'edge.end_shape_index'],
            'action': 'include',
          },
        },
        cancelToken: cancel,
      );
      return SpeedLimitMap.fromTraceAttributes(r.data ?? const {});
    } on DioException {
      return SpeedLimitMap.empty;
    }
  }

  static Failure _mapError(DioException e) {
    final d = e.response?.data;
    if (d is Map && d['error_code'] != null) {
      final code = (d['error_code'] as num).toInt();
      switch (code) {
        case 171:
        case 170:
          return Failure(FailureKind.client, 'Aucune route trouvée près du départ ou de l\'arrivée. Choisissez un point plus proche d\'une voie accessible.', code: '$code');
        case 442:
        case 443:
          return Failure(FailureKind.client, 'Aucun itinéraire possible entre ces points avec ces options.', code: '$code');
        case 154:
          return Failure(FailureKind.client, 'Le trajet est trop long pour ce mode de déplacement.', code: '$code');
        case 150:
          return Failure(FailureKind.client, 'Trop de points de passage pour un seul calcul.', code: '$code');
      }
    }
    return Failure.fromDio(e);
  }

  /// Profil Valhalla utilisé : celui du véhicule en voiture, celui du mode sinon.
  static String costingFor(TravelMode mode, RoutePrefs prefs) => mode == TravelMode.car ? prefs.vehicle.costing : mode.costing;

  /// Corps de la requête Valhalla (méthode statique pour être testée sans réseau).
  /// [viaIndexes] : indices des points à traverser sans arrêt (étapes « through » : pas de manœuvre d'arrivée).
  static Map<String, dynamic> buildRequest(
    List<GeoPoint> points,
    TravelMode mode,
    RoutePrefs prefs, {
    int alternates = 2,
    Set<int> viaIndexes = const {},
  }) {
    final options = <String, dynamic>{};
    final shortest = prefs.criterion == RouteCriterion.shortest;
    final economic = prefs.criterion == RouteCriterion.economic;
    final touristic = prefs.criterion == RouteCriterion.touristic;
    final costing = costingFor(mode, prefs);
    switch (mode) {
      case TravelMode.car:
        final v = prefs.vehicle;
        final auto = <String, dynamic>{};
        // Péages et autoroutes : les choix explicites de l'utilisateur priment sur le style d'itinéraire.
        if (prefs.avoidTolls || ((economic || touristic) && prefs.customTollUse == null)) {
          auto['use_tolls'] = 0.0;
        } else if (prefs.customTollUse != null) {
          auto['use_tolls'] = prefs.customTollUse;
        }
        if (prefs.avoidHighways || v == VehicleType.microcar || touristic) {
          auto['use_highways'] = 0.0;
        } else if (prefs.customHighwayUse != null) {
          auto['use_highways'] = prefs.customHighwayUse;
        } else if (economic) {
          auto['use_highways'] = 0.3;
        }
        if (prefs.avoidFerries) auto['use_ferry'] = 0.0;
        if (shortest) auto['shortest'] = true;
        // Économique : vitesse modérée (moins de carburant) et préférence pour la distance. Touristique : routes secondaires.
        if (economic) {
          auto['top_speed'] = 110;
          auto['use_distance'] = 0.5;
        }
        if (touristic) auto['use_distance'] = 0.3;
        // Voiture sans permis : vitesse limitée à 45 km/h, ce qui change aussi l'heure d'arrivée estimée.
        if (v == VehicleType.microcar) auto['top_speed'] = 45;
        if (v == VehicleType.van) {
          auto..['height'] = 2.7..['width'] = 2.1..['length'] = 6.0..['weight'] = 3.5;
        }
        if (v == VehicleType.truck) {
          auto
            ..['height'] = prefs.truckHeightM
            ..['width'] = prefs.truckWidthM
            ..['length'] = prefs.truckLengthM
            ..['weight'] = prefs.truckWeightT;
        }
        if (v == VehicleType.motorcycle) auto['use_trails'] = touristic ? 0.3 : 0.0;
        if (auto.isNotEmpty) options[costing] = auto;
      case TravelMode.bike:
        final bike = <String, dynamic>{
          'bicycle_type': prefs.bikeType.valhalla,
          'use_roads': (prefs.preferCycleways || touristic) ? 0.1 : 0.6,
          'use_hills': (prefs.avoidHills || economic) ? 0.0 : 0.5,
          'avoid_bad_surfaces': switch (prefs.bikeType) {
            BikeType.road => 0.8,
            BikeType.city => 0.6,
            BikeType.hybrid => 0.5,
            BikeType.cross => 0.2,
            BikeType.mountain => 0.1,
          },
        };
        if (prefs.avoidFerries) bike['use_ferry'] = 0.0;
        if (shortest) bike['shortest'] = true;
        options['bicycle'] = bike;
      case TravelMode.walk:
        final walk = <String, dynamic>{
          'walking_speed': prefs.walkSpeedKmh,
          'use_hills': (prefs.avoidHills || economic) ? 0.0 : 0.5,
        };
        if (touristic) {
          walk
            ..['use_living_streets'] = 1.0
            ..['walkway_factor'] = 0.8
            ..['alley_factor'] = 2.0;
        }
        if (prefs.avoidStairs) walk['step_penalty'] = 600;
        if (prefs.avoidFerries) walk['use_ferry'] = 0.0;
        if (shortest) walk['shortest'] = true;
        options['pedestrian'] = walk;
      case TravelMode.transit:
        break;
    }
    return {
      'locations': [
        for (var i = 0; i < points.length; i++) {'lat': points[i].lat, 'lon': points[i].lon, 'type': viaIndexes.contains(i) ? 'through' : 'break'},
      ],
      'costing': costing,
      if (options.isNotEmpty) 'costing_options': options,
      'directions_options': {'language': Translator.language.routingTag, 'units': 'kilometers'},
      if (points.length == 2 && alternates > 0) 'alternates': alternates,
    };
  }

  /// Transforme la réponse Valhalla (trajet principal + alternatives) en [RouteOption].
  static List<RouteOption> parseResponse(Map<String, dynamic> json, TravelMode mode) {
    final trips = <Map<String, dynamic>>[];
    if (json['trip'] is Map) trips.add(Map<String, dynamic>.from(json['trip'] as Map));
    for (final a in (json['alternates'] as List?) ?? const []) {
      if (a is Map && a['trip'] is Map) trips.add(Map<String, dynamic>.from(a['trip'] as Map));
    }
    final out = <RouteOption>[];
    for (var i = 0; i < trips.length; i++) {
      final r = _parseTrip(trips[i], mode, 'r$i');
      if (r != null) out.add(r);
    }
    return out;
  }

  static RouteOption? _parseTrip(Map<String, dynamic> trip, TravelMode mode, String id) {
    final legs = (trip['legs'] as List?) ?? const [];
    if (legs.isEmpty) return null;
    final shape = <GeoPoint>[];
    final maneuvers = <Maneuver>[];
    final waypointIdx = <int>[];
    for (var li = 0; li < legs.length; li++) {
      final leg = Map<String, dynamic>.from(legs[li] as Map);
      final pts = decodePolyline(leg['shape'] as String, precision: 6);
      if (pts.isEmpty) continue;
      final isLast = li == legs.length - 1;
      // Le dernier point d'un tronçon est le premier du suivant : on ne le répète pas.
      final offset = shape.isEmpty ? 0 : shape.length - 1;
      shape.addAll(shape.isEmpty ? pts : pts.skip(1));
      final ms = (leg['maneuvers'] as List?) ?? const [];
      for (var mi = 0; mi < ms.length; mi++) {
        final m = Map<String, dynamic>.from(ms[mi] as Map);
        final type = (m['type'] as num?)?.toInt() ?? 0;
        final isArrival = type == 4 || type == 5 || type == 6;
        final isDeparture = type == 1 || type == 2 || type == 3;
        // Le départ d'un tronçon intermédiaire n'est pas une manœuvre à annoncer.
        if (li > 0 && mi == 0 && isDeparture) continue;
        final begin = ((m['begin_shape_index'] as num?)?.toInt() ?? 0) + offset;
        if (isArrival && !isLast) waypointIdx.add(begin);
        maneuvers.add(Maneuver(
          instruction: (m['instruction'] as String?) ?? '',
          verbalPre: m['verbal_pre_transition_instruction'] as String?,
          verbalPost: m['verbal_post_transition_instruction'] as String?,
          verbalAlert: m['verbal_transition_alert_instruction'] as String?,
          type: type,
          distanceM: ((m['length'] as num?)?.toDouble() ?? 0) * 1000,
          durationS: (m['time'] as num?)?.toDouble() ?? 0,
          beginIndex: begin,
          streetNames: ((m['street_names'] as List?) ?? const []).map((e) => '$e').toList(),
          isFinal: isArrival && isLast,
          isWaypoint: isArrival && !isLast,
        ));
      }
    }
    if (shape.length < 2) return null;
    final s = Map<String, dynamic>.from((trip['summary'] as Map?) ?? const {});
    return RouteOption(
      id: id,
      mode: mode,
      shape: shape,
      distanceM: ((s['length'] as num?)?.toDouble() ?? 0) * 1000,
      durationS: (s['time'] as num?)?.toDouble() ?? 0,
      hasToll: s['has_toll'] == true,
      hasHighway: s['has_highway'] == true,
      hasFerry: s['has_ferry'] == true,
      maneuvers: maneuvers,
      waypointIndices: waypointIdx,
    );
  }

  /// Ajoute les libellés « Plus rapide », « Plus court », « Sans péage » en comparant les alternatives.
  static void labelRoutes(List<RouteOption> routes) {
    if (routes.isEmpty) return;
    var fastest = routes.first;
    var shortest = routes.first;
    for (final r in routes) {
      if (r.durationS < fastest.durationS) fastest = r;
      if (r.distanceM < shortest.distanceM) shortest = r;
    }
    fastest.label = 'Plus rapide';
    if (routes.length > 1) {
      if (!identical(shortest, fastest)) shortest.label ??= 'Plus court';
      final anyToll = routes.any((r) => r.hasToll);
      if (anyToll) {
        for (final r in routes) {
          if (!r.hasToll && r.label == null) r.label = 'Sans péage';
        }
      }
      for (final r in routes) {
        r.label ??= 'Alternative';
      }
    }
  }
}
