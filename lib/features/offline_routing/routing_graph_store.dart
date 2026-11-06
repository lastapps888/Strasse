import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/features/offline_routing/graph_builder.dart';
import 'package:strasse/features/offline_routing/routing_graph.dart';

enum RoutingZoneStatus { downloading, ready, failed }

/// Zone dont le réseau routier est stocké sur l'appareil pour calculer des itinéraires sans réseau.
class RoutingZone {
  const RoutingZone({
    required this.id,
    required this.name,
    required this.bounds,
    required this.status,
    required this.updatedAt,
    this.sizeBytes = 0,
    this.error,
  });

  final String id;
  final String name;
  final GeoBounds bounds;
  final RoutingZoneStatus status;
  final DateTime updatedAt;
  final int sizeBytes;
  final String? error;

  RoutingZone copyWith({RoutingZoneStatus? status, int? sizeBytes, String? error, DateTime? updatedAt, bool clearError = false}) => RoutingZone(
        id: id,
        name: name,
        bounds: bounds,
        status: status ?? this.status,
        updatedAt: updatedAt ?? this.updatedAt,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        error: clearError ? null : (error ?? this.error),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'south': bounds.south,
        'west': bounds.west,
        'north': bounds.north,
        'east': bounds.east,
        'status': status.name,
        'updatedAt': updatedAt.toIso8601String(),
        'sizeBytes': sizeBytes,
        'error': error,
      };

  static RoutingZone? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'];
    final s = j['south'], w = j['west'], n = j['north'], e = j['east'];
    if (id is! String || name is! String || s is! num || w is! num || n is! num || e is! num) return null;
    final st = RoutingZoneStatus.values.firstWhere((v) => v.name == j['status'], orElse: () => RoutingZoneStatus.failed);
    return RoutingZone(
      id: id,
      name: name,
      bounds: GeoBounds(south: s.toDouble(), west: w.toDouble(), north: n.toDouble(), east: e.toDouble()),
      status: st,
      updatedAt: DateTime.tryParse('${j['updatedAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      sizeBytes: j['sizeBytes'] is num ? (j['sizeBytes'] as num).toInt() : 0,
      error: j['error'] is String ? j['error'] as String : null,
    );
  }
}

/// Gère les graphes routiers locaux : téléchargement (Overpass), conversion en isolat, stockage, chargement en mémoire.
class RoutingGraphStore extends StateNotifier<List<RoutingZone>> {
  RoutingGraphStore({required this.directory, required this.overpassUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(minutes: 5),
              responseType: ResponseType.plain,
            )),
        super(const []);

  final Future<Directory> Function() directory;
  final String Function() overpassUrl;
  final Dio _dio;

  final Map<String, RoutingGraph> _loaded = {};
  final Map<String, CancelToken> _running = {};

  /// Graphes prêts, utilisables par [LocalRouter].
  List<RoutingGraph> graphs() => _loaded.values.toList(growable: false);

  Future<File> _file(String id) async => File('${(await directory()).path}/$id.stg');
  Future<File> _index() async => File('${(await directory()).path}/index.json');

  Future<void> load() async {
    try {
      final dir = await directory();
      if (!await dir.exists()) await dir.create(recursive: true);
      final idx = await _index();
      if (!await idx.exists()) return;
      final raw = jsonDecode(await idx.readAsString());
      final zones = <RoutingZone>[];
      if (raw is List) {
        for (final j in raw) {
          final z = RoutingZone.fromJson(j);
          if (z != null) zones.add(z);
        }
      }
      final fixed = <RoutingZone>[];
      for (final z in zones) {
        var zone = z;
        if (z.status == RoutingZoneStatus.downloading) {
          zone = z.copyWith(status: RoutingZoneStatus.failed, error: 'Téléchargement interrompu. Relancez-le.');
        } else if (z.status == RoutingZoneStatus.ready) {
          try {
            final bytes = await (await _file(z.id)).readAsBytes();
            _loaded[z.id] = await compute(_decode, bytes);
          } catch (_) {
            zone = z.copyWith(status: RoutingZoneStatus.failed, error: 'Données illisibles. Retéléchargez la zone.');
          }
        }
        fixed.add(zone);
      }
      state = fixed;
      await _saveIndex();
    } catch (_) {
      // Index illisible : on repart d'une liste vide, les fichiers orphelins sont ignorés.
      state = const [];
    }
  }

