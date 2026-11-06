import 'dart:math' as math;
import 'dart:typed_data';

import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/offline_routing/routing_graph.dart';
import 'package:strasse/features/routing/routing_service.dart';

/// Moteur d'itinéraires hors connexion : A* sur un graphe routier OpenStreetMap téléchargé sur l'appareil.
///
/// Limites assumées (documentées dans docs/OFFLINE.md) : pas de restrictions de virage, pas de trafic, pas d'altitude
/// (l'option « éviter les côtes » est ignorée), pas de transports en commun, pas d'alternatives, vitesses estimées.
class LocalRouter implements LocalRoutingBackend {
  LocalRouter(this._graphs);

  final List<RoutingGraph> Function() _graphs;

  @override
  bool get available => _graphs().isNotEmpty;

  RoutingGraph? _graphFor(List<GeoPoint> pts) {
    for (final g in _graphs()) {
      if (pts.every(g.bounds.contains)) return g;
    }
    return null;
  }

  @override
  Future<List<RouteOption>> route(List<GeoPoint> points, TravelMode mode, RoutePrefs prefs) async {
    if (mode == TravelMode.transit) {
      throw const Failure(FailureKind.client, 'Les transports en commun ne sont pas disponibles hors connexion.');
    }
    if (points.length < 2) throw const Failure(FailureKind.client, 'Il faut au moins un départ et une arrivée.');
    final g = _graphFor(points);
    if (g == null) {
      throw const Failure(
        FailureKind.client,
        'Hors connexion : aucune zone d\'itinéraires téléchargée ne contient le départ, les étapes et l\'arrivée. '
        'Téléchargez les itinéraires de la zone dans Réglages > Cartes hors connexion.',
        code: 'offline_graph_missing',
      );
    }
    return [computeRoute(g, points, mode, prefs)];
  }

  /// Calcul synchrone, exposé pour les tests.
  static RouteOption computeRoute(RoutingGraph g, List<GeoPoint> points, TravelMode mode, RoutePrefs prefs) {
    final cost = _Cost(g, mode, prefs);
    final snaps = [for (final p in points) _snap(g, cost, p)];

    final steps = <_Step>[];
    final waypointStepEnds = <int>[]; // nombre de pas cumulés à chaque étape intermédiaire
    for (var i = 0; i < snaps.length - 1; i++) {
      final leg = _search(g, cost, snaps[i], snaps[i + 1]);
      if (leg == null) {
        throw const Failure(
          FailureKind.client,
          'Aucun itinéraire trouvé dans les données téléchargées entre ces points (zone non connectée ou voies inaccessibles pour ce mode).',
          code: 'offline_no_route',
        );
      }
      steps.addAll(leg);
      if (i < snaps.length - 2) waypointStepEnds.add(steps.length);
    }
    return _assemble(g, cost, mode, steps, waypointStepEnds, points);
  }

  // ---------------------------------------------------------------------------------- Accrochage

  static _Snap _snap(RoutingGraph g, _Cost cost, GeoPoint p) {
    _Snap? best;
    for (final ring in const [1, 2, 4, 8]) {
      for (final e in g.candidateEdges(p, ring: ring)) {
        if (!cost.usable(e)) continue;
        final pts = [for (var i = g.geomStart[e]; i < g.geomStart[e + 1]; i++) g.geomPoint(i)];
        final pr = projectOnPolyline(pts, p);
        if (best == null || pr.distanceM < best.dist) {
          final cum = cumulativeDistances(pts);
          final segLen = cum[pr.segment + 1] - cum[pr.segment];
          best = _Snap(e, pr.segment, pr.t, pr.point, cum[pr.segment] + pr.t * segLen, pr.distanceM, cum.last);
        }
      }
      if (best != null) break;
    }
    if (best == null || best.dist > 600) {
      throw const Failure(
        FailureKind.client,
        'Ce point est trop éloigné des voies téléchargées pour ce mode de déplacement.',
        code: 'offline_snap_failed',
      );
    }
    return best;
  }

  // ------------------------------------------------------------------------------------------ A*

