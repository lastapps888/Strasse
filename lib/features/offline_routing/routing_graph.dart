import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:strasse/core/core.dart';

/// Indicateurs d'une arête du graphe routier.
class EdgeFlag {
  const EdgeFlag._();
  static const oneway = 1; // sens unique (dans le sens de la géométrie) pour voiture et, sauf exception, vélo
  static const noCar = 2;
  static const noBike = 4;
  static const noWalk = 8;
  static const toll = 16;
  static const motorway = 32;
  static const cycleway = 64;
  static const steps = 128;
  static const bikeTwoWay = 256; // vélo autorisé à contresens d'un sens unique
  static const roundabout = 512;
}

/// Classes de voies OpenStreetMap retenues, avec la vitesse voiture par défaut (km/h).
const List<(String, int)> kHighwayClasses = [
  ('motorway', 110),
  ('motorway_link', 60),
  ('trunk', 90),
  ('trunk_link', 50),
  ('primary', 70),
  ('primary_link', 40),
  ('secondary', 60),
  ('secondary_link', 40),
  ('tertiary', 50),
  ('tertiary_link', 35),
  ('unclassified', 40),
  ('residential', 30),
  ('living_street', 10),
  ('service', 20),
  ('road', 30),
  ('track', 15),
  ('cycleway', 20),
  ('path', 10),
  ('footway', 5),
  ('pedestrian', 5),
  ('steps', 3),
  ('bridleway', 5),
];

int highwayClassIndex(String? v) {
  if (v == null) return -1;
  for (var i = 0; i < kHighwayClasses.length; i++) {
    if (kHighwayClasses[i].$1 == v) return i;
  }
  return -1;
}

/// Graphe routier compact (arêtes entre intersections, avec géométrie), stocké en tableaux typés.
/// Construit à partir de données OpenStreetMap ; ne contient ni restrictions de virage ni altitude.
class RoutingGraph {
  RoutingGraph({
    required this.bounds,
    required this.nodeLat,
    required this.nodeLon,
    required this.edgeFrom,
    required this.edgeTo,
    required this.edgeLen,
    required this.edgeClass,
    required this.edgeFlags,
    required this.edgeMaxSpeed,
    required this.edgeName,
    required this.geomStart,
    required this.geomLat,
    required this.geomLon,
    required this.names,
  }) {
    _buildAdjacency();
    _buildGrid();
  }

  final GeoBounds bounds;
  final Float64List nodeLat;
  final Float64List nodeLon;
  final Int32List edgeFrom;
  final Int32List edgeTo;
  final Float32List edgeLen;
  final Uint8List edgeClass;
  final Uint16List edgeFlags;
  final Int16List edgeMaxSpeed;
  final Int32List edgeName;

  /// geomStart[e]..geomStart[e+1] : indices des points de l'arête e dans geomLat/geomLon.
  final Int32List geomStart;
  final Float64List geomLat;
  final Float64List geomLon;
  final List<String> names;

  int get nodeCount => nodeLat.length;
  int get edgeCount => edgeFrom.length;

  late final Int32List adjStart;
  late final Int32List adjEdge;

  static const double _cell = 0.004; // ~450 m
  late final Map<int, List<int>> _grid;

  bool hasFlag(int e, int flag) => (edgeFlags[e] & flag) != 0;

  void _buildAdjacency() {
    final n = nodeCount;
    final deg = Int32List(n + 1);
    for (var e = 0; e < edgeCount; e++) {
      deg[edgeFrom[e] + 1]++;
      deg[edgeTo[e] + 1]++;
    }
    for (var i = 0; i < n; i++) {
      deg[i + 1] += deg[i];
    }
    adjStart = deg;
    final fill = Int32List(n);
    adjEdge = Int32List(adjStart[n]);
    for (var e = 0; e < edgeCount; e++) {
      final a = edgeFrom[e];
      final b = edgeTo[e];
      adjEdge[adjStart[a] + fill[a]++] = e;
      adjEdge[adjStart[b] + fill[b]++] = e;
    }
  }

  static int _key(int cx, int cy) => cx * 1000003 + cy;
  int _cx(double lon) => (lon / _cell).floor();
  int _cy(double lat) => (lat / _cell).floor();

