import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';

/// Catégories de recherche à proximité. Le terme est interprété par le géocodeur (expressions Nominatim).
enum PlaceCategory {
  fuel('Station-service', 'station-service', 'local_gas_station'),
  parking('Parking', 'parking', 'local_parking'),
  restaurant('Restaurant', 'restaurant', 'restaurant'),
  cafe('Café', 'café', 'local_cafe'),
  pharmacy('Pharmacie', 'pharmacie', 'local_pharmacy'),
  hotel('Hôtel', 'hôtel', 'hotel'),
  supermarket('Supermarché', 'supermarché', 'shopping_cart'),
  charging('Recharge', 'borne de recharge', 'ev_station'),
  atm('Distributeur', 'distributeur', 'atm'),
  toilets('Toilettes', 'toilettes', 'wc'),
  rest('Aire de repos', 'aire de repos', 'airline_seat_recline_normal');

  const PlaceCategory(this.label, this.query, this.iconName);
  final String label;
  final String query;
  final String iconName;
}

/// Géocodeur compatible Nominatim : recherche d'adresses, de lieux, recherche inverse.
///
/// Respecter la politique d'utilisation du serveur choisi (le serveur public d'OpenStreetMap n'est pas
/// destiné à la production : utiliser une instance dédiée, Photon ou un fournisseur commercial compatible).
class GeocoderClient {
  GeocoderClient(this.baseUrl, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'Accept': 'application/json', 'Accept-Language': 'fr'},
            ));

  final String baseUrl;
  final Dio _dio;
  final LinkedHashMap<String, List<Place>> _cache = LinkedHashMap();

  bool get configured => baseUrl.isNotEmpty;

  Future<List<Place>> search(
    String query, {
    GeoPoint? near,
    GeoBounds? bounds,
    bool bounded = false,
    int limit = 8,
    CancelToken? cancel,
  }) async {
    if (!configured) throw Failure.notConfigured('La recherche d\'adresses');
    final q = query.trim();
    if (q.isEmpty) return const [];
    final view = bounds ?? (near == null ? null : GeoBounds.around(near, 30000));
    final key = '$q|${view?.toBboxParam()}|$bounded|$limit';
    final cached = _cache[key];
    if (cached != null) {
      _cache.remove(key);
      _cache[key] = cached; // récent en dernier
      return cached;
    }
    try {
      final r = await _dio.get<List<dynamic>>(
        '/search',
        queryParameters: {
          'q': q,
          'format': 'jsonv2',
          'addressdetails': 1,
          'extratags': 1,
          'limit': limit,
          'accept-language': 'fr',
          if (view != null) 'viewbox': '${view.west},${view.north},${view.east},${view.south}',
          if (view != null && bounded) 'bounded': 1,
        },
        cancelToken: cancel,
      );
      final places = <Place>[];
      for (final e in r.data ?? const []) {
        try {
          places.add(Place.fromNominatim(Map<String, dynamic>.from(e as Map)));
        } catch (_) {
          // résultat mal formé : ignoré
        }
      }
      _cache[key] = places;
      if (_cache.length > 80) _cache.remove(_cache.keys.first);
      return places;
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }

  /// Lieu le plus proche d'un point (appui long sur la carte).
  Future<Place?> reverse(GeoPoint p, {CancelToken? cancel}) async {
    if (!configured) return null;
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '/reverse',
        queryParameters: {'lat': p.lat, 'lon': p.lon, 'format': 'jsonv2', 'addressdetails': 1, 'extratags': 1, 'zoom': 18, 'accept-language': 'fr'},
        cancelToken: cancel,
      );
      final d = r.data;
      if (d == null || d['error'] != null) return null;
      final place = Place.fromNominatim(d);
      return Place(
        id: 'map:${p.lat.toStringAsFixed(6)},${p.lon.toStringAsFixed(6)}',
        name: place.name,
        point: p,
        address: place.address,
        category: place.category,
        phone: place.phone,
        website: place.website,
        openingHours: place.openingHours,
        description: place.description,
        source: 'map',
      );
    } on DioException {
      return null;
    }
  }

  // ------------------------------------------------------ Coordonnées GPS

  static final _decimalComma = RegExp(r'^(-?\d{1,3}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)$');
  static final _decimalSpace = RegExp(r'^(-?\d{1,3}(?:\.\d+)?)\s+(-?\d{1,3}(?:\.\d+)?)$');
  static final _frenchDecimals = RegExp(r'^(-?\d{1,3},\d+)\s*[;\s]\s*(-?\d{1,3},\d+)$');
  static final _dms = RegExp(
    r'''^(\d{1,3})\s*[°d]\s*(\d{1,2})\s*['′m]\s*(\d{1,2}(?:[.,]\d+)?)\s*["″s]?\s*([NSns])[\s,;]+(\d{1,3})\s*[°d]\s*(\d{1,2})\s*['′m]\s*(\d{1,2}(?:[.,]\d+)?)\s*["″s]?\s*([EWOewo])$''',
  );

  /// Reconnaît des coordonnées GPS saisies : « 48.8566, 2.3522 », « 48,8566 2,3522 », « 48°51'24"N 2°21'8"E ».
  static GeoPoint? parseCoordinates(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    GeoPoint? check(double lat, double lon) =>
        (lat.abs() <= 90 && lon.abs() <= 180) ? GeoPoint(lat, lon) : null;

    var m = _decimalComma.firstMatch(s) ?? _decimalSpace.firstMatch(s);
    if (m != null) return check(double.parse(m.group(1)!), double.parse(m.group(2)!));
    m = _frenchDecimals.firstMatch(s);
    if (m != null) {
      return check(double.parse(m.group(1)!.replaceAll(',', '.')), double.parse(m.group(2)!.replaceAll(',', '.')));
    }
    final dms = _dms.firstMatch(s);
    if (dms != null) {
      double part(int d, int mi, int se) =>
          double.parse(dms.group(d)!) + double.parse(dms.group(mi)!) / 60 + double.parse(dms.group(se)!.replaceAll(',', '.')) / 3600;
      var lat = part(1, 2, 3);
      var lon = part(5, 6, 7);
      if (dms.group(4)!.toUpperCase() == 'S') lat = -lat;
      final ew = dms.group(8)!.toUpperCase();
      if (ew == 'W' || ew == 'O') lon = -lon;
      return check(lat, lon);
    }
    return null;
  }
}
