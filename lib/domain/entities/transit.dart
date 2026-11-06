import 'package:strasse/core/core.dart';

/// Tronçon d'un trajet en transports en commun (marche, bus, métro, train…).
class TransitLeg {
  const TransitLeg({
    required this.mode,
    required this.from,
    required this.to,
    required this.fromName,
    required this.toName,
    required this.start,
    required this.end,
    required this.distanceM,
    required this.shape,
    this.routeName,
    this.headsign,
    this.agency,
  });

  /// WALK, BUS, SUBWAY, RAIL, TRAM… (valeurs OpenTripPlanner).
  final String mode;
  final GeoPoint from;
  final GeoPoint to;
  final String fromName;
  final String toName;
  final DateTime start;
  final DateTime end;
  final double distanceM;
  final List<GeoPoint> shape;
  final String? routeName;
  final String? headsign;
  final String? agency;

  bool get isWalk => mode == 'WALK';
  Duration get duration => end.difference(start);
}

/// Itinéraire en transports en commun, tel que calculé par le fournisseur configuré.
class TransitItinerary {
  const TransitItinerary({
    required this.start,
    required this.end,
    required this.legs,
    required this.transfers,
    required this.walkDistanceM,
  });

  final DateTime start;
  final DateTime end;
  final List<TransitLeg> legs;
  final int transfers;
  final double walkDistanceM;

  Duration get duration => end.difference(start);
  List<GeoPoint> get shape => [for (final l in legs) ...l.shape];
}
