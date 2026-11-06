import 'dart:math' as math;

import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';

/// Résultat du traitement d'une position GPS par le moteur de guidage.
class NavUpdate {
  const NavUpdate({
    required this.snapped,
    required this.alongM,
    required this.remainingM,
    required this.remainingS,
    required this.nextManeuverIndex,
    required this.distanceToNextM,
    required this.offRouteM,
    required this.offRoute,
    required this.arrived,
    required this.speech,
    required this.bearing,
    required this.currentSegment,
  });

  /// Position projetée sur l'itinéraire.
  final GeoPoint snapped;

  /// Distance déjà parcourue le long de l'itinéraire.
  final double alongM;
  final double remainingM;
  final double remainingS;
  final int nextManeuverIndex;
  final double distanceToNextM;

  /// Distance entre la position GPS et l'itinéraire.
  final double offRouteM;

  /// Vrai seulement après plusieurs positions consécutives hors itinéraire (évite les faux positifs).
  final bool offRoute;
  final bool arrived;

  /// Phrases à prononcer maintenant.
  final List<String> speech;
  final double bearing;
  final int currentSegment;
}

/// Moteur de guidage : suit la progression sur un itinéraire calculé, détecte les manœuvres, l'écart de parcours
/// et l'arrivée. Aucune dépendance à Flutter ni au GPS : il est entièrement testable.
class NavigationEngine {
  NavigationEngine(
    this.route, {
    this.units = Units.metric,
    List<double>? announceDistances,
    this.offRouteConfirmations = 3,
  }) : announceDistances = announceDistances ?? defaultAnnounceDistances(route.mode) {
    _cum = route.cumulative;
    _total = route.totalM;
  }

  final RouteOption route;
  final Units units;

  /// Distances (m) auxquelles une manœuvre est annoncée, de la plus grande à la plus petite.
  final List<double> announceDistances;
  final int offRouteConfirmations;

  late final List<double> _cum;
  late final double _total;

  int _segment = 0;
  int _next = 1;
  int _offCount = 0;
  bool _startAnnounced = false;
  bool _arrivalAnnounced = false;
  final Set<String> _spoken = {};
  final Set<int> _waypointsAnnounced = {};

  static List<double> defaultAnnounceDistances(TravelMode mode) {
    switch (mode) {
      case TravelMode.car:
        return const [1000, 400, 120];
      case TravelMode.bike:
        return const [250, 80];
      case TravelMode.walk:
      case TravelMode.transit:
        return const [100, 30];
    }
  }

  double get arrivalRadiusM => route.mode == TravelMode.car ? 25 : 15;

  double _cumAtManeuver(int i) {
    final idx = route.maneuvers[i].beginIndex.clamp(0, _cum.length - 1);
    return _cum[idx];
  }

  /// Traite une nouvelle position.
  NavUpdate update(GeoPoint position, {double accuracyM = 10, DateTime? now}) {
    final shape = route.shape;
    // Recherche locale devant la position précédente, puis globale si l'écart est important.
    var proj = projectOnPolyline(shape, position, from: math.max(0, _segment - 5), to: math.min(shape.length - 1, _segment + 80));
    if (proj.distanceM > 60) {
      final global = projectOnPolyline(shape, position);
      if (global.distanceM + 20 < proj.distanceM) proj = global;
    }
    // On ne recule jamais de plus de quelques segments (GPS qui saute en arrière).
    if (proj.segment >= _segment - 3) _segment = math.max(_segment, proj.segment);

    final segLen = _cum[math.min(proj.segment + 1, _cum.length - 1)] - _cum[proj.segment];
    final along = (_cum[proj.segment] + proj.t * segLen).clamp(0.0, _total);
    final remaining = math.max(0.0, _total - along);

    // Écart de parcours : seuil adapté à la précision du GPS, confirmé sur plusieurs positions.
    final threshold = math.max(route.mode == TravelMode.car ? 35.0 : 25.0, accuracyM * 1.5);
    if (proj.distanceM > threshold) {
      _offCount++;
    } else {
      _offCount = 0;
    }
    final offRoute = _offCount >= offRouteConfirmations;

    final ms = route.maneuvers;
    final lastIdx = ms.length - 1;
    // Manœuvre à venir : la première non encore atteinte (la dernière, l'arrivée, n'est jamais dépassée).
    while (_next < lastIdx && _cumAtManeuver(_next) <= along + 3) {
      _next++;
    }
    final next = ms.isEmpty ? null : ms[math.min(_next, lastIdx)];
    final distToNext = next == null ? remaining : math.max(0.0, _cumAtManeuver(math.min(_next, lastIdx)) - along);

    final arrived = remaining <= arrivalRadiusM && !offRoute;

    final speech = <String>[];
    if (!offRoute) _collectSpeech(speech, along, distToNext, arrived);

    return NavUpdate(
      snapped: proj.point,
      alongM: along,
      remainingM: remaining,
      remainingS: _remainingSeconds(along),
      nextManeuverIndex: math.min(_next, math.max(0, lastIdx)),
      distanceToNextM: distToNext,
      offRouteM: proj.distanceM,
      offRoute: offRoute,
      arrived: arrived,
      speech: speech,
      bearing: bearingDeg(shape[proj.segment], shape[math.min(proj.segment + 1, shape.length - 1)]),
      currentSegment: proj.segment,
    );
  }