  void _buildGrid() {
    final grid = <int, List<int>>{};
    void add(int cx, int cy, int e) {
      final l = grid.putIfAbsent(_key(cx, cy), () => <int>[]);
      if (l.isEmpty || l.last != e) l.add(e);
    }

    for (var e = 0; e < edgeCount; e++) {
      for (var i = geomStart[e]; i < geomStart[e + 1] - 1; i++) {
        final la = geomLat[i], lo = geomLon[i], lb = geomLat[i + 1], ob = geomLon[i + 1];
        final cells = math.max(1, (math.max((lb - la).abs(), (ob - lo).abs()) / (_cell / 2)).ceil());
        for (var s = 0; s <= cells; s++) {
          final t = s / cells;
          add(_cx(lo + (ob - lo) * t), _cy(la + (lb - la) * t), e);
        }
      }
    }
    _grid = grid;
  }

  /// Arêtes candidates autour d'un point, en élargissant l'anneau de cellules jusqu'à `maxRings`.
  Iterable<int> candidateEdges(GeoPoint p, {int ring = 1}) sync* {
    final cx = _cx(p.lon), cy = _cy(p.lat);
    final seen = <int>{};
    for (var dx = -ring; dx <= ring; dx++) {
      for (var dy = -ring; dy <= ring; dy++) {
        final l = _grid[_key(cx + dx, cy + dy)];
        if (l == null) continue;
        for (final e in l) {
          if (seen.add(e)) yield e;
        }
      }
    }
  }

  GeoPoint nodePoint(int n) => GeoPoint(nodeLat[n], nodeLon[n]);

  GeoPoint geomPoint(int i) => GeoPoint(geomLat[i], geomLon[i]);

  // ------------------------------------------------------------------------------ Sérialisation

  static const int _magic = 0x53544731; // « STG1 »

  Uint8List encode() {
    final nameBytes = utf8.encode(jsonEncode(names));
    final sizes = <int>[
      8 * 4, // en-tête : bornes
      nodeCount * 8 * 2,
      edgeCount * 4 * 2,
      edgeCount * 4,
      edgeCount,
      edgeCount * 2,
      edgeCount * 2,
      edgeCount * 4,
      (edgeCount + 1) * 4,
      geomLat.length * 8 * 2,
    ];
    final total = 16 + sizes.fold<int>(0, (a, b) => a + b) + 4 + nameBytes.length;
    final bd = ByteData(total);
    var o = 0;
    bd.setUint32(o, _magic, Endian.little);
    bd.setUint32(o + 4, nodeCount, Endian.little);
    bd.setUint32(o + 8, edgeCount, Endian.little);
    bd.setUint32(o + 12, geomLat.length, Endian.little);
    o += 16;
    bd.setFloat64(o, bounds.south, Endian.little);
    bd.setFloat64(o + 8, bounds.west, Endian.little);
    bd.setFloat64(o + 16, bounds.north, Endian.little);
    bd.setFloat64(o + 24, bounds.east, Endian.little);
    o += 32;
    for (var i = 0; i < nodeCount; i++) {
      bd.setFloat64(o, nodeLat[i], Endian.little);
      bd.setFloat64(o + 8, nodeLon[i], Endian.little);
      o += 16;
    }
    for (var i = 0; i < edgeCount; i++) {
      bd.setInt32(o, edgeFrom[i], Endian.little);
      bd.setInt32(o + 4, edgeTo[i], Endian.little);
      o += 8;
    }
    for (var i = 0; i < edgeCount; i++) {
      bd.setFloat32(o, edgeLen[i], Endian.little);
      o += 4;
    }
    for (var i = 0; i < edgeCount; i++) {
      bd.setUint8(o++, edgeClass[i]);
    }
    for (var i = 0; i < edgeCount; i++) {
      bd.setUint16(o, edgeFlags[i], Endian.little);
      o += 2;
    }
    for (var i = 0; i < edgeCount; i++) {
      bd.setInt16(o, edgeMaxSpeed[i], Endian.little);
      o += 2;
    }
    for (var i = 0; i < edgeCount; i++) {
      bd.setInt32(o, edgeName[i], Endian.little);
      o += 4;
    }
    for (var i = 0; i <= edgeCount; i++) {
      bd.setInt32(o, geomStart[i], Endian.little);
      o += 4;
    }
    for (var i = 0; i < geomLat.length; i++) {
      bd.setFloat64(o, geomLat[i], Endian.little);
      bd.setFloat64(o + 8, geomLon[i], Endian.little);
      o += 16;
    }
    bd.setUint32(o, nameBytes.length, Endian.little);
    o += 4;
    final out = bd.buffer.asUint8List();
    out.setRange(o, o + nameBytes.length, nameBytes);
    return out;
  }

