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

/// Arrêt de transport en commun (bus, tram, gare, station de métro, gare de funiculaire…).
class TransitStop {
  const TransitStop({required this.id, required this.name, required this.point, this.modes = const []});

  /// Identifiant utilisable pour demander les horaires au fournisseur.
  final String id;
  final String name;
  final GeoPoint point;
  final List<String> modes;
}

/// Un passage prévu à un arrêt.
class StopDeparture {
  const StopDeparture({
    required this.routeName,
    required this.mode,
    required this.scheduled,
    this.headsign,
    this.expected,
    this.agency,
    this.cancelled = false,
  });

  final String routeName;
  final String mode;
  final String? headsign;
  final DateTime scheduled;

  /// Heure prévue en temps réel, quand l'opérateur la publie.
  final DateTime? expected;
  final String? agency;
  final bool cancelled;

  DateTime get best => expected ?? scheduled;
  bool get realTime => expected != null;
  Duration get delay => expected == null ? Duration.zero : expected!.difference(scheduled);
}

/// Ligne de transport en commun dessinée sur la carte (données OpenStreetMap).
class TransitLine {
  const TransitLine({
    required this.id,
    required this.mode,
    required this.ref,
    required this.shapes,
    this.name,
    this.colorHex,
    this.from,
    this.to,
    this.operator,
  });

  final String id;

  /// route=* d'OpenStreetMap : bus, tram, subway, train, funicular, aerialway…
  final String mode;
  final String ref;
  final String? name;
  final String? colorHex;
  final String? from;
  final String? to;
  final String? operator;
  final List<List<GeoPoint>> shapes;

  String get title => ref.isNotEmpty ? ref : (name ?? '');
}

/// Libellé français d'un mode (valeurs MOTIS/OpenTripPlanner en majuscules, ou route=* d'OpenStreetMap).
String transitModeLabel(String mode) {
  switch (mode.toUpperCase()) {
    case 'WALK':
      return 'Marche';
    case 'BUS':
    case 'TROLLEYBUS':
      return 'Bus';
    case 'COACH':
      return 'Car';
    case 'TRAM':
    case 'LIGHT_RAIL':
      return 'Tram';
    case 'SUBWAY':
    case 'METRO':
      return 'Métro';
    case 'FERRY':
      return 'Bateau';
    case 'FUNICULAR':
      return 'Funiculaire';
    case 'CABLE_CAR':
    case 'GONDOLA':
    case 'AERIAL_LIFT':
    case 'AERIALWAY':
      return 'Télécabine';
    case 'MONORAIL':
      return 'Monorail';
    case 'TRAIN':
    case 'RAIL':
    case 'REGIONAL_RAIL':
    case 'REGIONAL_FAST_RAIL':
    case 'SUBURBAN':
      return 'TER / train';
    case 'HIGHSPEED_RAIL':
    case 'LONG_DISTANCE':
    case 'NIGHT_RAIL':
      return 'Train grandes lignes';
    default:
      return 'Transport';
  }
}
