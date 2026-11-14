import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/geo_backend.dart';
import 'package:strasse/domain/domain.dart';

/// Découverte d'établissements et de sites par Overpass API (données OpenStreetMap).
///
/// Respect des instances publiques : une seule requête à la fois, au moins 2 s entre deux requêtes, cache de 30 minutes
/// par zone arrondie, zone limitée en taille, résultats plafonnés.
class OverpassPoiClient {
  OverpassPoiClient(this.endpoints, {Dio? dio, String userAgent = ''})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 30),
              responseType: ResponseType.json,
              headers: {'Accept': 'application/json', if (userAgent.isNotEmpty) 'User-Agent': userAgent},
            ));

  /// Instances à essayer dans l'ordre.
  final List<String> endpoints;
  final Dio _dio;

  static final RateGate _gate = RateGate(const Duration(seconds: 2));

  /// File commune à tous les clients Overpass de l'application (une requête à la fois).
  static RateGate get sharedGate => _gate;
  static final TtlCache<List<Poi>> _cache = TtlCache(ttl: const Duration(minutes: 30), maxEntries: 60);

  /// Côté maximal (degrés) d'une zone interrogée.
  static const double maxSpanDeg = 0.12;

  bool get configured => endpoints.isNotEmpty;

  static const _filters = <PoiKind, List<String>>{
    PoiKind.hotel: ['["tourism"~"^(hotel|hostel|guest_house|motel|apartment|chalet|camp_site)\$"]'],
    PoiKind.restaurant: ['["amenity"~"^(restaurant|fast_food|cafe|bar|pub)\$"]'],
    PoiKind.tourism: [
      '["tourism"~"^(attraction|viewpoint|museum|gallery|zoo|theme_park|artwork)\$"]',
      '["historic"~"^(castle|monument|ruins|archaeological_site|memorial|fort)\$"]',
    ],
  };

  /// Requête Overpass pour une catégorie dans une zone (exposée pour les tests).
  static String buildQuery(PoiKind kind, GeoBounds b, {int limit = 80}) => buildQueryFor(_filters[kind] ?? const <String>[], b, limit: limit);

  /// Requête pour une liste de filtres Overpass (ex. `["amenity"="fuel"]`).
  static String buildQueryFor(List<String> filters, GeoBounds b, {int limit = 80, bool requireName = true}) {
    final box = '${b.south.toStringAsFixed(5)},${b.west.toStringAsFixed(5)},${b.north.toStringAsFixed(5)},${b.east.toStringAsFixed(5)}';
    final name = requireName ? '["name"]' : '';
    final parts = filters.map((f) => 'nwr$f$name($box);').join();
    return '[out:json][timeout:25];($parts);out center tags $limit;';
  }

  Future<List<Poi>> inBounds(PoiKind kind, GeoBounds b, {GeoPoint? from, int limit = 80, CancelToken? cancel}) async {
    final filters = _filters[kind];
    if (filters == null) return const [];
    return byFilters(filters, b, kind: kind, from: from, limit: limit, cancel: cancel);
  }

  /// Recherche libre par filtres Overpass (catégories « autour de moi » : stations, parkings, pharmacies…).
  Future<List<Poi>> byFilters(
    List<String> filters,
    GeoBounds b, {
    PoiKind kind = PoiKind.other,
    bool requireName = true,
    GeoPoint? from,
    int limit = 80,
    CancelToken? cancel,
  }) async {
    if (!configured) throw Failure.notConfigured('Les données routières (Overpass)');
    if (b.latSpan > maxSpanDeg || b.lonSpan > maxSpanDeg) {
      throw const Failure(FailureKind.client, 'Zoomez sur la carte pour afficher les établissements.', code: 'zoom_in');
    }
    final key = '${filters.join()}|${b.south.toStringAsFixed(2)},${b.west.toStringAsFixed(2)},${b.north.toStringAsFixed(2)},${b.east.toStringAsFixed(2)}|$limit';
    final cached = _cache.get(key);
    final center = from ?? b.center;
    if (cached != null) return _sorted(cached, center);

    final query = buildQueryFor(filters, b, limit: limit, requireName: requireName);
    final data = await FailoverRunner.run(endpoints, (i) => _gate.run(() async {
          try {
            final r = await _dio.post<Object>(
              endpoints[i],
              data: 'data=${Uri.encodeQueryComponent(query)}',
              options: Options(contentType: Headers.formUrlEncodedContentType),
              cancelToken: cancel,
            );
            return r.data;
          } on DioException catch (e) {
            throw Failure.fromDio(e);
          }
        }));
    final pois = parse(data, kind, requireName: requireName);
    _cache.put(key, pois);
    return _sorted(pois, center);
  }

  static List<Poi> _sorted(List<Poi> list, GeoPoint from) {
    final out = [for (final p in list) p.withDistance(from)];
    out.sort((a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0));
    return out;
  }

  /// Convertit la réponse Overpass JSON en établissements. Les éléments sans nom ou sans position sont ignorés.
  static List<Poi> parse(Object? data, PoiKind kind, {bool requireName = true}) {
    if (data is! Map) throw const Failure(FailureKind.server, 'Réponse Overpass invalide.');
    final elements = data['elements'];
    if (elements is! List) throw const Failure(FailureKind.server, 'Réponse Overpass sans éléments.');
    final out = <Poi>[];
    for (final e in elements) {
      try {
        if (e is! Map) continue;
        final tags = e['tags'];
        if (tags is! Map) continue;
        String? t(String k) {
          final v = tags[k];
          return v is String && v.trim().isNotEmpty ? v.trim() : null;
        }

        final name = t('name') ?? (requireName ? null : (t('brand') ?? t('operator') ?? Place.categoryLabel('amenity', t('amenity') ?? t('shop') ?? '') ?? 'Lieu'));
        if (name == null) continue;
        double? lat, lon;
        if (e['lat'] is num && e['lon'] is num) {
          lat = (e['lat'] as num).toDouble();
          lon = (e['lon'] as num).toDouble();
        } else if (e['center'] is Map) {
          final c = e['center'] as Map;
          if (c['lat'] is num && c['lon'] is num) {
            lat = (c['lat'] as num).toDouble();
            lon = (c['lon'] as num).toDouble();
          }
        }
        if (lat == null || lon == null) continue;
        final street = [t('addr:housenumber'), t('addr:street')].whereType<String>().join(' ');
        final city = [t('addr:postcode'), t('addr:city')].whereType<String>().join(' ');
        final address = [street, city].where((s) => s.isNotEmpty).join(', ');
        final kindKey = t('tourism') ?? t('amenity') ?? t('historic') ?? '';
        final cat = Place.categoryLabel(t('tourism') != null ? 'tourism' : (t('amenity') != null ? 'amenity' : 'historic'), kindKey);
        final website = _https(t('website') ?? t('contact:website'));
        final place = Place(
          id: 'osm:${e['type']}${e['id']}',
          name: name,
          point: GeoPoint(lat, lon),
          address: address.isEmpty ? null : address,
          category: cat,
          phone: t('phone') ?? t('contact:phone'),
          website: website,
          openingHours: t('opening_hours'),
          description: t('description'),
          source: 'osm',
        );
        out.add(Poi(
          place: place,
          kind: kind,
          source: 'osm',
          photoUrl: photoFrom(t('image'), t('wikimedia_commons')),
          stars: _stars(t('stars')),
          cuisine: _cuisine(t('cuisine')),
          reservationUrl: _https(t('reservation:website') ?? t('booking:website') ?? t('contact:booking')),
          email: t('email') ?? t('contact:email'),
        ));
      } catch (_) {
        // élément mal formé : ignoré
      }
    }
    return out;
  }

  /// Seules les adresses HTTPS sont conservées (navigateur intégré sécurisé).
  static String? _https(String? u) {
    if (u == null) return null;
    final v = u.startsWith('http') ? u : 'https://$u';
    final uri = Uri.tryParse(v);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.replace(scheme: 'https').toString();
  }

  /// Photo libre : lien `image` direct, ou fichier Wikimedia Commons (`File:Nom.jpg`).
  static String? photoFrom(String? image, String? commons) {
    if (commons != null && commons.toLowerCase().startsWith('file:')) {
      final file = commons.substring(5).trim();
      if (file.isNotEmpty) return 'https://commons.wikimedia.org/wiki/Special:FilePath/${Uri.encodeComponent(file)}?width=480';
    }
    if (image != null && image.startsWith('https://')) {
      final low = image.toLowerCase();
      if (low.contains('commons.wikimedia.org/wiki/file:')) {
        final name = image.substring(low.indexOf('file:') + 5);
        return 'https://commons.wikimedia.org/wiki/Special:FilePath/$name?width=480';
      }
      if (RegExp(r'\.(jpe?g|png|webp)(\?.*)?$', caseSensitive: false).hasMatch(image)) return image;
    }
    return null;
  }

  static int? _stars(String? v) {
    if (v == null) return null;
    final m = RegExp(r'^(\d)').firstMatch(v);
    final n = m == null ? null : int.tryParse(m.group(1)!);
    return n != null && n >= 1 && n <= 5 ? n : null;
  }

  static String? _cuisine(String? v) {
    if (v == null) return null;
    const names = {
      'french': 'Française', 'italian': 'Italienne', 'pizza': 'Pizzeria', 'burger': 'Burgers', 'chinese': 'Chinoise',
      'japanese': 'Japonaise', 'sushi': 'Sushi', 'indian': 'Indienne', 'thai': 'Thaï', 'vietnamese': 'Vietnamienne',
      'lebanese': 'Libanaise', 'kebab': 'Kebab', 'regional': 'Régionale', 'seafood': 'Poissons et fruits de mer',
      'steak_house': 'Grillades', 'crepe': 'Crêperie', 'coffee_shop': 'Café', 'spanish': 'Espagnole', 'mexican': 'Mexicaine',
      'greek': 'Grecque', 'american': 'Américaine', 'sandwich': 'Sandwichs', 'bakery': 'Boulangerie',
    };
    final first = v.split(';').first.trim().toLowerCase();
    return names[first] ?? (first.isEmpty ? null : first.replaceAll('_', ' '));
  }
}
