import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:strasse/core/core.dart';
import 'package:strasse/features/offline_routing/routing_graph.dart';

/// Requête Overpass récupérant les voies praticables d'une zone, avec leurs nœuds (format JSON « skel »).
String overpassQuery(GeoBounds b, {int timeoutS = 180}) {
  final box = '${b.south.toStringAsFixed(6)},${b.west.toStringAsFixed(6)},${b.north.toStringAsFixed(6)},${b.east.toStringAsFixed(6)}';
  const classes = 'motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|unclassified|residential|living_street|service|road|track|cycleway|path|footway|pedestrian|steps|bridleway';
  return '[out:json][timeout:$timeoutS];way["highway"~"^($classes)\$"]($box);(._;>;);out body qt;';
}

class _RawWay {
  _RawWay(this.nodes, this.tags);
  final List<int> nodes;
  final Map<String, String> tags;
}

/// Convertit une réponse Overpass (JSON) en graphe. S'exécute dans un isolat : fonction de premier niveau.
/// Lève une [FormatException] si la réponse n'est pas exploitable.
RoutingGraph buildGraphFromOverpass(({String body, double south, double west, double north, double east}) args) {
  final decoded = jsonDecode(args.body);
  if (decoded is! Map<String, dynamic>) throw const FormatException('Réponse Overpass invalide.');
  final elements = decoded['elements'];
  if (elements is! List) throw const FormatException('Réponse Overpass sans éléments.');

  final nodeIndex = <int, int>{};
  final lats = <double>[];
  final lons = <double>[];
  final ways = <_RawWay>[];

  for (final e in elements) {
    if (e is! Map) continue;
    final type = e['type'];
    if (type == 'node') {
      final id = e['id'];
      final lat = e['lat'];
      final lon = e['lon'];
      if (id is int && lat is num && lon is num) {
        nodeIndex[id] = lats.length;
        lats.add(lat.toDouble());
        lons.add(lon.toDouble());
      }
    } else if (type == 'way') {
      final nds = e['nodes'];
      final tags = e['tags'];
      if (nds is List && tags is Map) {
        ways.add(_RawWay([for (final n in nds) if (n is int) n], {for (final en in tags.entries) en.key.toString(): en.value.toString()}));
      }
    }
  }
  if (ways.isEmpty) throw const FormatException('Aucune voie trouvée dans cette zone.');

  // Nombre d'utilisations de chaque nœud : > 1 => intersection.
  final use = <int, int>{};
  for (final w in ways) {
    for (final n in w.nodes) {
      use[n] = (use[n] ?? 0) + 1;
    }
  }

  final graphNode = <int, int>{}; // id OSM -> indice de nœud du graphe
  final nLat = <double>[];
  final nLon = <double>[];
  int junction(int osm) {
    final existing = graphNode[osm];
    if (existing != null) return existing;
    final i = nodeIndex[osm]!;
    graphNode[osm] = nLat.length;
    nLat.add(lats[i]);
    nLon.add(lons[i]);
    return nLat.length - 1;
  }

  final from = <int>[];
  final to = <int>[];
  final len = <double>[];
  final cls = <int>[];
  final flags = <int>[];
  final maxSpeed = <int>[];
  final nameIdx = <int>[];
  final geomStart = <int>[0];
  final gLat = <double>[];
  final gLon = <double>[];
  final names = <String>[''];
  final nameMap = <String, int>{'': 0};

  int nameId(String? n) {
    if (n == null || n.isEmpty) return 0;
    return nameMap.putIfAbsent(n, () {
      names.add(n);
      return names.length - 1;
    });
  }

  for (final w in ways) {
    final ci = highwayClassIndex(w.tags['highway']);
    if (ci < 0) continue;
    var nodes = w.nodes.where(nodeIndex.containsKey).toList();
    if (nodes.length < 2) continue;

    final f = _flagsFor(w.tags, ci);
    final oneway = w.tags['oneway'];
    if (oneway == '-1' || oneway == 'reverse') nodes = nodes.reversed.toList();
    final nm = nameId(w.tags['name'] ?? w.tags['ref']);
    final ms = _parseMaxSpeed(w.tags['maxspeed']);

    var segStart = 0;
    for (var i = 1; i < nodes.length; i++) {
      final isEnd = i == nodes.length - 1;
      if (!isEnd && (use[nodes[i]] ?? 0) < 2) continue;

      final a = junction(nodes[segStart]);
      final b = junction(nodes[i]);
      var length = 0.0;
      final startGeom = gLat.length;
      for (var k = segStart; k <= i; k++) {
        final idx = nodeIndex[nodes[k]]!;
        gLat.add(lats[idx]);
        gLon.add(lons[idx]);
        if (k > segStart) {
          final p = nodeIndex[nodes[k - 1]]!;
          length += distanceM(GeoPoint(lats[p], lons[p]), GeoPoint(lats[idx], lons[idx]));
        }
      }
      if (gLat.length - startGeom < 2) {
        gLat.length = startGeom;
        gLon.length = startGeom;
        segStart = i;
        continue;
      }
      from.add(a);
      to.add(b);
      len.add(length);
      cls.add(ci);
      flags.add(f);
      maxSpeed.add(ms);
      nameIdx.add(nm);
      geomStart.add(gLat.length);
      segStart = i;
    }
  }
  if (from.isEmpty) throw const FormatException('Le graphe routier de cette zone est vide.');

  return RoutingGraph(
    bounds: GeoBounds(south: args.south, west: args.west, north: args.north, east: args.east),
    nodeLat: Float64List.fromList(nLat),
    nodeLon: Float64List.fromList(nLon),
    edgeFrom: Int32List.fromList(from),
    edgeTo: Int32List.fromList(to),
    edgeLen: Float32List.fromList(len),
    edgeClass: Uint8List.fromList(cls),
    edgeFlags: Uint16List.fromList(flags),
    edgeMaxSpeed: Int16List.fromList(maxSpeed),
    edgeName: Int32List.fromList(nameIdx),
    geomStart: Int32List.fromList(geomStart),
    geomLat: Float64List.fromList(gLat),
    geomLon: Float64List.fromList(gLon),
    names: names,
  );
}

