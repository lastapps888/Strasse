import 'package:strasse/core/core.dart';
import 'package:strasse/domain/entities/place.dart';

enum PoiKind {
  hotel('Hôtel'),
  restaurant('Restaurant'),
  tourism('Site touristique'),
  other('Lieu');

  const PoiKind(this.label);
  final String label;
}

/// Établissement ou site découvert sur la carte. Chaque champ n'est renseigné que si la source le fournit.
class Poi {
  const Poi({
    required this.place,
    required this.kind,
    required this.source,
    this.photoUrl,
    this.stars,
    this.popularity,
    this.cuisine,
    this.reservationUrl,
    this.email,
    this.distanceMeters,
  });

  final Place place;
  final PoiKind kind;

  /// osm | opentripmap
  final String source;

  /// Photo libre (Wikimedia Commons ou lien `image` d'OpenStreetMap).
  final String? photoUrl;

  /// Classement officiel d'un hôtel (étoiles, balise OSM `stars`). Ce n'est pas une note d'utilisateurs.
  final int? stars;

  /// Indice de popularité 1–3 (OpenTripMap). Ce n'est pas une note d'utilisateurs.
  final int? popularity;
  final String? cuisine;

  /// Lien de réservation fourni par OpenStreetMap (`reservation:website`, `booking`…).
  final String? reservationUrl;
  final String? email;
  final double? distanceMeters;

  String get id => place.id;
  GeoPoint get point => place.point;

  /// Adresse de réservation réellement disponible : lien de réservation, sinon site de l'établissement.
  String? get bookingTarget => reservationUrl ?? place.website;

  Poi withDistance(GeoPoint from) => Poi(
        place: place,
        kind: kind,
        source: source,
        photoUrl: photoUrl,
        stars: stars,
        popularity: popularity,
        cuisine: cuisine,
        reservationUrl: reservationUrl,
        email: email,
        distanceMeters: distanceM(from, place.point),
      );
}
