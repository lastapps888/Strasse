import 'dart:math' as math;

const double earthRadiusM = 6371008.8;

double _rad(double d) => d * math.pi / 180.0;
double _deg(double r) => r * 180.0 / math.pi;

/// Point géographique (latitude, longitude) indépendant de toute bibliothèque de carte.
class GeoPoint {
  const GeoPoint(this.lat, this.lon);

  final double lat;
  final double lon;

  factory GeoPoint.fromJson(Map<String, dynamic> j) =>
      GeoPoint((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble());

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};

  @override
  bool operator ==(Object other) => other is GeoPoint && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'GeoPoint($lat, $lon)';
}

/// Rectangle géographique (sud-ouest / nord-est).
class GeoBounds {
  const GeoBounds({required this.south, required this.west, required this.north, required this.east});

  final double south;
  final double west;
  final double north;
  final double east;

  GeoPoint get center => GeoPoint((south + north) / 2, (west + east) / 2);
  double get latSpan => north - south;
  double get lonSpan => east - west;

  bool contains(GeoPoint p) => p.lat >= south && p.lat <= north && p.lon >= west && p.lon <= east;

  factory GeoBounds.fromPoints(Iterable<GeoPoint> pts) {
    var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
    for (final p in pts) {
      s = math.min(s, p.lat);
      n = math.max(n, p.lat);
      w = math.min(w, p.lon);
      e = math.max(e, p.lon);
    }
    return GeoBounds(south: s, west: w, north: n, east: e);
  }

  /// Boîte autour d'un point, de `meters` mètres de demi-côté.
  factory GeoBounds.around(GeoPoint c, double meters) {
    final dLat = _deg(meters / earthRadiusM);
    final dLon = dLat / math.max(0.01, math.cos(_rad(c.lat)));
    return GeoBounds(south: c.lat - dLat, west: c.lon - dLon, north: c.lat + dLat, east: c.lon + dLon);
  }

  /// Format attendu par l'API Strasse : minLon,minLat,maxLon,maxLat.
  String toBboxParam() => '${west.toStringAsFixed(5)},${south.toStringAsFixed(5)},${east.toStringAsFixed(5)},${north.toStringAsFixed(5)}';

  Map<String, dynamic> toJson() => {'south': south, 'west': west, 'north': north, 'east': east};

  factory GeoBounds.fromJson(Map<String, dynamic> j) => GeoBounds(
        south: (j['south'] as num).toDouble(),
        west: (j['west'] as num).toDouble(),
        north: (j['north'] as num).toDouble(),
        east: (j['east'] as num).toDouble(),
      );
}

/// Distance orthodromique en mètres (haversine).
double distanceM(GeoPoint a, GeoPoint b) {
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lon - a.lon);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(h.toDouble())));
}

/// Cap initial de a vers b, en degrés [0, 360).
double bearingDeg(GeoPoint a, GeoPoint b) {
  final dLon = _rad(b.lon - a.lon);
  final y = math.sin(dLon) * math.cos(_rad(b.lat));
  final x = math.cos(_rad(a.lat)) * math.sin(_rad(b.lat)) - math.sin(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.cos(dLon);
  return (_deg(math.atan2(y, x)) + 360) % 360;
}

/// Distances cumulées le long d'une polyligne (le premier élément vaut 0).
List<double> cumulativeDistances(List<GeoPoint> pts) {
  final out = List<double>.filled(pts.length, 0);
  for (var i = 1; i < pts.length; i++) {
    out[i] = out[i - 1] + distanceM(pts[i - 1], pts[i]);
  }
  return out;
}

/// Résultat de la projection d'un point sur une polyligne.
class Projection {
  const Projection({required this.segment, required this.t, required this.point, required this.distanceM});

  /// Indice du segment (entre `segment` et `segment + 1`).
  final int segment;

  /// Position le long du segment, entre 0 et 1.
  final double t;
  final GeoPoint point;

  /// Distance entre le point d'origine et sa projection.
  final double distanceM;
}

/// Projette `p` sur le segment [a, b] avec une approximation équirectangulaire locale.
({double t, GeoPoint point, double dist}) projectOnSegment(GeoPoint p, GeoPoint a, GeoPoint b) {
  final cosLat = math.cos(_rad(a.lat));
  final mPerDegLat = earthRadiusM * math.pi / 180.0;
  final mPerDegLon = mPerDegLat * cosLat;
  final ax = 0.0, ay = 0.0;
  final bx = (b.lon - a.lon) * mPerDegLon, by = (b.lat - a.lat) * mPerDegLat;
  final px = (p.lon - a.lon) * mPerDegLon, py = (p.lat - a.lat) * mPerDegLat;
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  var t = len2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final qx = ax + t * dx, qy = ay + t * dy;
  final dist = math.sqrt(math.pow(px - qx, 2) + math.pow(py - qy, 2));
  final point = GeoPoint(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
  return (t: t, point: point, dist: dist);
}

/// Projection de `p` sur la polyligne, en ne parcourant que les segments [from, to).
Projection projectOnPolyline(List<GeoPoint> pts, GeoPoint p, {int from = 0, int? to}) {
  if (pts.isEmpty) throw ArgumentError('Polyligne vide');
  if (pts.length == 1) {
    return Projection(segment: 0, t: 0, point: pts.first, distanceM: distanceM(p, pts.first));
  }
  final end = math.min(to ?? pts.length - 1, pts.length - 1);
  final start = math.max(0, math.min(from, end - 1));
  var best = Projection(segment: start, t: 0, point: pts[start], distanceM: double.infinity);
  for (var i = start; i < end; i++) {
    final r = projectOnSegment(p, pts[i], pts[i + 1]);
    if (r.dist < best.distanceM) {
      best = Projection(segment: i, t: r.t, point: r.point, distanceM: r.dist);
    }
  }
  return best;
}

/// Distance minimale entre `p` et la polyligne.
double distanceToPolylineM(List<GeoPoint> pts, GeoPoint p) => projectOnPolyline(pts, p).distanceM;

/// Décode une polyligne encodée (Valhalla : précision 6 ; Google/OTP : précision 5).
List<GeoPoint> decodePolyline(String encoded, {int precision = 6}) {
  final factor = math.pow(10, precision).toDouble();
  final out = <GeoPoint>[];
  var index = 0, lat = 0, lon = 0;
  while (index < encoded.length) {
    var shift = 0, result = 0, b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && index < encoded.length);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && index < encoded.length);
    lon += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    out.add(GeoPoint(lat / factor, lon / factor));
  }
  return out;
}