  Future<void> _saveIndex() async {
    try {
      final f = await _index();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode([for (final z in state) z.toJson()]), flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  bool isRunning(String id) => _running.containsKey(id);

  /// Zone d'itinéraires correspondant à une zone de carte, si elle existe.
  RoutingZone? byId(String id) {
    for (final z in state) {
      if (z.id == id) return z;
    }
    return null;
  }

  /// Contrôle la taille d'une zone avant téléchargement. Retourne un message d'erreur, ou null si elle est acceptable.
  static String? checkBounds(GeoBounds b) {
    if (b.latSpan > kMaxRoutingSpanDeg || b.lonSpan > kMaxRoutingSpanDeg) {
      return 'Zone trop grande pour les itinéraires hors connexion (maximum ${kMaxRoutingSpanDeg.toStringAsFixed(2)}° de côté, environ 35 km). Choisissez une zone plus petite.';
    }
    return null;
  }

  /// Télécharge le réseau routier de la zone et le stocke. [id] identifie la zone (réutiliser l'identifiant d'une région de carte).
  Future<void> download({required String id, required String name, required GeoBounds bounds}) async {
    if (_running.containsKey(id)) return;
    final url = overpassUrl();
    if (url.isEmpty) {
      throw Failure.notConfigured('Le serveur Overpass', hint: 'Renseignez-le dans Réglages > Services pour télécharger les itinéraires hors connexion.');
    }
    if (!url.startsWith('https://')) {
      throw const Failure(FailureKind.client, 'L\'adresse Overpass doit commencer par https://.');
    }
    final err = checkBounds(bounds);
    if (err != null) throw Failure(FailureKind.client, err);

    final token = CancelToken();
    _running[id] = token;
    final base = RoutingZone(id: id, name: name, bounds: bounds, status: RoutingZoneStatus.downloading, updatedAt: DateTime.now());
    state = [for (final z in state) if (z.id != id) z, base];
    await _saveIndex();

    try {
      final res = await _dio.post<String>(
        url,
        data: 'data=${Uri.encodeQueryComponent(overpassQuery(bounds))}',
        options: Options(contentType: Headers.formUrlEncodedContentType),
        cancelToken: token,
      );
      final body = res.data;
      if (res.statusCode != null && res.statusCode! >= 400) {
        throw Failure(FailureKind.server, 'Le serveur Overpass a répondu ${res.statusCode}. Réessayez plus tard ou choisissez une zone plus petite.');
      }
      if (body == null || body.isEmpty) throw const Failure(FailureKind.server, 'Réponse Overpass vide.');
      final bytes = await compute(_buildAndEncode, (body: body, south: bounds.south, west: bounds.west, north: bounds.north, east: bounds.east));
      final dir = await directory();
      if (!await dir.exists()) await dir.create(recursive: true);
      final f = await _file(id);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
      _loaded[id] = await compute(_decode, bytes);
      _set(id, (z) => z.copyWith(status: RoutingZoneStatus.ready, sizeBytes: bytes.length, updatedAt: DateTime.now(), clearError: true));
    } on DioException catch (e) {
      _loaded.remove(id);
      final cancelled = CancelToken.isCancel(e);
      _set(id, (z) => z.copyWith(status: RoutingZoneStatus.failed, error: cancelled ? 'Téléchargement annulé.' : Failure.fromDio(e).message));
      if (!cancelled) rethrow;
    } on FormatException catch (e) {
      _loaded.remove(id);
      _set(id, (z) => z.copyWith(status: RoutingZoneStatus.failed, error: e.message));
      throw Failure(FailureKind.server, e.message);
    } on Failure catch (f) {
      _loaded.remove(id);
      _set(id, (z) => z.copyWith(status: RoutingZoneStatus.failed, error: f.message));
      rethrow;
    } catch (e) {
      _loaded.remove(id);
      _set(id, (z) => z.copyWith(status: RoutingZoneStatus.failed, error: 'Échec du téléchargement.'));
      throw Failure(FailureKind.unknown, 'Échec du téléchargement des itinéraires : $e');
    } finally {
      _running.remove(id);
      await _saveIndex();
    }
  }

  void cancel(String id) => _running[id]?.cancel();

  Future<void> delete(String id) async {
    cancel(id);
    _loaded.remove(id);
    state = [for (final z in state) if (z.id != id) z];
    try {
      final f = await _file(id);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await _saveIndex();
  }

  void _set(String id, RoutingZone Function(RoutingZone) f) {
    state = [for (final z in state) z.id == id ? f(z) : z];
  }
}

// Fonctions de premier niveau pour `compute`.
Uint8List _buildAndEncode(({String body, double south, double west, double north, double east}) a) => buildGraphFromOverpass(a).encode();

RoutingGraph _decode(Uint8List bytes) => RoutingGraph.decode(bytes);
