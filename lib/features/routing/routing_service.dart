import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/geo_backend.dart';
import 'package:strasse/data/providers/otp_client.dart';
import 'package:strasse/data/providers/poi_service.dart';
import 'package:strasse/data/providers/valhalla_client.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/navigation/speed_limits.dart';

/// Moteur d'itinéraires embarqué (hors connexion). Interface prête à recevoir une intégration native de Valhalla
/// ou d'un autre moteur : sans implémentation, le calcul hors connexion est indiqué comme indisponible.
abstract class LocalRoutingBackend {
  bool get available;
  Future<List<RouteOption>> route(List<GeoPoint> points, TravelMode mode, RoutePrefs prefs);
}

/// Variante d'itinéraire comparée dans le planificateur de voyages.
class RouteVariant {
  const RouteVariant({required this.label, this.route, this.error});
  final String label;
  final RouteOption? route;
  final Failure? error;
}

/// Résultat d'un calcul par style : itinéraires, référence « plus rapide » et sites touristiques traversés.
class ModePlan {
  const ModePlan({required this.routes, this.baseline, this.passedPois = const []});
  final List<RouteOption> routes;
  final RouteOption? baseline;
  final List<Poi> passedPois;
}

/// Calcul d'itinéraires : Valhalla en ligne, moteur local éventuel hors connexion, OpenTripPlanner pour les transports.
class RoutingService {
  RoutingService({required this.valhalla, required this.transit, this.local});

  /// Serveurs Valhalla à essayer dans l'ordre (le fournisseur choisi, puis ses remplaçants).
  final List<ValhallaClient> valhalla;
  final TransitRouter transit;
  final LocalRoutingBackend? local;

  bool get configured => valhalla.any((v) => v.configured) || (local?.available ?? false);
  bool get transitAvailable => transit.available;

  Future<List<RouteOption>> plan(
    List<GeoPoint> points,
    TravelMode mode,
    RoutePrefs prefs, {
    int alternates = 2,
    Set<int> viaIndexes = const {},
    CancelToken? cancel,
  }) async {
    try {
      final clients = valhalla.where((v) => v.configured).toList();
      if (clients.isEmpty) throw Failure.notConfigured('Le calcul d\'itinéraires');
      return await FailoverRunner.run([for (final c in clients) c.baseUrl], (i) => clients[i].route(points, mode, prefs, alternates: alternates, viaIndexes: viaIndexes, cancel: cancel));
    } on Failure catch (f) {
      final backend = local;
      if ((f.kind == FailureKind.offline || f.kind == FailureKind.timeout || f.kind == FailureKind.notConfigured) &&
          backend != null &&
          backend.available) {
        return backend.route(points, mode, prefs);
      }
      if (f.kind == FailureKind.offline) {
        throw const Failure(
          FailureKind.offline,
          'Hors connexion : le calcul d\'un itinéraire nécessite le serveur d\'itinéraires. '
          'Un trajet déjà calculé reste guidé sans réseau.',
          code: 'offline_routing_unavailable',
        );
      }
      rethrow;
    }
  }

  /// Limites de vitesse de l'itinéraire (premier serveur qui en renvoie). Vide si aucune n'est connue.
  Future<SpeedLimitMap> speedLimits(RouteOption route, RoutePrefs prefs, {CancelToken? cancel}) async {
    for (final v in valhalla.where((v) => v.configured)) {
      final m = await v.speedLimits(route.shape, route.mode, prefs, cancel: cancel);
      if (!m.isEmpty) return m;
    }
    return SpeedLimitMap.empty;
  }

  /// Calcule selon le style choisi (rapide, économique, touristique) et explique en quoi l'itinéraire diffère du plus rapide.
  /// Le plus rapide sert de référence : si un style donne le même tracé, la note le dit au lieu de prétendre le contraire.
  Future<ModePlan> planMode(
    List<GeoPoint> points,
    TravelMode mode,
    RoutePrefs prefs, {
    int alternates = 2,
    PoiService? poi,
    CancelToken? cancel,
  }) async {
    final c = prefs.criterion;
    if (mode == TravelMode.transit || c == RouteCriterion.fastest || c == RouteCriterion.shortest) {
      return ModePlan(routes: await plan(points, mode, prefs, alternates: alternates, cancel: cancel));
    }
    final baselinePrefs = prefs.copyWith(criterion: RouteCriterion.fastest);
    RouteOption? baseline;
    try {
      baseline = (await plan(points, mode, baselinePrefs, alternates: 0, cancel: cancel)).first;
    } on Failure {
      baseline = null; // le calcul du style choisi peut encore réussir
    }
    var routes = await plan(points, mode, prefs, alternates: alternates, cancel: cancel);
    final notes = <String>[];
    var passed = <Poi>[];

    if (c == RouteCriterion.touristic && points.length == 2 && poi != null && poi.configured) {
      try {
        final t = await _touristic(points, mode, prefs, routes.first, baseline, poi, cancel);
        if (t != null) {
          routes = [t.route, ...routes];
          passed = t.passed;
        }
      } on Failure catch (f) {
        if (f.kind == FailureKind.offline) rethrow;
        notes.add('Sites touristiques indisponibles pour le moment (${f.message}). Itinéraire par routes secondaires seulement.');
      }
    } else if (c == RouteCriterion.touristic && points.length > 2) {
      notes.add('Avec des étapes, le mode touristique évite les grands axes mais n\'ajoute pas de site.');
    }

    for (final r in routes) {
      r.label = r.label == 'Plus rapide' ? c.label : (r.label ?? c.label);
    }
    routes.first.label = c.label;
    if (baseline != null) _describeDifference(routes.first, baseline, c, notes, passed);
    if (c == RouteCriterion.economic && mode == TravelMode.car) {
      notes.add('Économique : péages évités, autoroutes limitées, vitesse modélisée plafonnée à 110 km/h. Le coût réel dépend de votre véhicule.');
    }
    if (notes.isNotEmpty) routes.first.note = [if (routes.first.note != null) routes.first.note!, ...notes].join('\n');
    return ModePlan(routes: routes, baseline: baseline, passedPois: passed);
  }

