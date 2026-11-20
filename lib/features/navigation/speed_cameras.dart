import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/geo_backend.dart';
import 'package:strasse/data/providers/overpass_poi_client.dart';
import 'package:strasse/domain/domain.dart';

/// Ce que la loi du pays traversé autorise pour l'alerte de contrôles de vitesse.
enum CameraPolicy {
  /// Alerte interdite ou incertaine : aucune alerte n'est donnée (défaut prudent).
  none,

  /// France : seules les « zones de danger » peuvent être signalées, sans position précise de radar.
  dangerZoneOnly,

  /// Alerte de position autorisée.
  allowed,
}

/// Politique par zone géographique. Les zones sont des rectangles approximatifs ; en cas de chevauchement (frontières),
/// la politique la plus restrictive s'applique. En dehors des zones connues : aucune alerte.
/// Ce tableau résume le droit tel que Strasse le comprend ; il ne remplace pas un avis juridique, et l'utilisateur peut
/// désactiver les alertes dans les réglages.
class CameraPolicies {
  const CameraPolicies._();

  static const _zones = <({String name, double s, double w, double n, double e, CameraPolicy policy})>[
    (name: 'FR', s: 41.3, w: -5.3, n: 51.2, e: 9.7, policy: CameraPolicy.dangerZoneOnly),
    (name: 'DE', s: 47.2, w: 5.8, n: 55.1, e: 15.1, policy: CameraPolicy.none),
    (name: 'CH', s: 45.8, w: 5.9, n: 47.9, e: 10.6, policy: CameraPolicy.none),
    (name: 'AT', s: 46.3, w: 9.5, n: 49.1, e: 17.2, policy: CameraPolicy.none),
    (name: 'GB', s: 49.8, w: -8.7, n: 60.9, e: 1.8, policy: CameraPolicy.allowed),
    (name: 'IE', s: 51.3, w: -10.7, n: 55.5, e: -5.9, policy: CameraPolicy.allowed),
    (name: 'IT', s: 36.5, w: 6.6, n: 47.1, e: 18.6, policy: CameraPolicy.allowed),
    (name: 'ES', s: 35.9, w: -9.4, n: 43.9, e: 4.4, policy: CameraPolicy.allowed),
  ];

  static int _rank(CameraPolicy p) => switch (p) { CameraPolicy.none => 0, CameraPolicy.dangerZoneOnly => 1, CameraPolicy.allowed => 2 };

  static CameraPolicy at(GeoPoint p) {
    CameraPolicy? best;
    for (final z in _zones) {
      if (p.lat >= z.s && p.lat <= z.n && p.lon >= z.w && p.lon <= z.e) {
        if (best == null || _rank(z.policy) < _rank(best)) best = z.policy;
      }
    }
    return best ?? CameraPolicy.none;
  }
}

/// Point de contrôle de vitesse issu d'OpenStreetMap (`highway=speed_camera`). Données collaboratives : la position
/// n'est pas vérifiée officiellement et la liste n'est pas exhaustive.
class SpeedCamera {
  const SpeedCamera({required this.id, required this.point, this.maxSpeedKmh, this.directionDeg, required this.alongM});
  final String id;
  final GeoPoint point;
  final int? maxSpeedKmh;
  final double? directionDeg;

  /// Distance depuis le début de l'itinéraire, mesurée le long de celui-ci.
  final double alongM;
}

class CameraWarning {
  const CameraWarning({required this.camera, required this.distanceM, required this.policy});
  final SpeedCamera camera;
  final double distanceM;
  final CameraPolicy policy;

  /// Message à afficher/prononcer. En France, jamais le mot « radar » ni la position : zone de danger uniquement.
  String get message {
    final d = distanceM >= 1000 ? '${(distanceM / 1000).toStringAsFixed(1)} km' : '${(distanceM / 50).round() * 50} m';
    if (policy == CameraPolicy.dangerZoneOnly) return 'Zone de danger dans $d';
    final lim = camera.maxSpeedKmh == null ? '' : ' · ${camera.maxSpeedKmh} km/h';
    return 'Contrôle de vitesse (non vérifié) dans $d$lim';
  }
}