  static List<_Step>? _search(RoutingGraph g, _Cost cost, _Snap s, _Snap t) {
    final n = g.nodeCount;
    final dist = Float64List(n)..fillRange(0, n, double.infinity);
    final prevEdge = Int32List(n)..fillRange(0, n, -1);
    final prevFwd = Uint8List(n);
    final origin = Uint8List(n); // 1 : départ vers le nœud `from` de l'arête de départ ; 2 : vers `to`
    final heap = _Heap();
    final goal = t.point;
    final hFactor = cost.heuristicFactor;

    double h(int node) => distanceM(g.nodePoint(node), goal) * hFactor;

    final sFrom = g.edgeFrom[s.edge], sTo = g.edgeTo[s.edge];
    if (cost.allowed(s.edge, false)) {
      final c = cost.partial(s.edge, s.along);
      if (c < dist[sFrom]) {
        dist[sFrom] = c;
        origin[sFrom] = 1;
        heap.push(c + h(sFrom), c, sFrom);
      }
    }
    if (cost.allowed(s.edge, true)) {
      final c = cost.partial(s.edge, s.edgeLen - s.along);
      if (c < dist[sTo]) {
        dist[sTo] = c;
        origin[sTo] = 2;
        heap.push(c + h(sTo), c, sTo);
      }
    }

    // Cas particulier : départ et arrivée sur la même arête.
    double best = double.infinity;
    int bestNode = -1;
    int bestKind = 0; // 1 : on arrive par `from` et on avance ; 2 : on arrive par `to` et on recule ; 3 : direct sur l'arête
    if (s.edge == t.edge) {
      if (t.along >= s.along && cost.allowed(s.edge, true)) {
        best = cost.partial(s.edge, t.along - s.along);
        bestKind = 3;
      } else if (t.along < s.along && cost.allowed(s.edge, false)) {
        best = cost.partial(s.edge, s.along - t.along);
        bestKind = 3;
      }
    }

    final tFrom = g.edgeFrom[t.edge], tTo = g.edgeTo[t.edge];
    final finishFrom = cost.allowed(t.edge, true) ? cost.partial(t.edge, t.along) : double.infinity;
    final finishTo = cost.allowed(t.edge, false) ? cost.partial(t.edge, t.edgeLen - t.along) : double.infinity;

    while (heap.isNotEmpty) {
      final top = heap.pop();
      if (top.f >= best) break;
      final u = top.node;
      if (top.g > dist[u]) continue;

      if (u == tFrom && dist[u] + finishFrom < best) {
        best = dist[u] + finishFrom;
        bestNode = u;
        bestKind = 1;
      }
      if (u == tTo && dist[u] + finishTo < best) {
        best = dist[u] + finishTo;
        bestNode = u;
        bestKind = 2;
      }

      for (var k = g.adjStart[u]; k < g.adjStart[u + 1]; k++) {
        final e = g.adjEdge[k];
        final c = cost.edgeCost(e);
        if (g.edgeFrom[e] == u && cost.allowed(e, true)) {
          final v = g.edgeTo[e];
          final nd = dist[u] + c;
          if (nd < dist[v]) {
            dist[v] = nd;
            prevEdge[v] = e;
            prevFwd[v] = 1;
            heap.push(nd + h(v), nd, v);
          }
        }
        if (g.edgeTo[e] == u && cost.allowed(e, false)) {
          final v = g.edgeFrom[e];
          final nd = dist[u] + c;
          if (nd < dist[v]) {
            dist[v] = nd;
            prevEdge[v] = e;
            prevFwd[v] = 0;
            heap.push(nd + h(v), nd, v);
          }
        }
      }
    }

    if (best == double.infinity) return null;

    if (bestKind == 3) {
      return [_Step(s.edge, t.along >= s.along, _slice(g, s, t), (t.along - s.along).abs())];
    }

    // Reconstruction du chemin.
    final path = <_Step>[];
    var node = bestNode;
    while (prevEdge[node] != -1) {
      final e = prevEdge[node];
      final fwd = prevFwd[node] == 1;
      path.add(_Step(e, fwd, _edgePoints(g, e, fwd), g.edgeLen[e].toDouble()));
      node = fwd ? g.edgeFrom[e] : g.edgeTo[e];
    }
    final steps = <_Step>[];
    // Début : portion de l'arête de départ.
    if (origin[node] == 1) {
      steps.add(_Step(s.edge, false, _partialToFrom(g, s), s.along));
    } else {
      steps.add(_Step(s.edge, true, _partialToTo(g, s), s.edgeLen - s.along));
    }
    steps.addAll(path.reversed);
    // Fin : portion de l'arête d'arrivée.
    if (bestKind == 1) {
      steps.add(_Step(t.edge, true, _partialFromFrom(g, t), t.along));
    } else {
      steps.add(_Step(t.edge, false, _partialFromTo(g, t), t.edgeLen - t.along));
    }
    return steps;
  }