  /// Relit un graphe écrit par [encode]. Lève une [FormatException] si le fichier est corrompu.
  static RoutingGraph decode(Uint8List bytes) {
    if (bytes.length < 48) throw const FormatException('Fichier de graphe trop court.');
    final bd = ByteData.sublistView(bytes);
    var o = 0;
    if (bd.getUint32(o, Endian.little) != _magic) throw const FormatException('Format de graphe inconnu.');
    final n = bd.getUint32(o + 4, Endian.little);
    final m = bd.getUint32(o + 8, Endian.little);
    final g = bd.getUint32(o + 12, Endian.little);
    final expected = 16 + 32 + n * 16 + m * 8 + m * 4 + m + m * 2 + m * 2 + m * 4 + (m + 1) * 4 + g * 16 + 4;
    if (bytes.length < expected) throw const FormatException('Fichier de graphe tronqué.');
    o += 16;
    final bounds = GeoBounds(
      south: bd.getFloat64(o, Endian.little),
      west: bd.getFloat64(o + 8, Endian.little),
      north: bd.getFloat64(o + 16, Endian.little),
      east: bd.getFloat64(o + 24, Endian.little),
    );
    o += 32;
    final nodeLat = Float64List(n), nodeLon = Float64List(n);
    for (var i = 0; i < n; i++) {
      nodeLat[i] = bd.getFloat64(o, Endian.little);
      nodeLon[i] = bd.getFloat64(o + 8, Endian.little);
      o += 16;
    }
    final from = Int32List(m), to = Int32List(m);
    for (var i = 0; i < m; i++) {
      from[i] = bd.getInt32(o, Endian.little);
      to[i] = bd.getInt32(o + 4, Endian.little);
      if (from[i] < 0 || from[i] >= n || to[i] < 0 || to[i] >= n) throw const FormatException('Graphe incohérent.');
      o += 8;
    }
    final len = Float32List(m);
    for (var i = 0; i < m; i++) {
      len[i] = bd.getFloat32(o, Endian.little);
      o += 4;
    }
    final cls = Uint8List(m);
    for (var i = 0; i < m; i++) {
      cls[i] = bd.getUint8(o++);
    }
    final flags = Uint16List(m);
    for (var i = 0; i < m; i++) {
      flags[i] = bd.getUint16(o, Endian.little);
      o += 2;
    }
    final ms = Int16List(m);
    for (var i = 0; i < m; i++) {
      ms[i] = bd.getInt16(o, Endian.little);
      o += 2;
    }
    final nm = Int32List(m);
    for (var i = 0; i < m; i++) {
      nm[i] = bd.getInt32(o, Endian.little);
      o += 4;
    }
    final gs = Int32List(m + 1);
    for (var i = 0; i <= m; i++) {
      gs[i] = bd.getInt32(o, Endian.little);
      o += 4;
    }
    if (gs[m] != g) throw const FormatException('Géométrie incohérente.');
    final gl = Float64List(g), go = Float64List(g);
    for (var i = 0; i < g; i++) {
      gl[i] = bd.getFloat64(o, Endian.little);
      go[i] = bd.getFloat64(o + 8, Endian.little);
      o += 16;
    }
    final nameLen = bd.getUint32(o, Endian.little);
    o += 4;
    if (o + nameLen > bytes.length) throw const FormatException('Noms de rues tronqués.');
    final decoded = jsonDecode(utf8.decode(Uint8List.sublistView(bytes, o, o + nameLen))) as List<dynamic>;
    return RoutingGraph(
      bounds: bounds,
      nodeLat: nodeLat,
      nodeLon: nodeLon,
      edgeFrom: from,
      edgeTo: to,
      edgeLen: len,
      edgeClass: cls,
      edgeFlags: flags,
      edgeMaxSpeed: ms,
      edgeName: nm,
      geomStart: gs,
      geomLat: gl,
      geomLon: go,
      names: decoded.map((e) => e as String).toList(growable: false),
    );
  }
}
