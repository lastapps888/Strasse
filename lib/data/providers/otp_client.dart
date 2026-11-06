import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';

/// Fournisseur de transports en commun : interface indépendante du moteur.
abstract class TransitRouter {
  bool get available;
  String get unavailableReason;
  Future<List<TransitItinerary>> plan(GeoPoint from, GeoPoint to, {DateTime? departAt});
}

/// Aucune source de données configurée : on le dit clairement, sans inventer ni horaires ni correspondances.
class UnavailableTransitRouter implements TransitRouter {
  const UnavailableTransitRouter();

  @override
  bool get available => false;

  @override
  String get unavailableReason =>
      'Aucune source de données de transports en commun (GTFS) n\'est configurée. '
      'Renseignez un serveur OpenTripPlanner dans Réglages > Services pour activer cette fonction.';

  @override
  Future<List<TransitItinerary>> plan(GeoPoint from, GeoPoint to, {DateTime? departAt}) async =>
      throw Failure(FailureKind.notConfigured, unavailableReason, code: 'transit_unavailable');
}

/// Client OpenTripPlanner (API REST `/otp/routers/default/plan`), alimenté par vos flux GTFS.
class OtpTransitRouter implements TransitRouter {
  OtpTransitRouter(this.baseUrl, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 20),
            ));

  final String baseUrl;
  final Dio _dio;

  @override
  bool get available => baseUrl.isNotEmpty;

  @override
  String get unavailableReason => 'Le serveur de transports en commun n\'est pas configuré.';

  @override
  Future<List<TransitItinerary>> plan(GeoPoint from, GeoPoint to, {DateTime? departAt}) async {
    final t = departAt ?? DateTime.now();
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '/otp/routers/default/plan',
        queryParameters: {
          'fromPlace': '${from.lat},${from.lon}',
          'toPlace': '${to.lat},${to.lon}',
          'mode': 'TRANSIT,WALK',
          'date': '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}',
          'time': formatClock(t),
          'numItineraries': 4,
          'locale': 'fr',
        },
      );
      final data = r.data ?? const {};
      if (data['error'] != null) {
        final msg = (data['error'] as Map?)?['msg']?.toString();
        throw Failure(FailureKind.client, msg ?? 'Aucun trajet en transports en commun trouvé.');
      }
      return parse(data);
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }

  /// Analyse la réponse OTP (méthode statique pour être testée sans réseau).
  static List<TransitItinerary> parse(Map<String, dynamic> json) {
    final its = ((json['plan'] as Map?)?['itineraries'] as List?) ?? const [];
    DateTime ms(Object? v) => DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
    final out = <TransitItinerary>[];
    for (final raw in its) {
      final it = Map<String, dynamic>.from(raw as Map);
      final legs = <TransitLeg>[];
      for (final l in (it['legs'] as List?) ?? const []) {
        final leg = Map<String, dynamic>.from(l as Map);
        final from = Map<String, dynamic>.from(leg['from'] as Map);
        final to = Map<String, dynamic>.from(leg['to'] as Map);
        final geom = (leg['legGeometry'] as Map?)?['points'] as String?;
        legs.add(TransitLeg(
          mode: (leg['mode'] as String?) ?? 'WALK',
          from: GeoPoint((from['lat'] as num).toDouble(), (from['lon'] as num).toDouble()),
          to: GeoPoint((to['lat'] as num).toDouble(), (to['lon'] as num).toDouble()),
          fromName: (from['name'] as String?) ?? '',
          toName: (to['name'] as String?) ?? '',
          start: ms(leg['startTime']),
          end: ms(leg['endTime']),
          distanceM: (leg['distance'] as num?)?.toDouble() ?? 0,
          shape: geom == null ? const [] : decodePolyline(geom, precision: 5),
          routeName: (leg['routeShortName'] as String?) ?? (leg['route'] as String?),
          headsign: leg['headsign'] as String?,
          agency: leg['agencyName'] as String?,
        ));
      }
      if (legs.isEmpty) continue;
      out.add(TransitItinerary(
        start: ms(it['startTime']),
        end: ms(it['endTime']),
        legs: legs,
        transfers: (it['transfers'] as num?)?.toInt() ?? 0,
        walkDistanceM: (it['walkDistance'] as num?)?.toDouble() ?? 0,
      ));
    }
    return out;
  }
}