  // --------------------------------------------------------------------------------- Géométrie

  static List<GeoPoint> _edgePoints(RoutingGraph g, int e, bool fwd) {
    final pts = [for (var i = g.geomStart[e]; i < g.geomStart[e + 1]; i++) g.geomPoint(i)];
    return fwd ? pts : pts.reversed.toList();
  }

  /// Du point accroché vers le nœud `from`.
  static List<GeoPoint> _partialToFrom(RoutingGraph g, _Snap s) {
    final a = g.geomStart[s.edge];
    final out = <GeoPoint>[s.point];
    for (var i = a + s.seg; i >= a; i--) {
      out.add(g.geomPoint(i));
    }
    return out;
  }

  /// Du point accroché vers le nœud `to`.
  static List<GeoPoint> _partialToTo(RoutingGraph g, _Snap s) {
    final b = g.geomStart[s.edge + 1] - 1;
    final a = g.geomStart[s.edge];
    final out = <GeoPoint>[s.point];
    for (var i = a + s.seg + 1; i <= b; i++) {
      out.add(g.geomPoint(i));
    }
    return out;
  }

  /// Du nœud `from` jusqu'au point accroché.
  static List<GeoPoint> _partialFromFrom(RoutingGraph g, _Snap s) => _partialToFrom(g, s).reversed.toList();

  /// Du nœud `to` jusqu'au point accroché.
  static List<GeoPoint> _partialFromTo(RoutingGraph g, _Snap s) => _partialToTo(g, s).reversed.toList();

  /// Portion de géométrie entre deux points accrochés sur la même arête (dans le sens du déplacement).
  static List<GeoPoint> _slice(RoutingGraph g, _Snap s, _Snap t) {
    final a = g.geomStart[s.edge];
    if (t.along >= s.along) {
      final out = <GeoPoint>[s.point];
      for (var i = a + s.seg + 1; i <= a + t.seg; i++) {
        out.add(g.geomPoint(i));
      }
      out.add(t.point);
      return out;
    }
    final out = <GeoPoint>[s.point];
    for (var i = a + s.seg; i > a + t.seg; i--) {
      out.add(g.geomPoint(i));
    }
    out.add(t.point);
    return out;
  }

  // ------------------------------------------------------------------------ Assemblage et guidage

