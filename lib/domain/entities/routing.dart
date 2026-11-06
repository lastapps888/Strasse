import 'package:flutter/material.dart';
import 'package:strasse/core/core.dart';

enum TravelMode {
  car('Voiture', Icons.directions_car_rounded, 'auto'),
  walk('Marche', Icons.directions_walk_rounded, 'pedestrian'),
  bike('Vélo', Icons.directions_bike_rounded, 'bicycle'),
  transit('Transports', Icons.directions_transit_rounded, '');

  const TravelMode(this.label, this.icon, this.costing);
  final String label;
  final IconData icon;
  final String costing;

  static TravelMode fromName(String? n) =>
      TravelMode.values.firstWhere((m) => m.name == n, orElse: () => TravelMode.car);
}

enum RouteCriterion { fastest, shortest }

enum BikeType {
  road('Route', 'Road'),
  hybrid('Hybride', 'Hybrid'),
  city('Ville', 'City'),
  cross('Cross', 'Cross'),
  mountain('VTT', 'Mountain');

  const BikeType(this.label, this.valhalla);
  final String label;
  final String valhalla;

  static BikeType fromName(String? n) => BikeType.values.firstWhere((m) => m.name == n, orElse: () => BikeType.hybrid);
}

/// Préférences de calcul d'itinéraire. Les options pertinentes dépendent du mode de déplacement.
class RoutePrefs {
  const RoutePrefs({
    this.criterion = RouteCriterion.fastest,
    this.avoidTolls = false,
    this.avoidHighways = false,
    this.avoidFerries = false,
    this.bikeType = BikeType.hybrid,
    this.preferCycleways = true,
    this.avoidHills = false,
    this.avoidStairs = false,
    this.walkSpeedKmh = 5.1,
    this.customHighwayUse,
    this.customTollUse,
  });

  final RouteCriterion criterion;
  final bool avoidTolls;
  final bool avoidHighways;
  final bool avoidFerries;
  final BikeType bikeType;

  /// Vélo : privilégie les pistes cyclables et voies calmes (Valhalla `use_roads` bas).
  final bool preferCycleways;
  final bool avoidHills;
  final bool avoidStairs;
  final double walkSpeedKmh;

  /// Itinéraire personnalisé (voiture) : curseurs 0..1 transmis tels quels à Valhalla.
  final double? customHighwayUse;
  final double? customTollUse;

  RoutePrefs copyWith({
    RouteCriterion? criterion,
    bool? avoidTolls,
    bool? avoidHighways,
    bool? avoidFerries,
    BikeType? bikeType,
    bool? preferCycleways,
    bool? avoidHills,
    bool? avoidStairs,
    double? walkSpeedKmh,
    double? customHighwayUse,
    double? customTollUse,
    bool clearCustom = false,
  }) =>
      RoutePrefs(
        criterion: criterion ?? this.criterion,
        avoidTolls: avoidTolls ?? this.avoidTolls,
        avoidHighways: avoidHighways ?? this.avoidHighways,
        avoidFerries: avoidFerries ?? this.avoidFerries,
        bikeType: bikeType ?? this.bikeType,
        preferCycleways: preferCycleways ?? this.preferCycleways,
        avoidHills: avoidHills ?? this.avoidHills,
        avoidStairs: avoidStairs ?? this.avoidStairs,
        walkSpeedKmh: walkSpeedKmh ?? this.walkSpeedKmh,
        customHighwayUse: clearCustom ? null : (customHighwayUse ?? this.customHighwayUse),
        customTollUse: clearCustom ? null : (customTollUse ?? this.customTollUse),
      );

  Map<String, dynamic> toJson() => {
        'criterion': criterion.name,
        'avoidTolls': avoidTolls,
        'avoidHighways': avoidHighways,
        'avoidFerries': avoidFerries,
        'bikeType': bikeType.name,
        'preferCycleways': preferCycleways,
        'avoidHills': avoidHills,
        'avoidStairs': avoidStairs,
        'walkSpeedKmh': walkSpeedKmh,
        'customHighwayUse': customHighwayUse,
        'customTollUse': customTollUse,
      };

