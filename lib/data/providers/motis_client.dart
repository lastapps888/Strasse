import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/geo_backend.dart';
import 'package:strasse/data/providers/otp_client.dart';
import 'package:strasse/domain/domain.dart';

/// Client MOTIS 2 (API `/api/v1`), le moteur derrière Transitous (https://transitous.org).
///
/// Transitous agrège les flux GTFS ouverts, dont ceux de transport.data.gouv.fr : métropoles, réseaux urbains,
/// cars régionaux, TER. La couverture dépend de ce que chaque opérateur publie. Le service est communautaire,
/// sans clé, à usage raisonnable : Strasse s'identifie par un User-Agent et met les réponses en cache.
class MotisTransitRouter implements TransitRouter {
  MotisTransitRouter(this.baseUrl, {Dio? dio, String userAgent = '', this.language = 'fr'})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 25),
              headers: {'Accept': 'application/json', if (userAgent.isNotEmpty) 'User-Agent': userAgent},
            ));

  final String baseUrl;
  final String language;
  final Dio _dio;

  final TtlCache<List<TransitStop>> _stopCache = TtlCache(ttl: const Duration(minutes: 20), maxEntries: 40);
  static final RateGate _gate = RateGate(const Duration(milliseconds: 250));

  @override
  bool get available => baseUrl.isNotEmpty;

  @override
  String get unavailableReason => 'Le serveur de transports en commun n\'est pas configuré.';

  static String _iso(DateTime t) => t.toUtc().toIso8601String();

  /// Versions d'API essayées, de la plus ancienne connue du serveur public à la plus récente. L'API MOTIS change de
  /// numéro de version par endpoint (plan/stoptimes/trip : v5 puis v6 ; map/stops : v1…). La première qui répond
  /// (autrement qu'en 404/400 « route inconnue ») est mémorisée pour la session.
  static const Map<String, List<int>> _versions = {
    'plan': [5, 6, 4],
    'stoptimes': [5, 6, 4],
    'trip': [5, 6, 4],
    'map/trips': [5, 6, 4],
    'map/stops': [1, 2],
  };
  static final Map<String, int> _working = {};

  Future<Response<T>> _get<T>(String endpoint, Map<String, dynamic> query, {CancelToken? cancel}) async {
    final all = _versions[endpoint] ?? const [1];
    final known = _working[endpoint];
    final order = [if (known != null) known, for (final v in all) if (v != known) v];
    DioException? last;
    for (final v in order) {
      try {
        final r = await _gate.run(() => _dio.get<T>('/api/v$v/$endpoint', queryParameters: query, cancelToken: cancel));
        _working[endpoint] = v;
        return r;
      } on DioException catch (e) {
        last = e;
        final code = e.response?.statusCode;
        // 404 : version absente du serveur ; 400/422 : paramètre inconnu de cette version → on tente la suivante.
        if (code == 404 || code == 400 || code == 422 || code == 410) continue;
        throw Failure.fromDio(e);
      }
    }
    throw Failure.fromDio(last!);
  }

  @override
  Future<List<TransitItinerary>> plan(GeoPoint from, GeoPoint to, {DateTime? departAt, bool arriveBy = false}) async {
    final r = await _get<Map<String, dynamic>>('plan', {
      'fromPlace': '${from.lat},${from.lon}',
      'toPlace': '${to.lat},${to.lon}',
      'time': _iso(departAt ?? DateTime.now()),
      'arriveBy': arriveBy,
      'numItineraries': 6,
      'detailedTransfers': false,
      'language': language,
    });
    final list = parsePlan(r.data ?? const {});
    if (list.isEmpty) {
      throw const Failure(FailureKind.client, 'Aucun trajet en transports en commun trouvé pour cet horaire. Essayez une autre heure ou un autre point.', code: 'no_transit');
    }
    return list;
  }

  /// Arrêts dans une zone (utilisée pour la couche « Transports en commun »).
  Future<List<TransitStop>> stopsIn(GeoBounds b, {CancelToken? cancel}) async {
    final key = '${b.south.toStringAsFixed(3)},${b.west.toStringAsFixed(3)},${b.north.toStringAsFixed(3)},${b.east.toStringAsFixed(3)}';
    final cached = _stopCache.get(key);
    if (cached != null) return cached;
    final r = await _get<Object>('map/stops', {
      'min': '${b.south},${b.west}',
      'max': '${b.north},${b.east}',
    }, cancel: cancel);
    final stops = parseStops(r.data);
    _stopCache.put(key, stops);
    return stops;
  }

  /// Prochains passages à un arrêt.
  Future<List<StopDeparture>> departures(String stopId, {DateTime? at, int count = 20, CancelToken? cancel}) async {
    final r = await _get<Map<String, dynamic>>('stoptimes', {
      'stopId': stopId,
      'n': count,
      'time': _iso(at ?? DateTime.now()),
      'language': language,
    }, cancel: cancel);
    return parseDepartures(r.data ?? const {});
  }

  /// Parcours complet d'un voyage (tous ses arrêts avec horaires) à partir de son identifiant.
  Future<TransitLeg?> tripDetail(String tripId, {CancelToken? cancel}) async {
    final r = await _get<Map<String, dynamic>>('trip', {'tripId': tripId, 'language': language}, cancel: cancel);
    final legs = parseLegs((r.data ?? const {})['legs']);
    for (final l in legs) {
      if (!l.isWalk) return l;
    }
    return null;
  }

  /// Lignes passant dans une zone (tracé + couleur officielle), à partir des voyages en cours. Sert de repli quand
  /// les relations OpenStreetMap ne sont pas disponibles.
  Future<List<TransitLine>> linesIn(GeoBounds b, {int zoom = 13, CancelToken? cancel}) async {
    final now = DateTime.now();
    final r = await _get<Object>('map/trips', {
      'zoom': zoom,
      'min': '${b.south},${b.west}',
      'max': '${b.north},${b.east}',
      'startTime': _iso(now.subtract(const Duration(minutes: 10))),
      'endTime': _iso(now.add(const Duration(minutes: 20))),
    }, cancel: cancel);
    return parseMapTrips(r.data);
  }

  // ---------------------------------------------------------------- Analyse (statique, testable sans réseau)

  static DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

  static String? _color(Object? v) {
    if (v is! String) return null;
    final c = v.trim().replaceFirst('#', '');
    return RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(c) ? '#${c.toLowerCase()}' : null;
  }

  static GeoPoint? _pt(Map m) {
    final la = m['lat'], lo = m['lon'];
    return la is num && lo is num ? GeoPoint(la.toDouble(), lo.toDouble()) : null;
  }

  static TransitCall? _call(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final p = _pt(m);
    if (p == null) return null;
    return TransitCall(
      name: (m['name'] as String?) ?? '',
      point: p,
      stopId: (m['stopId'] ?? m['id'])?.toString(),
      arrival: _time(m['arrival']),
      departure: _time(m['departure']),
      scheduledArrival: _time(m['scheduledArrival']),
      scheduledDeparture: _time(m['scheduledDeparture']),
      track: (m['track'] ?? m['scheduledTrack'])?.toString(),
      cancelled: m['cancelled'] == true,
    );
  }

  static List<TransitLeg> parseLegs(Object? rawLegs) {
    final legs = <TransitLeg>[];
    for (final l in (rawLegs as List?) ?? const []) {
      try {
        final leg = Map<String, dynamic>.from(l as Map);
        final from = Map<String, dynamic>.from(leg['from'] as Map);
        final to = Map<String, dynamic>.from(leg['to'] as Map);
        final geom = leg['legGeometry'] as Map?;
        final start = _time(leg['startTime']) ?? _time(from['departure']);
        final end = _time(leg['endTime']) ?? _time(to['arrival']);
        final fp = _pt(from), tp = _pt(to);
        if (start == null || end == null || fp == null || tp == null) continue;
        legs.add(TransitLeg(
          mode: ((leg['mode'] as String?) ?? 'WALK').toUpperCase(),
          from: fp,
          to: tp,
          fromName: (from['name'] as String?) ?? '',
          toName: (to['name'] as String?) ?? '',
          start: start,
          end: end,
          distanceM: (leg['distance'] as num?)?.toDouble() ?? 0,
          shape: geom == null || geom['points'] is! String
              ? [fp, tp]
              : decodePolyline(geom['points'] as String, precision: (geom['precision'] as num?)?.toInt() ?? 6),
          routeName: (leg['routeShortName'] as String?) ?? (leg['displayName'] as String?) ?? (leg['routeLongName'] as String?),
          headsign: leg['headsign'] as String?,
          agency: leg['agencyName'] as String?,
          routeColor: _color(leg['routeColor']),
          routeTextColor: _color(leg['routeTextColor']),
          realTime: leg['realTime'] == true,
          cancelled: leg['cancelled'] == true,
          tripId: leg['tripId'] as String?,
          fromStopId: from['stopId']?.toString(),
          toStopId: to['stopId']?.toString(),
          fromTrack: (from['track'] ?? from['scheduledTrack'])?.toString(),
          toTrack: (to['track'] ?? to['scheduledTrack'])?.toString(),
          intermediateStops: [for (final c in (leg['intermediateStops'] as List?) ?? const []) ?_call(c)],
          scheduledStart: _time(leg['scheduledStartTime']) ?? _time(from['scheduledDeparture']),
          scheduledEnd: _time(leg['scheduledEndTime']) ?? _time(to['scheduledArrival']),
        ));
      } catch (_) {
        // tronçon mal formé : ignoré
      }
    }
    return legs;
  }

  static List<TransitItinerary> parsePlan(Map<String, dynamic> json) {
    final out = <TransitItinerary>[];
    for (final raw in (json['itineraries'] as List?) ?? const []) {
      try {
        final it = Map<String, dynamic>.from(raw as Map);
        final legs = parseLegs(it['legs']);
        if (legs.isEmpty) continue;
        out.add(TransitItinerary(
          start: _time(it['startTime']) ?? legs.first.start,
          end: _time(it['endTime']) ?? legs.last.end,
          legs: legs,
          transfers: (it['transfers'] as num?)?.toInt() ?? 0,
          walkDistanceM: legs.where((l) => l.isWalk).fold(0.0, (a, l) => a + l.distanceM),
        ));
      } catch (_) {
        // itinéraire mal formé : ignoré
      }
    }
    return out;
  }

  /// Réponse de `map/trips` : segments de voyages avec tracé encodé et couleur de ligne.
  static List<TransitLine> parseMapTrips(Object? data) {
    final list = data is List ? data : (data is Map ? (data['segments'] ?? data['trips']) as List? : null) ?? const [];
    final byRoute = <String, ({String mode, String ref, String? color, String? agency, List<List<GeoPoint>> shapes})>{};
    for (final raw in list) {
      try {
        final m = Map<String, dynamic>.from(raw as Map);
        final poly = m['polyline'];
        final enc = poly is String ? poly : (poly is Map ? poly['points'] as String? : null);
        if (enc == null || enc.isEmpty) continue;
        final prec = poly is Map ? (poly['precision'] as num?)?.toInt() ?? 6 : 6;
        final pts = decodePolyline(enc, precision: prec);
        if (pts.length < 2) continue;
        final trips = (m['trips'] as List?) ?? const [];
        final first = trips.isNotEmpty && trips.first is Map ? Map<String, dynamic>.from(trips.first as Map) : const <String, dynamic>{};
        final ref = ((first['routeShortName'] ?? first['displayName'] ?? m['routeShortName']) ?? '').toString();
        final mode = ((m['mode'] ?? first['mode']) ?? 'BUS').toString().toLowerCase();
        final key = '$mode|$ref|${_color(m['routeColor']) ?? ''}';
        final cur = byRoute[key];
        if (cur == null) {
          byRoute[key] = (mode: mode, ref: ref, color: _color(m['routeColor']), agency: (first['agencyName'] ?? m['agencyName'])?.toString(), shapes: [pts]);
        } else {
          cur.shapes.add(pts);
        }
      } catch (_) {
        // segment mal formé : ignoré
      }
    }
    var n = 0;
    return [
      for (final e in byRoute.entries)
        TransitLine(id: 'motis/${n++}', mode: e.value.mode, ref: e.value.ref, colorHex: e.value.color, operator: e.value.agency, shapes: e.value.shapes),
    ];
  }

  static List<TransitStop> parseStops(Object? data) {
    final list = data is List ? data : (data is Map ? data['stops'] as List? : null) ?? const [];
    final out = <TransitStop>[];
    for (final raw in list) {
      try {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = (m['stopId'] ?? m['id'])?.toString();
        if (id == null || id.isEmpty) continue;
        out.add(TransitStop(
          id: id,
          name: (m['name'] as String?) ?? 'Arrêt',
          point: GeoPoint((m['lat'] as num).toDouble(), (m['lon'] as num).toDouble()),
          modes: [for (final x in (m['modes'] as List?) ?? const []) x.toString()],
        ));
      } catch (_) {
        // arrêt mal formé : ignoré
      }
    }
    return out;
  }

  static List<StopDeparture> parseDepartures(Map<String, dynamic> json) {
    final out = <StopDeparture>[];
    for (final raw in (json['stopTimes'] as List?) ?? const []) {
      try {
        final m = Map<String, dynamic>.from(raw as Map);
        final place = Map<String, dynamic>.from((m['place'] as Map?) ?? const {});
        final scheduled = _time(place['scheduledDeparture']) ?? _time(place['scheduledArrival']) ?? _time(place['departure']) ?? _time(place['arrival']);
        if (scheduled == null) continue;
        final actual = _time(place['departure']) ?? _time(place['arrival']);
        final realTime = m['realTime'] == true;
        out.add(StopDeparture(
          routeName: (m['routeShortName'] as String?) ?? (m['displayName'] as String?) ?? (m['routeLongName'] as String?) ?? '',
          mode: (m['mode'] as String?) ?? 'BUS',
          headsign: (m['headsign'] as String?) ?? ((m['tripTo'] as Map?)?['name'] as String?),
          scheduled: scheduled,
          expected: realTime ? actual : null,
          agency: m['agencyName'] as String?,
          cancelled: m['cancelled'] == true || place['cancelled'] == true,
          routeColor: _color(m['routeColor']),
          routeTextColor: _color(m['routeTextColor']),
          tripId: m['tripId'] as String?,
          track: (place['track'] ?? place['scheduledTrack'])?.toString(),
        ));
      } catch (_) {
        // passage mal formé : ignoré
      }
    }
    out.sort((a, b) => a.best.compareTo(b.best));
    return out;
  }
}