  static RouteOption _assemble(RoutingGraph g, _Cost cost, TravelMode mode, List<_Step> steps, List<int> waypointStepEnds, List<GeoPoint> requested) {
    final shape = <GeoPoint>[];
    final stepStartIdx = <int>[];
    var distance = 0.0;
    var duration = 0.0;
    var hasToll = false;
    var hasHighway = false;
    for (final st in steps) {
      stepStartIdx.add(shape.isEmpty ? 0 : shape.length - 1);
      for (final p in st.pts) {
        if (shape.isNotEmpty && shape.last == p) continue;
        shape.add(p);
      }
      distance += st.len;
      duration += cost.timeSeconds(st.edge, st.len);
      if (g.hasFlag(st.edge, EdgeFlag.toll)) hasToll = true;
      if (g.hasFlag(st.edge, EdgeFlag.motorway)) hasHighway = true;
    }
    final waypointIndices = [for (final i in waypointStepEnds) if (i < stepStartIdx.length) stepStartIdx[i]];

    final maneuvers = <Maneuver>[];
    final cum = cumulativeDistances(shape);

    String nameOf(int e) => g.names[g.edgeName[e]];

    String? cardinal(double b) {
      const n = ['le nord', 'le nord-est', 'l\'est', 'le sud-est', 'le sud', 'le sud-ouest', 'l\'ouest', 'le nord-ouest'];
      return n[((normalizeDeg(b) + 22.5) ~/ 45) % 8];
    }

    double headOut(_Step st) {
      final a = st.pts.first;
      for (final p in st.pts.skip(1)) {
        if (distanceM(a, p) >= 8) return bearingDeg(a, p);
      }
      return bearingDeg(a, st.pts.last);
    }

    double headIn(_Step st) {
      final z = st.pts.last;
      for (var i = st.pts.length - 2; i >= 0; i--) {
        if (distanceM(st.pts[i], z) >= 8) return bearingDeg(st.pts[i], z);
      }
      return bearingDeg(st.pts.first, z);
    }

    // Départ.
    final firstName = nameOf(steps.first.edge);
    final startHeading = headOut(steps.first);
    maneuvers.add(Maneuver(
      instruction: firstName.isEmpty ? 'Prenez la direction ${cardinal(startHeading)}' : 'Démarrez sur $firstName en direction de ${cardinal(startHeading)}',
      verbalPre: firstName.isEmpty ? 'Prenez la direction ${cardinal(startHeading)}' : 'Démarrez sur $firstName',
      type: 1,
      distanceM: 0,
      durationS: 0,
      beginIndex: 0,
      streetNames: firstName.isEmpty ? const [] : [firstName],
    ));

    for (var i = 1; i < steps.length; i++) {
      final prev = steps[i - 1];
      final cur = steps[i];
      final idx = stepStartIdx[i].clamp(0, shape.length - 1);
      final isWaypoint = waypointStepEnds.contains(i);
      if (isWaypoint) {
        maneuvers.add(Maneuver(instruction: 'Vous êtes arrivé à l\'étape.', verbalPre: 'Vous êtes arrivé à l\'étape', type: 4, distanceM: 0, durationS: 0, beginIndex: idx, isWaypoint: true));
        continue;
      }
      final angle = -angleDiffDeg(headIn(prev), headOut(cur)); // positif = virage à droite
      final prevName = nameOf(prev.edge), curName = nameOf(cur.edge);
      final nameChanged = curName != prevName;
      final alternatives = _alternativeCount(g, cost, prev, cur);
      final a = angle.abs();

      final strong = a >= 45;
      final significant = alternatives > 0 && (a >= 25 || (nameChanged && curName.isNotEmpty));
      if (!strong && !significant) continue;
      if (alternatives == 0 && !strong) continue;

      final right = angle > 0;
      late int type;
      late String phrase;
      if (a < 25) {
        type = 8;
        phrase = 'Continuez';
      } else if (a < 60) {
        type = right ? 9 : 16;
        phrase = right ? 'Tournez légèrement à droite' : 'Tournez légèrement à gauche';
      } else if (a < 120) {
        type = right ? 10 : 15;
        phrase = right ? 'Tournez à droite' : 'Tournez à gauche';
      } else if (a < 165) {
        type = right ? 11 : 14;
        phrase = right ? 'Tournez franchement à droite' : 'Tournez franchement à gauche';
      } else {
        type = right ? 12 : 13;
        phrase = 'Faites demi-tour';
      }
      final roundabout = g.hasFlag(cur.edge, EdgeFlag.roundabout) && !g.hasFlag(prev.edge, EdgeFlag.roundabout);
      if (roundabout) {
        type = 26;
        phrase = 'Entrez dans le rond-point';
      }
      final text = type == 12 || type == 13 ? phrase : (curName.isEmpty ? phrase : '$phrase sur $curName');
      maneuvers.add(Maneuver(
        instruction: text,
        verbalPre: text,
        type: type,
        distanceM: 0,
        durationS: 0,
        beginIndex: idx,
        streetNames: curName.isEmpty ? const [] : [curName],
      ));
    }

    maneuvers.add(Maneuver(
      instruction: 'Vous êtes arrivé à destination.',
      verbalPre: 'Vous êtes arrivé à destination',
      type: 4,
      distanceM: 0,
      durationS: 0,
      beginIndex: shape.length - 1,
      isFinal: true,
    ));

    // Distances et durées des manœuvres (longueur du tronçon qui suit chaque manœuvre).
    final withLen = <Maneuver>[];
    for (var i = 0; i < maneuvers.length; i++) {
      final m = maneuvers[i];
      final endIdx = i + 1 < maneuvers.length ? maneuvers[i + 1].beginIndex : m.beginIndex;
      final d = (cum[endIdx.clamp(0, cum.length - 1)] - cum[m.beginIndex.clamp(0, cum.length - 1)]).clamp(0.0, double.infinity);
      withLen.add(Maneuver(
        instruction: m.instruction,
        verbalPre: m.verbalPre,
        type: m.type,
        distanceM: d,
        durationS: distance <= 0 ? 0 : duration * d / distance,
        beginIndex: m.beginIndex,
        streetNames: m.streetNames,
        isFinal: m.isFinal,
        isWaypoint: m.isWaypoint,
      ));
    }

    return RouteOption(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      mode: mode,
      shape: shape,
      distanceM: distance,
      durationS: duration,
      maneuvers: withLen,
      hasToll: hasToll,
      hasHighway: hasHighway,
      label: 'Hors connexion',
      waypointIndices: waypointIndices,
    );
  }

