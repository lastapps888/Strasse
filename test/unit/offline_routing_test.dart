import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/offline_routing/graph_builder.dart';
import 'package:strasse/features/offline_routing/local_router.dart';
import 'package:strasse/features/offline_routing/routing_graph.dart';

/// Petit réseau synthétique :  1 ── 2 ── 3 (est-ouest, « Rue Test »)  et  2 ── 4 (nord, « Avenue Nord »),
/// plus une voie à sens unique 3 → 5 et un chemin piéton 1 ── 6.
const _json = {
  'elements': [
    {'type': 'node', 'id': 1, 'lat': 45.000, 'lon': 5.000},
    {'type': 'node', 'id': 2, 'lat': 45.000, 'lon': 5.005},
    {'type': 'node', 'id': 3, 'lat': 45.000, 'lon': 5.010},
    {'type': 'node', 'id': 4, 'lat': 45.005, 'lon': 5.005},
    {'type': 'node', 'id': 5, 'lat': 45.005, 'lon': 5.010},
    {'type': 'node', 'id': 6, 'lat': 44.992, 'lon': 5.000},
    {'type': 'way', 'id': 10, 'nodes': [1, 2, 3], 'tags': {'highway': 'residential', 'name': 'Rue Test'}},
    {'type': 'way', 'id': 11, 'nodes': [2, 4], 'tags': {'highway': 'residential', 'name': 'Avenue Nord'}},
    {'type': 'way', 'id': 12, 'nodes': [3, 5], 'tags': {'highway': 'residential', 'oneway': 'yes', 'name': 'Sens Unique'}},
    {'type': 'way', 'id': 13, 'nodes': [1, 6], 'tags': {'highway': 'footway'}},
  ],
};

GeoBounds get _bounds => GeoBounds(south: 44.99, west: 4.99, north: 45.01, east: 5.02);

RoutingGraph _graph() => buildGraphFromJsonString(jsonEncode(_json), _bounds);