  void _collectSpeech(List<String> out, double along, double distToNext, bool arrived) {
    final ms = route.maneuvers;
    if (ms.isEmpty) return;

    if (!_startAnnounced) {
      _startAnnounced = true;
      final first = ms.first;
      if (first.spoken.isNotEmpty) out.add(first.spoken);
    }

    if (arrived) {
      if (!_arrivalAnnounced) {
        _arrivalAnnounced = true;
        out.add('Vous êtes arrivé à destination.');
      }
      return;
    }

    final idx = math.min(_next, ms.length - 1);
    final m = ms[idx];

    // Étape intermédiaire atteinte.
    if (m.isWaypoint && distToNext <= arrivalRadiusM && _waypointsAnnounced.add(idx)) {
      out.add('Vous êtes arrivé à l\'étape.');
      return;
    }

    // Annonces à distance décroissante. On ne dit que la plus proche seuil franchi, jamais plusieurs d'un coup.
    final prevBegin = idx > 0 ? _cumAtManeuver(idx - 1) : 0.0;
    final segmentLen = _cumAtManeuver(idx) - prevBegin;
    String? chosen;
    double? chosenT;
    for (final t in announceDistances) {
      if (distToNext <= t && !_spoken.contains('$idx:$t')) {
        // Un seuil supérieur à la longueur du tronçon n'a pas de sens (manœuvres rapprochées).
        if (t > segmentLen + 20 && idx > 1) {
          _spoken.add('$idx:$t');
          continue;
        }
        chosen = '$idx:$t';
        chosenT = t;
      }
    }
    if (chosen == null || chosenT == null) return;
    // Marque tous les seuils plus grands comme dits.
    for (final t in announceDistances) {
      if (t >= chosenT) _spoken.add('$idx:$t');
    }
    final smallest = announceDistances.last;
    final isNow = chosenT == smallest;
    if (m.isFinal) {
      out.add(isNow ? 'Votre destination est juste devant.' : 'Votre destination est dans ${speakDistance(distToNext, units)}.');
    } else if (isNow) {
      out.add(m.spoken);
    } else {
      out.add('Dans ${speakDistance(distToNext, units)}, ${_lowerFirst(m.spoken)}');
    }
  }

  static String _lowerFirst(String s) => s.isEmpty ? s : '${s[0].toLowerCase()}${s.substring(1)}';

  /// Temps restant en sommant la durée des manœuvres à venir (plus fidèle qu'un simple prorata global).
  double _remainingSeconds(double along) {
    final ms = route.maneuvers;
    if (ms.isEmpty) return _total == 0 ? 0 : route.durationS * (1 - along / _total);
    var remaining = 0.0;
    for (var i = 0; i < ms.length; i++) {
      final begin = _cumAtManeuver(i);
      final end = i + 1 < ms.length ? _cumAtManeuver(i + 1) : _total;
      final len = end - begin;
      if (end <= along) continue;
      if (begin >= along || len <= 0) {
        remaining += ms[i].durationS;
      } else {
        remaining += ms[i].durationS * ((end - along) / len);
      }
    }
    return remaining;
  }
}