/// Variante testable : prend le texte JSON et les bornes.
RoutingGraph buildGraphFromJsonString(String body, GeoBounds b) =>
    buildGraphFromOverpass((body: body, south: b.south, west: b.west, north: b.north, east: b.east));

bool _yes(String? v) => v == 'yes' || v == 'true' || v == '1' || v == 'designated' || v == 'permissive';
bool _no(String? v) => v == 'no' || v == 'false' || v == '0';

int _flagsFor(Map<String, String> t, int ci) {
  final hw = kHighwayClasses[ci].$1;
  var f = 0;

  // Accès par défaut selon la classe de voie.
  const carForbidden = {'cycleway', 'path', 'footway', 'pedestrian', 'steps', 'bridleway', 'track'};
  const bikeForbidden = {'motorway', 'motorway_link', 'trunk', 'trunk_link', 'footway', 'pedestrian', 'steps', 'bridleway'};
  const walkForbidden = {'motorway', 'motorway_link'};
  if (carForbidden.contains(hw)) f |= EdgeFlag.noCar;
  if (bikeForbidden.contains(hw)) f |= EdgeFlag.noBike;
  if (walkForbidden.contains(hw)) f |= EdgeFlag.noWalk;
  if (hw == 'cycleway') f |= EdgeFlag.cycleway;
  if (hw == 'steps') f |= EdgeFlag.steps;
  if (hw == 'motorway' || hw == 'motorway_link') f |= EdgeFlag.motorway;

  // Surcharges par étiquettes.
  final access = t['access'];
  if (_no(access) || access == 'private') f |= EdgeFlag.noCar | EdgeFlag.noBike | EdgeFlag.noWalk;
  if (_no(t['motor_vehicle']) || t['motor_vehicle'] == 'private') f |= EdgeFlag.noCar;
  if (_no(t['motorcar']) || t['motorcar'] == 'private') f |= EdgeFlag.noCar;
  if (_no(t['vehicle'])) f |= EdgeFlag.noCar | EdgeFlag.noBike;
  if (_no(t['bicycle']) || t['bicycle'] == 'dismount') f |= EdgeFlag.noBike;
  if (_no(t['foot'])) f |= EdgeFlag.noWalk;
  if (_yes(t['bicycle'])) f &= ~EdgeFlag.noBike;
  if (_yes(t['foot'])) f &= ~EdgeFlag.noWalk;
  if (hw == 'service' && (t['service'] == 'parking_aisle' || t['service'] == 'driveway')) {
    // Accessibles mais à éviter : le coût les pénalise ailleurs ; on les garde.
  }
  if (t['toll'] == 'yes') f |= EdgeFlag.toll;

  // Sens unique.
  final ow = t['oneway'];
  final roundabout = t['junction'] == 'roundabout' || t['junction'] == 'circular';
  if (roundabout) f |= EdgeFlag.roundabout;
  if (_yes(ow) || ow == '-1' || ow == 'reverse' || roundabout || hw == 'motorway' || hw == 'motorway_link') {
    f |= EdgeFlag.oneway;
  }
  if (_no(t['oneway:bicycle']) || (t['cycleway']?.startsWith('opposite') ?? false) || (t['cycleway:both']?.startsWith('opposite') ?? false)) {
    f |= EdgeFlag.bikeTwoWay;
  }
  return f;
}

int _parseMaxSpeed(String? v) {
  if (v == null) return 0;
  final s = v.trim().toLowerCase();
  final m = RegExp(r'^(\d{1,3})\s*(mph|km/h)?$').firstMatch(s);
  if (m != null) {
    final n = int.parse(m.group(1)!);
    return m.group(2) == 'mph' ? (n * 1.609).round() : n;
  }
  if (s.endsWith(':urban')) return 50;
  if (s.endsWith(':rural')) return 80;
  if (s.endsWith(':motorway')) return 130;
  if (s == 'walk') return 7;
  return 0;
}

/// Taille maximale d'une zone pour le calcul d'itinéraires hors connexion (degrés de côté).
const double kMaxRoutingSpanDeg = 0.35;

double routingAreaKm2(GeoBounds b) {
  final h = b.latSpan * 111.32;
  final w = b.lonSpan * 111.32 * math.cos(b.center.lat * math.pi / 180);
  return h * w;
}