/// Interroge Overpass pour les points `highway=speed_camera` le long d'un itinéraire, puis les associe à celui-ci.
class SpeedCameraClient {
  SpeedCameraClient(this.endpoints, {Dio? dio, String userAgent = ''})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 30),
              responseType: ResponseType.json,
              headers: {'Accept': 'application/json', if (userAgent.isNotEmpty) 'User-Agent': userAgent},
            ));

  final List<String> endpoints;
  final Dio _dio;
  static final TtlCache<List<SpeedCamera>> _cache = TtlCache(ttl: const Duration(hours: 6), maxEntries: 20);

  /// Distance maximale entre un contrôle et l'axe de l'itinéraire pour qu'il soit retenu.
  static const double maxOffsetM = 35;

  /// Longueur maximale d'itinéraire interrogée (au-delà : seuls les premiers kilomètres, le reste à la volée serait trop lourd).
  static const double maxRouteM = 400000;

  static List<GeoPoint> _sample(List<GeoPoint> shape, double stepM) {
    if (shape.length < 2) return shape;
    final out = <GeoPoint>[shape.first];
    var acc = 0.0;
    for (var i = 1; i < shape.length; i++) {
      acc += distanceM(shape[i - 1], shape[i]);
      if (acc >= stepM) {
        out.add(shape[i]);
        acc = 0;
      }
    }
    if (out.last != shape.last) out.add(shape.last);
    return out;
  }

  static String buildQuery(List<GeoPoint> chunk) {
    final line = chunk.map((p) => '${p.lat.toStringAsFixed(5)},${p.lon.toStringAsFixed(5)}').join(',');
    return '[out:json][timeout:25];node["highway"="speed_camera"](around:${maxOffsetM.round()},$line);out tags center 400;';
  }

  Future<List<SpeedCamera>> along(List<GeoPoint> shape, {CancelToken? cancel}) async {
    if (endpoints.isEmpty || shape.length < 2) return const [];
    final key = '${shape.first.lat.toStringAsFixed(3)},${shape.first.lon.toStringAsFixed(3)}>${shape.last.lat.toStringAsFixed(3)},${shape.last.lon.toStringAsFixed(3)}|${shape.length}';
    final cached = _cache.get(key);
    if (cached != null) return cached;

    // Distances cumulées le long de l'itinéraire.
    final cum = <double>[0];
    for (var i = 1; i < shape.length; i++) {
      cum.add(cum.last + distanceM(shape[i - 1], shape[i]));
    }
    final usable = <GeoPoint>[];
    for (var i = 0; i < shape.length; i++) {
      if (cum[i] > maxRouteM) break;
      usable.add(shape[i]);
    }
    final pts = _sample(usable, 150);
    final found = <String, Map>{};
    for (var i = 0; i < pts.length - 1; i += 80) {
      final chunk = pts.sublist(i, math.min(i + 81, pts.length));
      if (chunk.length < 2) continue;
      final query = buildQuery(chunk);
      final data = await FailoverRunner.run(endpoints, (k) => OverpassPoiClient.sharedGate.run(() async {
            try {
              final r = await _dio.post<Object>(endpoints[k], data: 'data=${Uri.encodeQueryComponent(query)}', options: Options(contentType: Headers.formUrlEncodedContentType), cancelToken: cancel);
              return r.data;
            } on DioException catch (e) {
              throw Failure.fromDio(e);
            }
          }));
      if (data is Map && data['elements'] is List) {
        for (final e in data['elements'] as List) {
          if (e is Map && e['id'] != null) found['${e['id']}'] = e;
        }
      }
    }
    final out = <SpeedCamera>[];
    for (final e in found.values) {
      final lat = (e['lat'] as num?)?.toDouble();
      final lon = (e['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      final p = GeoPoint(lat, lon);
      final snap = _snap(shape, cum, p);
      if (snap == null) continue;
      final tags = e['tags'] is Map ? e['tags'] as Map : const {};
      final dir = double.tryParse('${tags['direction'] ?? tags['camera:direction'] ?? ''}');
      // Contrôle orienté dans le sens contraire de notre marche : il ne nous concerne pas.
      if (dir != null && _angleDiff(dir, snap.bearing) > 100) continue;
      out.add(SpeedCamera(id: '${e['id']}', point: p, maxSpeedKmh: int.tryParse('${tags['maxspeed'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '')), directionDeg: dir, alongM: snap.alongM));
    }
    out.sort((a, b) => a.alongM.compareTo(b.alongM));
    _cache.put(key, out);
    return out;
  }

  static double _angleDiff(double a, double b) {
    var d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  static ({double alongM, double bearing})? _snap(List<GeoPoint> shape, List<double> cum, GeoPoint p) {
    var best = double.infinity;
    double along = 0, bearing = 0;
    for (var i = 0; i < shape.length - 1; i++) {
      final a = shape[i], b = shape[i + 1];
      final mLat = 111320.0, mLon = 111320.0 * math.cos(a.lat * math.pi / 180);
      final ax = 0.0, ay = 0.0;
      final bx = (b.lon - a.lon) * mLon, by = (b.lat - a.lat) * mLat;
      final px = (p.lon - a.lon) * mLon, py = (p.lat - a.lat) * mLat;
      final len2 = bx * bx + by * by;
      final t = len2 == 0 ? 0.0 : (((px - ax) * bx + (py - ay) * by) / len2).clamp(0.0, 1.0);
      final dx = px - bx * t, dy = py - by * t;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d < best) {
        best = d;
        along = cum[i] + math.sqrt(len2) * t;
        bearing = (math.atan2(bx, by) * 180 / math.pi + 360) % 360;
      }
    }
    return best <= maxOffsetM ? (alongM: along, bearing: bearing) : null;
  }
}

/// Suit la progression sur l'itinéraire et indique le prochain contrôle à signaler, selon la loi locale.
class SpeedCameraTracker {
  SpeedCameraTracker(this.cameras);
  final List<SpeedCamera> cameras;

  /// Distance d'alerte anticipée (m) : plus longue quand on roule vite, pour laisser le temps de réagir.
  static double leadDistanceM(double speedKmh) => (speedKmh * 3.6 * 12).clamp(400.0, 1200.0).toDouble();

  CameraWarning? next(double alongM, double speedKmh) {
    final lead = leadDistanceM(speedKmh);
    for (final c in cameras) {
      final d = c.alongM - alongM;
      if (d < -20) continue;
      if (d > lead) return null;
      final policy = CameraPolicies.at(c.point);
      if (policy == CameraPolicy.none) continue;
      return CameraWarning(camera: c, distanceM: math.max(0, d), policy: policy);
    }
    return null;
  }
}
