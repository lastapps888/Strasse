import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';

/// Attractions touristiques par OpenTripMap (clé gratuite requise). https://dev.opentripmap.org/product
class OpenTripMapClient {
  OpenTripMapClient(this.baseUrl, this.apiKey, {Dio? dio, String userAgent = ''})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 15),
              headers: {'Accept': 'application/json', if (userAgent.isNotEmpty) 'User-Agent': userAgent},
            ));

  final String baseUrl;
  final String apiKey;
  final Dio _dio;

  bool get configured => baseUrl.isNotEmpty && apiKey.isNotEmpty;

  Future<List<Poi>> around(GeoPoint c, {int radiusM = 5000, int limit = 40, CancelToken? cancel}) async {
    if (!configured) throw Failure.notConfigured('OpenTripMap', hint: 'Renseignez la clé dans Réglages > Services > Données touristiques.');
    try {
      final r = await _dio.get<Object>(
        '/places/radius',
        queryParameters: {
          'radius': radiusM,
          'lon': c.lon,
          'lat': c.lat,
          'kinds': 'interesting_places',
          'rate': '2',
          'format': 'json',
          'limit': limit,
          'apikey': apiKey,
        },
        cancelToken: cancel,
      );
      return parse(r.data, c);
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }

  /// Convertit la réponse (tableau JSON) ; les entrées sans nom ou sans position sont ignorées.
  static List<Poi> parse(Object? data, GeoPoint from) {
    if (data is! List) throw const Failure(FailureKind.server, 'Réponse OpenTripMap invalide.');
    final out = <Poi>[];
    for (final e in data) {
      try {
        if (e is! Map) continue;
        final name = (e['name'] as String?)?.trim() ?? '';
        final p = e['point'];
        if (name.isEmpty || p is! Map) continue;
        final lat = (p['lat'] as num).toDouble();
        final lon = (p['lon'] as num).toDouble();
        final kinds = (e['kinds'] as String?) ?? '';
        final rate = int.tryParse('${e['rate'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), ''));
        out.add(Poi(
          place: Place(
            id: 'otm:${e['xid']}',
            name: name,
            point: GeoPoint(lat, lon),
            category: kinds.isEmpty ? 'Site touristique' : _label(kinds.split(',').first),
            source: 'opentripmap',
          ),
          kind: PoiKind.tourism,
          source: 'opentripmap',
          popularity: rate != null && rate >= 1 && rate <= 3 ? rate : null,
          distanceMeters: distanceM(from, GeoPoint(lat, lon)),
        ));
      } catch (_) {
        // entrée mal formée : ignorée
      }
    }
    out.sort((a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0));
    return out;
  }

  static String _label(String kind) => kind.replaceAll('_', ' ');
}
