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

  @override
  Future<List<TransitItinerary>> plan(GeoPoint from, GeoPoint to, {DateTime? departAt}) async {
    try {
      final r = await _gate.run(() => _dio.get<Map<String, dynamic>>('/api/v1/plan', queryParameters: {
            'fromPlace': '${from.lat},${from.lon}',
            'toPlace': '${to.lat},${to.lon}',
            'time': _iso(departAt ?? DateTime.now()),
            'arriveBy': false,
            'numItineraries': 5,
            'language': language,
          }));
      final list = parsePlan(r.data ?? const {});
      if (list.isEmpty) {
        throw const Failure(FailureKind.client, 'Aucun trajet en transports en commun trouvé pour cet horaire. Essayez une autre heure ou un autre point.', code: 'no_transit');
      }
      return list;
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }

  /// Arrêts dans une zone (utilisée pour la couche « Transports en commun »).
  Future<List<TransitStop>> stopsIn(GeoBounds b, {CancelToken? cancel}) async {
    final key = '${b.south.toStringAsFixed(3)},${b.west.toStringAsFixed(3)},${b.north.toStringAsFixed(3)},${b.east.toStringAsFixed(3)}';
    final cached = _stopCache.get(key);
    if (cached != null) return cached;
    try {
      final r = await _gate.run(() => _dio.get<Object>('/api/v1/map/stops', queryParameters: {
            'min': '${b.south},${b.west}',
            'max': '${b.north},${b.east}',
          }, cancelToken: cancel));
      final stops = parseStops(r.data);
      _stopCache.put(key, stops);
      return stops;
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }

  /// Prochains passages à un arrêt.
  Future<List<StopDeparture>> departures(String stopId, {DateTime? at, int count = 14, CancelToken? cancel}) async {
    try {
      final r = await _gate.run(() => _dio.get<Map<String, dynamic>>('/api/v1/stoptimes', queryParameters: {
            'stopId': stopId,
            'n': count,
            'time': _iso(at ?? DateTime.now()),
            'language': language,
          }, cancelToken: cancel));
      return parseDepartures(r.data ?? const {});
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }

  // ---------------------------------------------------------------- Analyse (statique, testable sans réseau)

  static DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

  static List<TransitItinerary> parsePlan(Map<String, dynamic> json) {
    final out = <TransitItinerary>[];
    for (final raw in (json['itineraries'] as List?) ?? const []) {
      try {
        final it = Map<String, dynamic>.from(raw as Map);
        final legs = <TransitLeg>[];
        for (final l in (it['legs'] as List?) ?? const []) {
          final leg = Map<String, dynamic>.from(l as Map);
          final from = Map<String, dynamic>.from(leg['from'] as Map);
          final to = Map<String, dynamic>.from(leg['to'] as Map);
          final geom = leg['legGeometry'] as Map?;
          final start = _time(leg['startTime']) ?? _time(from['departure']);
          final end = _time(leg['endTime']) ?? _time(to['arrival']);
          if (start == null || end == null) continue;
          legs.add(TransitLeg(
            mode: (leg['mode'] as String?) ?? 'WALK',
            from: GeoPoint((from['lat'] as num).toDouble(), (from['lon'] as num).toDouble()),
            to: GeoPoint((to['lat'] as num).toDouble(), (to['lon'] as num).toDouble()),
            fromName: (from['name'] as String?) ?? '',
            toName: (to['name'] as String?) ?? '',
            start: start,
            end: end,
            distanceM: (leg['distance'] as num?)?.toDouble() ?? 0,
            shape: geom == null ? const [] : decodePolyline(geom['points'] as String, precision: (geom['precision'] as num?)?.toInt() ?? 6),
            routeName: (leg['routeShortName'] as String?) ?? (leg['routeLongName'] as String?),
            headsign: leg['headsign'] as String?,
            agency: leg['agencyName'] as String?,
          ));
        }
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
        ));
      } catch (_) {
        // passage mal formé : ignoré
      }
    }
    out.sort((a, b) => a.best.compareTo(b.best));
    return out;
  }
}