  /// Nombre de voies praticables, autres que celle d'où l'on vient et celle où l'on va, au nœud de jonction.
  static int _alternativeCount(RoutingGraph g, _Cost cost, _Step prev, _Step cur) {
    final node = prev.fwd ? g.edgeTo[prev.edge] : g.edgeFrom[prev.edge];
    var n = 0;
    for (var k = g.adjStart[node]; k < g.adjStart[node + 1]; k++) {
      final e = g.adjEdge[k];
      if (e == prev.edge || e == cur.edge) continue;
      if (cost.usable(e)) n++;
    }
    return n;
  }
}

// ------------------------------------------------------------------------------ Types internes

class _Snap {
  _Snap(this.edge, this.seg, this.t, this.point, this.along, this.dist, this.edgeLen);
  final int edge;
  final int seg;
  final double t;
  final GeoPoint point;

  /// Distance (m) le long de l'arête depuis son nœud `from`.
  final double along;
  final double dist;
  final double edgeLen;
}

class _Step {
  _Step(this.edge, this.fwd, this.pts, this.len);
  final int edge;
  final bool fwd;
  final List<GeoPoint> pts;
  final double len;
}

/// Coûts par mode de déplacement.
class _Cost {
  _Cost(this.g, this.mode, this.p);
  final RoutingGraph g;
  final TravelMode mode;
  final RoutePrefs p;

  bool get _shortest => p.criterion == RouteCriterion.shortest;

  /// Arête utilisable dans au moins un sens.
  bool usable(int e) => allowed(e, true) || allowed(e, false);

  bool allowed(int e, bool fwd) {
    final f = g.edgeFlags[e];
    switch (mode) {
      case TravelMode.car:
        if ((f & EdgeFlag.noCar) != 0) return false;
        if ((f & EdgeFlag.oneway) != 0 && !fwd) return false;
        return true;
      case TravelMode.bike:
        if ((f & EdgeFlag.noBike) != 0) return false;
        if ((f & EdgeFlag.steps) != 0) return false;
        if ((f & EdgeFlag.oneway) != 0 && !fwd && (f & EdgeFlag.bikeTwoWay) == 0) return false;
        return true;
      case TravelMode.walk:
        if ((f & EdgeFlag.noWalk) != 0) return false;
        if ((f & EdgeFlag.steps) != 0 && p.avoidStairs) return false;
        return true;
      case TravelMode.transit:
        return false;
    }
  }