void main() {
  group('graph_builder', () {
    test('coupe les voies aux intersections', () {
      final g = _graph();
      // 1-2, 2-3, 2-4, 3-5, 1-6 => 5 arêtes
      expect(g.edgeCount, 5);
      expect(g.nodeCount, 6);
    });

    test('refuse une réponse sans voie', () {
      expect(() => buildGraphFromJsonString('{"elements":[]}', _bounds), throwsFormatException);
      expect(() => buildGraphFromJsonString('[]', _bounds), throwsFormatException);
    });

    test('marque les accès par type de voie', () {
      final g = _graph();
      var foot = 0, oneway = 0;
      for (var e = 0; e < g.edgeCount; e++) {
        if (g.hasFlag(e, EdgeFlag.noCar)) foot++;
        if (g.hasFlag(e, EdgeFlag.oneway)) oneway++;
      }
      expect(foot, 1);
      expect(oneway, 1);
    });
  });

  group('serialisation', () {
    test('encode puis decode redonne le même graphe', () {
      final g = _graph();
      final back = RoutingGraph.decode(g.encode());
      expect(back.nodeCount, g.nodeCount);
      expect(back.edgeCount, g.edgeCount);
      expect(back.names, g.names);
      expect(back.edgeLen.toList(), g.edgeLen.toList());
      expect(back.bounds.north, g.bounds.north);
    });

    test('détecte un fichier corrompu', () {
      final bytes = _graph().encode();
      expect(() => RoutingGraph.decode(bytes.sublist(0, 30)), throwsFormatException);
      final bad = bytes.sublist(0)..[0] = 0;
      expect(() => RoutingGraph.decode(bad), throwsFormatException);
      expect(() => RoutingGraph.decode(bytes.sublist(0, bytes.length - 40)), throwsA(anything));
    });
  });

  group('local_router', () {
    test('voiture : tourne à gauche sur l\'avenue Nord', () {
      final g = _graph();
      final r = LocalRouter.computeRoute(g, [const GeoPoint(45.0, 5.0005), const GeoPoint(45.0045, 5.005)], TravelMode.car, const RoutePrefs());
      expect(r.distanceM, closeTo(45 * 0 + 0.0045 * 111195 + 0.0045 * 78600, 120));
      expect(r.maneuvers.first.type, 1);
      expect(r.maneuvers.last.type, 4);
      expect(r.maneuvers.last.isFinal, isTrue);
      expect(r.maneuvers.any((m) => m.type == 15 || m.type == 16), isTrue);
      expect(r.shape.length, greaterThan(2));
    });

    test('voiture : respecte le sens unique', () {
      final g = _graph();
      // De 5 vers 3 est interdit ; il n'y a pas d'autre route : aucun itinéraire.
      expect(
        () => LocalRouter.computeRoute(g, [const GeoPoint(45.005, 5.0099), const GeoPoint(45.0, 5.0099)], TravelMode.car, const RoutePrefs()),
        throwsA(isA<Failure>()),
      );
      // De 3 vers 5 est autorisé.
      final ok = LocalRouter.computeRoute(g, [const GeoPoint(45.0, 5.0099), const GeoPoint(45.005, 5.0099)], TravelMode.car, const RoutePrefs());
      expect(ok.distanceM, greaterThan(400));
    });

    test('voiture : ne prend pas le chemin piéton, la marche oui', () {
      final g = _graph();
      expect(
        () => LocalRouter.computeRoute(g, [const GeoPoint(45.0, 5.0), const GeoPoint(44.992, 5.0)], TravelMode.car, const RoutePrefs()),
        throwsA(isA<Failure>()),
      );
      final walk = LocalRouter.computeRoute(g, [const GeoPoint(45.0, 5.0), const GeoPoint(44.992, 5.0)], TravelMode.walk, const RoutePrefs());
      expect(walk.distanceM, closeTo(890, 15));
      expect(walk.durationS, closeTo(890 / (5.1 / 3.6), 15));
    });

    test('départ et arrivée sur la même arête', () {
      final g = _graph();
      final r = LocalRouter.computeRoute(g, [const GeoPoint(45.0, 5.001), const GeoPoint(45.0, 5.003)], TravelMode.car, const RoutePrefs());
      expect(r.distanceM, closeTo(0.002 * 78600, 10));
      expect(r.maneuvers.length, 2);
    });

    test('étape intermédiaire : une manœuvre d\'étape est ajoutée', () {
      final g = _graph();
      final r = LocalRouter.computeRoute(
        g,
        [const GeoPoint(45.0, 5.001), const GeoPoint(45.0, 5.009), const GeoPoint(45.0045, 5.005)],
        TravelMode.car,
        const RoutePrefs(),
      );
      expect(r.maneuvers.where((m) => m.isWaypoint).length, 1);
      expect(r.waypointIndices.length, 1);
    });

    test('point trop éloigné du réseau : erreur claire', () {
      final g = _graph();
      expect(
        () => LocalRouter.computeRoute(g, [const GeoPoint(45.0, 5.0), const GeoPoint(45.009, 5.019)], TravelMode.car, const RoutePrefs()),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'offline_snap_failed')),
      );
    });

    test('transports en commun : refusés hors connexion', () async {
      final router = LocalRouter(() => [_graph()]);
      expect(router.available, isTrue);
      await expectLater(
        router.route([const GeoPoint(45.0, 5.0), const GeoPoint(45.0, 5.01)], TravelMode.transit, const RoutePrefs()),
        throwsA(isA<Failure>()),
      );
    });

    test('aucune zone téléchargée : erreur explicite', () async {
      final router = LocalRouter(() => const []);
      expect(router.available, isFalse);
      await expectLater(
        router.route([const GeoPoint(45.0, 5.0), const GeoPoint(45.0, 5.01)], TravelMode.car, const RoutePrefs()),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'offline_graph_missing')),
      );
    });
  });
}