/// Encode une polyligne (utilisé pour stocker les itinéraires de l'historique de façon compacte).
String encodePolyline(List<GeoPoint> pts, {int precision = 6}) {
  final factor = math.pow(10, precision).toDouble();
  final sb = StringBuffer();
  var prevLat = 0, prevLon = 0;
  void write(int v) {
    var n = v < 0 ? ~(v << 1) : (v << 1);
    while (n >= 0x20) {
      sb.writeCharCode((0x20 | (n & 0x1f)) + 63);
      n >>= 5;
    }
    sb.writeCharCode(n + 63);
  }

  for (final p in pts) {
    final lat = (p.lat * factor).round();
    final lon = (p.lon * factor).round();
    write(lat - prevLat);
    write(lon - prevLon);
    prevLat = lat;
    prevLon = lon;
  }
  return sb.toString();
}

int _lon2tile(double lon, int z) => ((lon + 180.0) / 360.0 * (1 << z)).floor();
int _lat2tile(double lat, int z) {
  final r = _rad(lat.clamp(-85.0511, 85.0511));
  return ((1.0 - math.log(math.tan(r) + 1.0 / math.cos(r)) / math.pi) / 2.0 * (1 << z)).floor();
}

/// Nombre de tuiles du niveau [z] couvrant `b`.
int tileCountAt(GeoBounds b, int z) {
  final x0 = _lon2tile(b.west, z), x1 = _lon2tile(b.east, z);
  final y0 = _lat2tile(b.north, z), y1 = _lat2tile(b.south, z);
  return ((x1 - x0).abs() + 1) * ((y1 - y0).abs() + 1);
}

/// Nombre de tuiles couvrant `b` pour les niveaux de zoom [minZoom, maxZoom].
int estimateTileCount(GeoBounds b, int minZoom, int maxZoom) {
  var total = 0;
  for (var z = minZoom; z <= maxZoom; z++) {
    total += tileCountAt(b, z);
  }
  return total;
}

double _mercY(double lat) => math.log(math.tan(math.pi / 4 + _rad(lat.clamp(-85.0, 85.0)) / 2));
double _unMercY(double y) => (2 * math.atan(math.exp(y)) - math.pi / 2) * 180 / math.pi;

/// Sous-rectangle d'une vue cartographique, défini par des fractions de l'écran (0 à 1, le haut = 0).
/// La longitude est linéaire à l'écran ; la latitude suit la projection Web Mercator utilisée par la carte.
GeoBounds subBounds(GeoBounds view, {required double left, required double top, required double right, required double bottom}) {
  final yN = _mercY(view.north), yS = _mercY(view.south);
  double lat(double f) => _unMercY(yN + (yS - yN) * f);
  double lon(double f) => view.west + (view.east - view.west) * f;
  return GeoBounds(south: lat(bottom), west: lon(left), north: lat(top), east: lon(right));
}

/// Largeur (au milieu de la zone) et hauteur d'une zone, en kilomètres.
double boundsWidthKm(GeoBounds b) {
  final lat = (b.north + b.south) / 2;
  return distanceM(GeoPoint(lat, b.west), GeoPoint(lat, b.east)) / 1000;
}

double boundsHeightKm(GeoBounds b) => distanceM(GeoPoint(b.south, b.west), GeoPoint(b.north, b.west)) / 1000;

/// Angle normalisé dans [0, 360).
double normalizeDeg(double d) => ((d % 360) + 360) % 360;

/// Écart angulaire signé le plus court entre deux caps, dans [-180, 180].
double angleDiffDeg(double a, double b) {
  var d = normalizeDeg(a) - normalizeDeg(b);
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d;
}

/// Ordre de passage qui raccourcit le trajet à vol d'oiseau, le premier et le dernier point restant fixes.
/// Plus proche voisin puis améliorations 2-opt : bon résultat pour une dizaine de points, sans garantie d'optimum.
/// Retourne les indices des points dans le nouvel ordre.
List<int> optimizeWaypointOrder(List<GeoPoint> pts) {
  final n = pts.length;
  if (n <= 3) return List.generate(n, (i) => i);
  final remaining = [for (var i = 1; i < n - 1; i++) i];
  final order = <int>[0];
  while (remaining.isNotEmpty) {
    final last = pts[order.last];
    remaining.sort((a, b) => distanceM(last, pts[a]).compareTo(distanceM(last, pts[b])));
    order.add(remaining.removeAt(0));
  }
  order.add(n - 1);
  double d(int a, int b) => distanceM(pts[order[a]], pts[order[b]]);
  var improved = true;
  while (improved) {
    improved = false;
    for (var i = 1; i < n - 2; i++) {
      for (var j = i + 1; j < n - 1; j++) {
        if (d(i - 1, j) + d(i, j + 1) + 1e-6 < d(i - 1, i) + d(j, j + 1)) {
          order.setRange(i, j + 1, order.sublist(i, j + 1).reversed.toList());
          improved = true;
        }
      }
    }
  }
  return order;
}