  double speedMps(int e) {
    final f = g.edgeFlags[e];
    switch (mode) {
      case TravelMode.car:
        final cls = kHighwayClasses[g.edgeClass[e]].$2;
        final ms = g.edgeMaxSpeed[e];
        var v = (ms > 0 ? ms : cls).toDouble().clamp(5.0, 130.0);
        if ((f & EdgeFlag.motorway) == 0) v *= 0.8; // feux, priorités, circulation
        return v / 3.6;
      case TravelMode.bike:
        final base = switch (p.bikeType) {
          BikeType.road => 21.0,
          BikeType.hybrid => 17.0,
          BikeType.city => 14.0,
          BikeType.cross => 16.0,
          BikeType.mountain => 13.0,
        };
        final track = g.edgeClass[e] == highwayClassIndex('track') || g.edgeClass[e] == highwayClassIndex('path');
        return (track ? base * 0.7 : base) / 3.6;
      case TravelMode.walk:
        final v = (f & EdgeFlag.steps) != 0 ? math.min(3.0, p.walkSpeedKmh) : p.walkSpeedKmh;
        return v / 3.6;
      case TravelMode.transit:
        return 1;
    }
  }

  double _multiplier(int e) {
    final f = g.edgeFlags[e];
    var m = 1.0;
    if (mode == TravelMode.car) {
      if ((f & EdgeFlag.toll) != 0 && (p.avoidTolls || (p.customTollUse != null && p.customTollUse! < 0.5))) m *= 20;
      if ((f & EdgeFlag.motorway) != 0) {
        if (p.avoidHighways) m *= 20;
        final use = p.customHighwayUse;
        if (use != null) m *= 1 + (1 - use) * 3;
      }
      final cls = kHighwayClasses[g.edgeClass[e]].$1;
      if (cls == 'service' || cls == 'track') m *= 1.5; // évite les accès privés et parkings quand c'est possible
    } else if (mode == TravelMode.bike) {
      final cls = kHighwayClasses[g.edgeClass[e]].$1;
      if ((f & EdgeFlag.cycleway) != 0) {
        if (p.preferCycleways) m *= 0.8;
      } else if (p.preferCycleways && (cls == 'primary' || cls == 'trunk' || cls == 'secondary')) {
        m *= 1.6;
      }
    } else if (mode == TravelMode.walk) {
      if ((f & EdgeFlag.steps) != 0) m *= 3;
    }
    return m;
  }

  /// Coût (secondes, ou mètres pour « plus court ») pour parcourir toute l'arête.
  double edgeCost(int e) {
    final len = g.edgeLen[e].toDouble();
    return (_shortest ? len : len / speedMps(e)) * _multiplier(e);
  }

  /// Coût d'une portion de longueur `meters` de l'arête.
  double partial(int e, double meters) {
    final len = g.edgeLen[e].toDouble();
    if (len <= 0) return 0;
    return edgeCost(e) * (meters / len).clamp(0.0, 1.0);
  }

  /// Durée réelle (sans pénalités) d'une portion.
  double timeSeconds(int e, double meters) => meters / speedMps(e);

  /// Facteur de l'heuristique : mètres -> coût minimal possible.
  double get heuristicFactor {
    final minMult = mode == TravelMode.bike && p.preferCycleways ? 0.8 : 1.0;
    if (_shortest) return minMult;
    final vmax = switch (mode) {
      TravelMode.car => 130 / 3.6,
      TravelMode.bike => 21 / 3.6,
      TravelMode.walk => math.max(p.walkSpeedKmh, 3) / 3.6,
      TravelMode.transit => 1.0,
    };
    return minMult / vmax;
  }
}

/// Tas binaire minimal (file de priorité) sans dépendance externe.
class _HeapEntry {
  _HeapEntry(this.f, this.g, this.node);
  final double f;
  final double g;
  final int node;
}

class _Heap {
  final List<_HeapEntry> _a = [];

  bool get isNotEmpty => _a.isNotEmpty;

  void push(double f, double g, int node) {
    _a.add(_HeapEntry(f, g, node));
    var i = _a.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_a[p].f <= _a[i].f) break;
      final tmp = _a[p];
      _a[p] = _a[i];
      _a[i] = tmp;
      i = p;
    }
  }

  _HeapEntry pop() {
    final top = _a.first;
    final last = _a.removeLast();
    if (_a.isNotEmpty) {
      _a[0] = last;
      var i = 0;
      final n = _a.length;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < n && _a[l].f < _a[m].f) m = l;
        if (r < n && _a[r].f < _a[m].f) m = r;
        if (m == i) break;
        final tmp = _a[m];
        _a[m] = _a[i];
        _a[i] = tmp;
        i = m;
      }
    }
    return top;
  }
}
