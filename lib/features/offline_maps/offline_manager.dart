import 'dart:async';
import 'dart:io';

import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:path_provider/path_provider.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/repositories/offline_repository.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/notifications/notifications_service.dart';
import 'package:uuid/uuid.dart';

/// Taille moyenne estimée d'une tuile vectorielle (octets). L'estimation avant téléchargement reste approximative.
const int kAverageTileBytes = 28 * 1024;

/// Estimation de l'espace nécessaire à une région.
int estimateRegionBytes(GeoBounds b, int minZoom, int maxZoom) =>
    estimateTileCount(b, minZoom, maxZoom) * kAverageTileBytes;

/// Gestion des cartes téléchargées : téléchargement par région (tuiles, polices et style gérés par le moteur
/// cartographique natif, dans un stockage persistant), suivi de progression, vérification, mise à jour, suppression.
class OfflineManager extends StateNotifier<List<OfflineRegionInfo>> {
  OfflineManager({
    required this.repo,
    required this.notifications,
    required this.writeStyleFile,
    required this.notifyEnabled,
  }) : super(const []);

  final OfflineRepository repo;
  final NotificationsService notifications;

  /// Écrit le style courant dans un fichier et retourne son URI `file://` (le moteur natif exige une URL de style).
  final Future<String> Function() writeStyleFile;
  final bool Function() notifyEnabled;

  final Map<String, Completer<void>> _running = {};
  static const _uuid = Uuid();

  Future<void> load() async {
    final saved = await repo.all();
    // Les téléchargements interrompus (application fermée) sont marqués échoués : il faut les relancer.
    final fixed = <OfflineRegionInfo>[];
    for (final r in saved) {
      if (r.status == OfflineStatus.downloading && !_running.containsKey(r.id)) {
        final f = r.copyWith(status: OfflineStatus.failed, error: 'Téléchargement interrompu. Relancez-le.');
        await repo.save(f);
        fixed.add(f);
      } else {
        fixed.add(r);
      }
    }
    state = fixed;
    try {
      await ml.setOfflineTileCountLimit(1000000);
    } catch (_) {}
  }

  /// Espace disque libre en octets, ou null si l'appareil ne le communique pas.
  Future<int?> freeBytes() async {
    try {
      final mb = await DiskSpacePlus().getFreeDiskSpace;
      return mb == null ? null : (mb * 1024 * 1024).round();
    } catch (_) {
      return null;
    }
  }

