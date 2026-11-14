import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/geocoder_client.dart';
import 'package:strasse/data/providers/geocoding_service.dart';
import 'package:strasse/data/providers/opentripmap_client.dart';
import 'package:strasse/data/providers/overpass_poi_client.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/services/provider_models.dart';
import 'package:strasse/features/services/provider_resolver.dart';

/// Découverte de lieux : hôtels, restaurants, sites touristiques et catégories « autour de moi ».
/// Le fournisseur de chaque catégorie vient de Réglages > Services.
class PoiService {
  PoiService({required this.overpass, this.openTripMap, required this.tourismUsesOpenTripMap});

  factory PoiService.fromResolver(ProviderResolver r, {Dio? dio}) {
    final ua = r.config.userAgent;
    final endpoints = [for (final p in r.candidates(ServiceCategory.roadData)) ProviderResolver.normalize(r.urlOf(p))];
    final tourism = r.selected(ServiceCategory.tourism);
    final isOtm = tourism.adapter == 'opentripmap';
    return PoiService(
      overpass: OverpassPoiClient(endpoints, dio: dio, userAgent: ua),
      openTripMap: isOtm ? OpenTripMapClient(ProviderResolver.normalize(r.urlOf(tourism)), r.credential(tourism, 'apiKey'), userAgent: ua) : null,
      tourismUsesOpenTripMap: isOtm,
    );
  }

  final OverpassPoiClient overpass;
  final OpenTripMapClient? openTripMap;
  final bool tourismUsesOpenTripMap;

  bool get configured => overpass.configured;

  Future<List<Poi>> hotels(GeoBounds b, {GeoPoint? from, CancelToken? cancel}) => overpass.inBounds(PoiKind.hotel, b, from: from, cancel: cancel);

  Future<List<Poi>> restaurants(GeoBounds b, {GeoPoint? from, CancelToken? cancel}) => overpass.inBounds(PoiKind.restaurant, b, from: from, cancel: cancel);

  /// Sites touristiques : OpenTripMap si choisi et configuré, sinon OpenStreetMap. Un échec d'OpenTripMap bascule sur OSM.
  Future<List<Poi>> tourism(GeoBounds b, {GeoPoint? from, CancelToken? cancel}) async {
    final otm = openTripMap;
    if (tourismUsesOpenTripMap && otm != null && otm.configured) {
      try {
        final c = from ?? b.center;
        final radius = (distanceM(b.center, GeoPoint(b.north, b.east)) / 1.2).clamp(500, 20000).round();
        final res = await otm.around(c, radiusM: radius, cancel: cancel);
        if (res.isNotEmpty) return res;
      } on Failure catch (f) {
        if (f.kind == FailureKind.client || f.kind == FailureKind.unauthorized) rethrow;
      }
    }
    return overpass.inBounds(PoiKind.tourism, b, from: from, cancel: cancel);
  }

  static const Map<PlaceCategory, List<String>> _categoryFilters = {
    PlaceCategory.fuel: ['["amenity"="fuel"]'],
    PlaceCategory.parking: ['["amenity"="parking"]["access"!~"^(private|customers)\$"]'],
    PlaceCategory.restaurant: ['["amenity"~"^(restaurant|fast_food)\$"]'],
    PlaceCategory.cafe: ['["amenity"="cafe"]'],
    PlaceCategory.pharmacy: ['["amenity"="pharmacy"]'],
    PlaceCategory.hotel: ['["tourism"~"^(hotel|hostel|guest_house|motel)\$"]'],
    PlaceCategory.supermarket: ['["shop"~"^(supermarket|convenience)\$"]'],
    PlaceCategory.charging: ['["amenity"="charging_station"]'],
    PlaceCategory.atm: ['["amenity"="atm"]'],
    PlaceCategory.toilets: ['["amenity"="toilets"]'],
    PlaceCategory.rest: ['["highway"="rest_area"]'],
  };

  /// Catégorie par Overpass ; si le service est en panne ou ne renvoie rien, recherche textuelle par le géocodeur.
  Future<List<Place>> categoryOrSearch(PlaceCategory c, GeoBounds b, GeocodingService geocoder, {GeoPoint? from, int limit = 20}) async {
    try {
      final r = await category(c, b, from: from, limit: limit);
      if (r.isNotEmpty) return r;
    } on Failure {
      // repli sur le géocodeur
    }
    return geocoder.search(c.query, bounds: b, bounded: true, limit: limit);
  }

  /// Lieux d'une catégorie dans une zone (Overpass). Les zones trop grandes sont réduites autour de leur centre.
  Future<List<Place>> category(PlaceCategory c, GeoBounds b, {GeoPoint? from, int limit = 40, CancelToken? cancel}) async {
    final bounds = (b.latSpan > OverpassPoiClient.maxSpanDeg || b.lonSpan > OverpassPoiClient.maxSpanDeg) ? GeoBounds.around(b.center, 6000) : b;
    final res = await overpass.byFilters(
      _categoryFilters[c] ?? const <String>[],
      bounds,
      requireName: c != PlaceCategory.fuel && c != PlaceCategory.parking && c != PlaceCategory.atm && c != PlaceCategory.toilets && c != PlaceCategory.charging && c != PlaceCategory.rest,
      from: from,
      limit: limit,
      cancel: cancel,
    );
    return [for (final p in res) p.place];
  }
}