  factory RoutePrefs.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const RoutePrefs();
    return RoutePrefs(
      criterion: RouteCriterion.values.firstWhere((c) => c.name == j['criterion'], orElse: () => RouteCriterion.fastest),
      avoidTolls: j['avoidTolls'] == true,
      avoidHighways: j['avoidHighways'] == true,
      avoidFerries: j['avoidFerries'] == true,
      bikeType: BikeType.fromName(j['bikeType'] as String?),
      preferCycleways: j['preferCycleways'] != false,
      avoidHills: j['avoidHills'] == true,
      avoidStairs: j['avoidStairs'] == true,
      walkSpeedKmh: (j['walkSpeedKmh'] as num?)?.toDouble() ?? 5.1,
      customHighwayUse: (j['customHighwayUse'] as num?)?.toDouble(),
      customTollUse: (j['customTollUse'] as num?)?.toDouble(),
    );
  }
}

/// Manœuvre de guidage (un virage, une sortie, un rond-point, l'arrivée…).
class Maneuver {
  const Maneuver({
    required this.instruction,
    required this.type,
    required this.distanceM,
    required this.durationS,
    required this.beginIndex,
    this.verbalPre,
    this.verbalPost,
    this.verbalAlert,
    this.streetNames = const [],
    this.isFinal = false,
    this.isWaypoint = false,
  });

  /// Texte affiché (« Tournez à droite sur Rue de Rivoli. »).
  final String instruction;

  /// Annonce vocale juste avant la manœuvre.
  final String? verbalPre;
  final String? verbalPost;

  /// Annonce d'alerte anticipée fournie par le moteur de routage.
  final String? verbalAlert;

  /// Type Valhalla (0..39) : voir [maneuverIcon].
  final int type;
  final double distanceM;
  final double durationS;

  /// Indice du point de la polyligne où commence la manœuvre.
  final int beginIndex;
  final List<String> streetNames;

  /// Arrivée à la destination finale.
  final bool isFinal;

  /// Arrivée à une étape intermédiaire.
  final bool isWaypoint;

  String get spoken => (verbalPre?.isNotEmpty ?? false) ? verbalPre! : instruction;

  String? get street => streetNames.isEmpty ? null : streetNames.first;
}

/// Un itinéraire complet calculé par le moteur de routage.
class RouteOption {
  RouteOption({
    required this.id,
    required this.mode,
    required this.shape,
    required this.distanceM,
    required this.durationS,
    required this.maneuvers,
    this.hasToll = false,
    this.hasHighway = false,
    this.hasFerry = false,
    this.label,
    this.waypointIndices = const [],
  });

  final String id;
  final TravelMode mode;
  final List<GeoPoint> shape;
  final double distanceM;
  final double durationS;
  final List<Maneuver> maneuvers;
  final bool hasToll;
  final bool hasHighway;
  final bool hasFerry;

  /// « Plus rapide », « Plus court », « Sans péage »… calculé en comparant les alternatives.
  String? label;

  /// Indices dans [shape] des étapes intermédiaires.
  final List<int> waypointIndices;

  late final List<double> cumulative = cumulativeDistances(shape);

  GeoPoint get start => shape.first;
  GeoPoint get end => shape.last;
  double get totalM => cumulative.isEmpty ? 0 : cumulative.last;
}

/// Pictogramme d'une manœuvre Valhalla.
IconData maneuverIcon(int type) {
  switch (type) {
    case 1:
    case 2:
    case 3:
      return Icons.navigation_rounded;
    case 4:
    case 5:
    case 6:
      return Icons.flag_rounded;
    case 9:
    case 16:
      return type == 9 ? Icons.turn_slight_right_rounded : Icons.turn_slight_left_rounded;
    case 10:
    case 18:
    case 20:
    case 23:
    case 37:
      return Icons.turn_right_rounded;
    case 11:
      return Icons.turn_sharp_right_rounded;
    case 14:
      return Icons.turn_sharp_left_rounded;
    case 15:
    case 19:
    case 21:
    case 24:
    case 38:
      return Icons.turn_left_rounded;
    case 12:
      return Icons.u_turn_right_rounded;
    case 13:
      return Icons.u_turn_left_rounded;
    case 26:
    case 27:
      return Icons.roundabout_right_rounded;
    case 25:
      return Icons.merge_rounded;
    case 28:
    case 29:
      return Icons.directions_boat_rounded;
    default:
      return Icons.straight_rounded;
  }
}