  /// Espace occupé par le cache cartographique natif (recherche au mieux dans le stockage de l'application).
  Future<int?> storageUsedBytes() async {
    try {
      final dir = await getApplicationSupportDirectory();
      var total = 0;
      var found = false;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          final name = e.uri.pathSegments.last;
          if (name == 'mbgl-offline.db' || (name == 'cache.db' && e.path.contains('.mapbox'))) {
            total += await e.length();
            found = true;
          }
        }
      }
      return found ? total : null;
    } catch (_) {
      return null;
    }
  }

  /// Vérifie qu'une région est réellement présente dans le moteur natif avant de la déclarer disponible.
  Future<bool> verify(String id) async {
    final r = await repo.byId(id);
    if (r == null || !r.isComplete || r.nativeId == null) return false;
    try {
      final regions = await ml.getListOfRegions();
      final present = regions.any((n) => n.id == r.nativeId);
      if (!present) {
        final f = r.copyWith(status: OfflineStatus.failed, error: 'Données absentes de l\'appareil. Retéléchargez la région.');
        await repo.save(f);
        _replace(f);
      }
      return present;
    } catch (_) {
      return false;
    }
  }

  /// Vérifie toutes les régions au démarrage.
  Future<void> verifyAll() async {
    for (final r in List.of(state)) {
      if (r.isComplete) await verify(r.id);
    }
  }

  /// Région téléchargée couvrant un point (pour savoir si la zone est consultable hors connexion).
  OfflineRegionInfo? regionCovering(GeoPoint p) {
    for (final r in state) {
      if (r.isComplete && r.bounds.contains(p)) return r;
    }
    return null;
  }

  /// Lance le téléchargement. Retourne l'identifiant de la région. Refuse un doublon ou un espace insuffisant.
  Future<OfflineRegionInfo> download({
    required String name,
    required GeoBounds bounds,
    required int minZoom,
    required int maxZoom,
  }) async {
    final dup = await repo.coveringRegion(bounds, maxZoom);
    if (dup != null) {
      throw Failure(FailureKind.client, 'Cette zone est déjà téléchargée dans « ${dup.name} ».');
    }
    final estimate = estimateRegionBytes(bounds, minZoom, maxZoom);
    final free = await freeBytes();
    if (free != null && estimate * 1.2 > free) {
      throw Failure(
        FailureKind.storage,
        'Espace insuffisant : ${formatBytes(estimate)} estimés, ${formatBytes(free)} disponibles. Libérez de la place ou réduisez la zone.',
      );
    }
    final id = _uuid.v4();
    var info = OfflineRegionInfo(
      id: id,
      name: name,
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      status: OfflineStatus.downloading,
      updatedAt: DateTime.now(),
      sizeBytes: estimate,
    );
    await repo.save(info);
    state = [info, ...state];
    unawaited(_run(info));
    return info;
  }

  Future<void> _run(OfflineRegionInfo info) async {
    final done = Completer<void>();
    _running[info.id] = done;
    var current = info;
    try {
      final styleUrl = await writeStyleFile();
      final def = ml.OfflineRegionDefinition(
        bounds: ml.LatLngBounds(
          southwest: ml.LatLng(info.bounds.south, info.bounds.west),
          northeast: ml.LatLng(info.bounds.north, info.bounds.east),
        ),
        mapStyleUrl: styleUrl,
        minZoom: info.minZoom.toDouble(),
        maxZoom: info.maxZoom.toDouble(),
        includeIdeographs: false,
      );
      final region = await ml.downloadOfflineRegion(
        def,
        metadata: {'strasseId': info.id, 'name': info.name},
        onEvent: (dynamic status) {
          // Les types d'événements du plugin (InProgress / Success / Error) sont lus par nom pour rester
          // indépendants de leur export exact.
          final type = status.runtimeType.toString();
          if (type == 'InProgress') {
            final p = (status.progress as num).toDouble();
            current = current.copyWith(progress: p, updatedAt: DateTime.now());
            _replace(current);
          } else if (type == 'Success') {
            current = current.copyWith(status: OfflineStatus.complete, progress: 100, updatedAt: DateTime.now());
            if (!done.isCompleted) done.complete();
          } else if (type == 'Error') {
            current = current.copyWith(status: OfflineStatus.failed, error: 'Le téléchargement a échoué (réseau ou serveur de cartes).');
            if (!done.isCompleted) done.complete();
          }
        },
      );
      current = current.copyWith(nativeId: region.id);
      _replace(current);
      await repo.save(current);
      await done.future;
    } catch (e) {
      current = current.copyWith(status: OfflineStatus.failed, error: toFailure(e).message);
    } finally {
      _running.remove(info.id);
    }
    await repo.save(current);
    _replace(current);
    if (notifyEnabled()) {
      if (current.isComplete) {
        await notifications.notifyDownloadComplete(current.name);
      } else {
        await notifications.notifyDownloadFailed(current.name);
      }
    }
  }

  bool isRunning(String id) => _running.containsKey(id);

  /// Annule un téléchargement en cours (la région partielle est supprimée du stockage natif).
  Future<void> cancel(String id) => delete(id);

  /// Supprime une région (stockage natif + métadonnées).
  Future<void> delete(String id) async {
    final r = await repo.byId(id);
    if (r?.nativeId != null) {
      try {
        await ml.deleteOfflineRegion(r!.nativeId!);
      } catch (_) {}
    }
    await repo.delete(id);
    state = state.where((x) => x.id != id).toList();
  }

  /// Met à jour une région : retéléchargement complet avec les mêmes paramètres.
  Future<OfflineRegionInfo> update(String id) async {
    final r = await repo.byId(id);
    if (r == null) throw const Failure(FailureKind.client, 'Région introuvable.');
    final name = r.name;
    final bounds = r.bounds;
    final minZ = r.minZoom;
    final maxZ = r.maxZoom;
    await delete(id);
    return download(name: name, bounds: bounds, minZoom: minZ, maxZoom: maxZ);
  }

  void _replace(OfflineRegionInfo r) {
    state = [for (final x in state) x.id == r.id ? r : x];
  }

  /// Écrit le style dans un fichier du dossier de support (utilisé pour les téléchargements natifs).
  static Future<String> writeStyle(String json) async {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/strasse_offline_style.json');
    await f.writeAsString(json, flush: true);
    return Uri.file(f.path).toString();
  }
}
