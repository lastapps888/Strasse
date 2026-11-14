import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/geo_backend.dart';
import 'package:strasse/data/providers/overpass_poi_client.dart';
import 'package:strasse/domain/domain.dart';

/// Tracé des lignes de transport en commun d'après OpenStreetMap (relations `route=*` et remontées mécaniques).
///
/// Couvre bus, trolleybus, car, tram, métro, train (TER compris), funiculaire, bateau et télécabine, partout où
/// la ligne est cartographiée. Les horaires viennent d'un autre fournisseur (voir MotisTransitRouter).
class TransitLinesClient {
  TransitLinesClient(this.endpoints, {Dio? dio, String userAgent = ''})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 40),
              responseType: ResponseType.json,
              headers: {'Accept': 'application/json', if (userAgent.isNotEmpty) 'User-Agent': userAgent},
            ));

  final List<String> endpoints;
  final Dio _dio;

  static final TtlCache<List<TransitLine>> _cache = TtlCache(ttl: const Duration(minutes: 30), maxEntries: 30);

  /// Zone maximale (degrés) pour les lignes lourdes (rail, tram, métro…) puis pour les bus.
  static const double maxSpanHeavy = 0.35;
  static const double maxSpanBus = 0.07;

  bool get configured => endpoints.isNotEmpty;

  static const _heavy = 'tram|subway|light_rail|train|funicular|monorail|ferry';

  static String buildQuery(GeoBounds b, {required bool withBuses, int limit = 120}) {
    final box = '${b.south.toStringAsFixed(5)},${b.west.toStringAsFixed(5)},${b.north.toStringAsFixed(5)},${b.east.toStringAsFixed(5)}';
    final modes = withBuses ? '$_heavy|bus|trolleybus' : _heavy;
    return '[out:json][timeout:30];'
        '(relation["type"="route"]["route"~"^($modes)\$"]($box);'
        'way["aerialway"~"^(cable_car|gondola|mixed_lift|funicular)\$"]($box););'
        'out geom tags $limit;';
  }

  Future<List<TransitLine>> linesIn(GeoBounds b, {CancelToken? cancel}) async {
    if (!configured) throw Failure.notConfigured('Les données routières (Overpass)');
    final span = b.latSpan > b.lonSpan ? b.latSpan : b.lonSpan;
    if (span > maxSpanHeavy) {
      throw const Failure(FailureKind.client, 'Zoomez sur la carte pour afficher les lignes de transport.', code: 'zoom_in');
    }
    final withBuses = span <= maxSpanBus;
    final key = '${withBuses ? 'b' : 'h'}|${b.south.toStringAsFixed(2)},${b.west.toStringAsFixed(2)},${b.north.toStringAsFixed(2)},${b.east.toStringAsFixed(2)}';
    final cached = _cache.get(key);
    if (cached != null) return cached;
    final query = buildQuery(b, withBuses: withBuses);
    final data = await FailoverRunner.run(endpoints, (i) => OverpassPoiClient.sharedGate.run(() async {
          try {
            final r = await _dio.post<Object>(
              endpoints[i],
              data: 'data=${Uri.encodeQueryComponent(query)}',
              options: Options(contentType: Headers.formUrlEncodedContentType),
              cancelToken: cancel,
            );
            return r.data;
          } on DioException catch (e) {
            throw Failure.fromDio(e);
          }
        }));
    final lines = parse(data);
    _cache.put(key, lines);
    return lines;
  }

  static List<TransitLine> parse(Object? data) {
    if (data is! Map || data['elements'] is! List) throw const Failure(FailureKind.server, 'Réponse Overpass invalide.');
    final out = <TransitLine>[];
    for (final e in data['elements'] as List) {
      try {
        if (e is! Map) continue;
        final tags = Map<String, dynamic>.from((e['tags'] as Map?) ?? const {});
        String? t(String k) {
          final v = tags[k];
          return v is String && v.trim().isNotEmpty ? v.trim() : null;
        }

        final shapes = <List<GeoPoint>>[];
        List<GeoPoint>? geom(Object? g) {
          if (g is! List) return null;
          final pts = [for (final p in g) if (p is Map && p['lat'] is num && p['lon'] is num) GeoPoint((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble())];
          return pts.length >= 2 ? pts : null;
        }

        String mode;
        if (e['type'] == 'relation') {
          mode = t('route') ?? 'bus';
          for (final m in (e['members'] as List?) ?? const []) {
            if (m is Map && m['type'] == 'way' && (m['role'] == null || m['role'] == '' || m['role'] == 'route' || m['role'] == 'forward' || m['role'] == 'backward')) {
              final g = geom(m['geometry']);
              if (g != null) shapes.add(g);
            }
          }
        } else {
          mode = 'aerialway';
          final g = geom(e['geometry']);
          if (g != null) shapes.add(g);
        }
        if (shapes.isEmpty) continue;
        out.add(TransitLine(
          id: '${e['type']}/${e['id']}',
          mode: mode,
          ref: t('ref') ?? '',
          name: t('name'),
          colorHex: _color(t('colour') ?? t('color')),
          from: t('from'),
          to: t('to'),
          operator: t('operator') ?? t('network'),
          shapes: shapes,
        ));
      } catch (_) {
        // élément mal formé : ignoré
      }
    }
    return out;
  }

  /// Accepte `#RRGGBB`, `#RGB` ou quelques noms usuels ; renvoie null sinon (la couleur du mode est alors utilisée).
  static String? _color(String? c) {
    if (c == null) return null;
    final v = c.trim().toLowerCase();
    if (RegExp(r'^#[0-9a-f]{6}$').hasMatch(v)) return v;
    final m = RegExp(r'^#([0-9a-f])([0-9a-f])([0-9a-f])$').firstMatch(v);
    if (m != null) return '#${m[1]}${m[1]}${m[2]}${m[2]}${m[3]}${m[3]}';
    const names = {'red': '#d32f2f', 'blue': '#1976d2', 'green': '#388e3c', 'yellow': '#fbc02d', 'orange': '#f57c00', 'purple': '#7b1fa2', 'pink': '#c2185b', 'brown': '#6d4c41', 'grey': '#757575', 'gray': '#757575', 'black': '#212121'};
    return names[v];
  }
}
