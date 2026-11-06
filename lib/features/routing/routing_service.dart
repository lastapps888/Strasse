import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/otp_client.dart';
import 'package:strasse/data/providers/valhalla_client.dart';
import 'package:strasse/domain/domain.dart';

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

/// Calcul d'itinéraires : Valhalla en ligne, moteur local éventuel hors connexion, OpenTripPlanner pour les transports.
class RoutingService {
  RoutingService({required this.valhalla, required this.transit, this.local});

  final ValhallaClient valhalla;
  final TransitRouter transit;
  final LocalRoutingBackend? local;

  bool get configured => valhalla.configured || (local?.available ?? false);
  bool get transitAvailable => transit.available;

  Future<List<RouteOption>> plan(
    List<GeoPoint> points,
    TravelMode mode,
    RoutePrefs prefs, {
    int alternates = 2,
    CancelToken? cancel,
  }) async {
    try {
      return await valhalla.route(points, mode, prefs, alternates: alternates, cancel: cancel);
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
