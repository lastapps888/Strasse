import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/geo_backend.dart';
import 'package:strasse/domain/domain.dart';

/// Client Photon (https://github.com/komoot/photon) : recherche progressive avec tolérance aux fautes, géocodage inverse.
class PhotonClient implements GeoBackend {
  PhotonClient(this.baseUrl, {Dio? dio, String userAgent = '', String language = 'fr'})
      : lang = supportedLang(language),
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'Accept': 'application/json', if (userAgent.isNotEmpty) 'User-Agent': userAgent},
            ));

  final String baseUrl;
  final Dio _dio;

  /// Photon ne connaît que quelques langues (default, en, de, fr, it) et répond 400 pour les autres.
  final String lang;
  static String supportedLang(String l) => const {'en', 'de', 'fr', 'it'}.contains(l) ? l : 'default';

  final TtlCache<List<Place>> _cache = TtlCache(ttl: const Duration(minutes: 10));

  @override
  bool get allowsAutocomplete => true;

  @override
  Future<List<Place>> search(
    String query, {
    GeoPoint? near,
    GeoBounds? bounds,
    bool bounded = false,
    int limit = 8,
    CancelToken? cancel,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final bias = near ?? bounds?.center;
    final key = '$lang|$q|${bias?.lat.toStringAsFixed(2)},${bias?.lon.toStringAsFixed(2)}|$limit';
    final cached = _cache.get(key);
    if (cached != null) return cached;
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '/api',
        queryParameters: {
          'q': q,
          'limit': limit,
          'lang': lang,
          if (bias != null) 'lat': bias.lat,
          if (bias != null) 'lon': bias.lon,
        },
        cancelToken: cancel,
      );
      final places = parseFeatures(r.data);
      _cache.put(key, places);
      return places;
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }

  @override
  Future<Place?> reverse(GeoPoint p, {CancelToken? cancel}) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '/reverse',
        queryParameters: {'lat': p.lat, 'lon': p.lon, 'lang': lang, 'limit': 1},
        cancelToken: cancel,
      );
      final list = parseFeatures(r.data);
      if (list.isEmpty) return null;
      final f = list.first;
      return Place(
        id: 'map:${p.lat.toStringAsFixed(6)},${p.lon.toStringAsFixed(6)}',
        name: f.name,
        point: p,
        address: f.address,
        category: f.category,
        source: 'map',
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return null;
      throw Failure.fromDio(e);
    }
  }

  /// Convertit une FeatureCollection GeoJSON Photon en lieux ; les entrées mal formées sont ignorées.
  static List<Place> parseFeatures(Object? data) {
    if (data is! Map) return const [];
    final features = data['features'];
    if (features is! List) return const [];
    final out = <Place>[];
    for (final f in features) {
      try {
        if (f is! Map) continue;
        final geom = f['geometry'];
        final props = f['properties'];
        if (geom is! Map || props is! Map) continue;
        final c = geom['coordinates'];
        if (c is! List || c.length < 2) continue;
        final lon = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        String? s(String k) {
          final v = props[k];
          return v is String && v.trim().isNotEmpty ? v.trim() : null;
        }

        final name = s('name') ?? [s('housenumber'), s('street')].whereType<String>().join(' ');
        final street = [s('housenumber'), s('street')].whereType<String>().join(' ');
        final cityLine = [s('postcode'), s('city') ?? s('town') ?? s('village') ?? s('district')].whereType<String>().join(' ');
        final address = [
          if (s('name') != null) s('name'),
          if (street.isNotEmpty) street,
          if (cityLine.isNotEmpty) cityLine,
          s('state'),
          s('country'),
        ].whereType<String>().join(', ');
        final osmType = s('osm_type');
        final osmId = props['osm_id'];
        out.add(Place(
          id: osmType != null && osmId != null ? 'osm:${_typeWord(osmType)}$osmId' : 'photon:$lat,$lon',
          name: name,
          point: GeoPoint(lat, lon),
          address: address.isEmpty ? null : address,
          category: Place.categoryLabel(s('osm_key') ?? '', s('osm_value') ?? ''),
        ));
      } catch (_) {
        // entrée mal formée : ignorée
      }
    }
    return out;
  }

  static String _typeWord(String t) {
    switch (t) {
      case 'N':
        return 'node';
      case 'W':
        return 'way';
      case 'R':
        return 'relation';
      default:
        return t;
    }
  }
}