  static void _describeDifference(RouteOption r, RouteOption base, RouteCriterion c, List<String> notes, List<Poi> passed) {
    final dMin = ((r.durationS - base.durationS) / 60).round();
    final dKm = (r.distanceM - base.distanceM) / 1000;
    final same = (dMin.abs() == 0 && dKm.abs() < 0.2) && r.hasToll == base.hasToll && r.hasHighway == base.hasHighway;
    if (same) {
      notes.insert(0, 'Même tracé que le plus rapide : aucune alternative sensiblement différente n\'existe entre ces points.');
      return;
    }
    String sign(num v, String unit) => '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(unit == 'km' ? 1 : 0)} $unit';
    final parts = <String>[
      'Par rapport au plus rapide : ${sign(dMin, 'min')}, ${sign(dKm, 'km')}',
      if (base.hasToll && !r.hasToll) 'sans péage',
      if (base.hasHighway && !r.hasHighway) 'sans autoroute',
    ];
    notes.insert(0, '${parts.join(' · ')}.');
    if (passed.isNotEmpty) notes.add('Passe près de : ${passed.take(4).map((p) => p.place.title).join(', ')}.');
  }

  /// Insère le meilleur site touristique proche du tracé comme étape de passage, si le détour reste raisonnable (≤ 35 %).
  Future<({RouteOption route, List<Poi> passed})?> _touristic(
    List<GeoPoint> points,
    TravelMode mode,
    RoutePrefs prefs,
    RouteOption scenic,
    RouteOption? baseline,
    PoiService poi,
    CancelToken? cancel,
  ) async {
    final raw = GeoBounds.fromPoints(scenic.shape);
    final bounds = GeoBounds(south: raw.south - 0.01, west: raw.west - 0.01, north: raw.north + 0.01, east: raw.east + 0.01);
    final windows = <GeoBounds>[];
    if (bounds.latSpan <= 0.12 && bounds.lonSpan <= 0.12) {
      windows.add(bounds);
    } else {
      // Trajet long : deux fenêtres de recherche (tiers et deux tiers du parcours), la requête d'un seul bloc serait refusée.
      for (final f in const [0.33, 0.66]) {
        final c = scenic.shape[(scenic.shape.length * f).floor().clamp(0, scenic.shape.length - 1)];
        windows.add(GeoBounds.around(c, 5000));
      }
    }
    final found = <String, Poi>{};
    for (final w in windows) {
      for (final p in await poi.tourism(w, cancel: cancel)) {
        found[p.id] = p;
      }
    }
    if (found.isEmpty) return null;
    final limit = (baseline ?? scenic).durationS * 1.35;
    final scored = <(Poi, double)>[];
    for (final p in found.values) {
      final off = distanceToPolylineM(scenic.shape, p.point);
      if (off > 2500) continue;
      final score = (p.popularity ?? 1) * 2.0 + (p.photoUrl != null ? 1.0 : 0) + (p.place.website != null ? 0.5 : 0) - off / 1500.0;
      scored.add((p, score));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    // On essaie les trois meilleurs : le premier dont le détour reste acceptable est retenu.
    for (final cand in scored.take(3)) {
      final pts = [points.first, cand.$1.point, points.last];
      List<RouteOption> via;
      try {
        via = await plan(pts, mode, prefs, alternates: 0, viaIndexes: {1}, cancel: cancel);
      } on Failure {
        continue;
      }
      final r = via.first;
      if (r.durationS > limit) continue;
      final passed = [
        for (final p in found.values)
          if (distanceToPolylineM(r.shape, p.point) <= 300) p,
      ]..sort((a, b) => (b.popularity ?? 0).compareTo(a.popularity ?? 0));
      return (route: r, passed: passed);
    }
    return null;
  }

  Future<List<TransitItinerary>> planTransit(GeoPoint from, GeoPoint to, {DateTime? departAt}) =>
      transit.plan(from, to, departAt: departAt);

  /// Calcule plusieurs variantes en parallèle (plus rapide, plus court, sans péage, sans autoroute…) pour les comparer.
  Future<List<RouteVariant>> variants(List<GeoPoint> points, TravelMode mode, RoutePrefs base) async {
    final defs = <(String, RoutePrefs)>[
      ('Plus rapide', base.copyWith(criterion: RouteCriterion.fastest, avoidTolls: false, avoidHighways: false)),
      ('Plus court', base.copyWith(criterion: RouteCriterion.shortest, avoidTolls: false, avoidHighways: false)),
      if (mode == TravelMode.car) ('Sans péages', base.copyWith(criterion: RouteCriterion.fastest, avoidTolls: true, avoidHighways: false)),
      if (mode == TravelMode.car) ('Sans autoroutes', base.copyWith(criterion: RouteCriterion.fastest, avoidTolls: false, avoidHighways: true)),
    ];
    final futures = defs.map((d) async {
      try {
        final routes = await plan(points, mode, d.$2, alternates: 0);
        return RouteVariant(label: d.$1, route: routes.first);
      } catch (e) {
        return RouteVariant(label: d.$1, error: toFailure(e));
      }
    });
    return Future.wait(futures);
  }
}
