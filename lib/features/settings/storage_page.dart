import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/offline_routing/routing_graph_store.dart';

/// Gestion explicite du cache et des téléchargements hors connexion.
/// Les fichiers musicaux importés, comptes, favoris, trajets et préférences ne sont jamais touchés.
class StorageManagementPage extends ConsumerStatefulWidget {
  const StorageManagementPage({super.key});

  @override
  ConsumerState<StorageManagementPage> createState() => _StorageManagementPageState();
}

class _StorageManagementPageState extends ConsumerState<StorageManagementPage> {
  int? _cacheBytes;
  int? _downloadedMapBytes;
  int? _routingBytes;
  int? _freeBytes;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<int> _directoryBytes(Directory directory, {bool preserveUpdateDownloads = false}) async {
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (preserveUpdateDownloads &&
          entity is Directory &&
          entity.path.split(Platform.pathSeparator).last.toLowerCase() == 'updates') {
        continue;
      }
      try {
        if (entity is File) {
          total += await entity.length();
        } else if (entity is Directory) {
          total += await _directoryBytes(entity);
        }
      } on FileSystemException {
        // Un fichier temporaire peut disparaître pendant que le système l'utilise.
      }
    }
    return total;
  }

  Future<void> _refresh() async {
    try {
      final temporary = await getTemporaryDirectory();
      final cache = await _directoryBytes(temporary, preserveUpdateDownloads: true);
      final regions = ref.read(offlineManagerProvider);
      final routes = ref.read(routingGraphStoreProvider);
      final maps = regions.where((region) => region.isComplete).fold<int>(0, (sum, region) => sum + region.sizeBytes);
      final routing = routes.where((zone) => zone.status == RoutingZoneStatus.ready).fold<int>(0, (sum, zone) => sum + zone.sizeBytes);
      final free = await ref.read(offlineManagerProvider.notifier).freeBytes();
      if (!mounted) return;
      setState(() {
        _cacheBytes = cache;
        _downloadedMapBytes = maps;
        _routingBytes = routing;
        _freeBytes = free;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de mesurer tout le stockage : $e';
      });
    }
  }

  Future<bool> _confirm({required String title, required String message, required String action}) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(action)),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _clearCache() async {
    final confirmed = await _confirm(
      title: 'Vider le cache temporaire ?',
      message: 'Les fichiers temporaires seront supprimés. Les IPA téléchargés dans Fichiers, cartes hors connexion, musique importée, compte, favoris, trajets et réglages seront conservés.',
      action: 'Vider le cache',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var failures = 0;
    try {
      final directory = await getTemporaryDirectory();
      await for (final entity in directory.list(followLinks: false)) {
        // Conserver un APK Android prêt à être installé depuis Réglages > Mise à jour.
        if (entity is Directory && entity.path.split(Platform.pathSeparator).last.toLowerCase() == 'updates') {
          continue;
        }
        try {
          await entity.delete(recursive: true);
        } on FileSystemException {
          failures++;
        }
      }
      await _refresh();
      if (!mounted) return;
      final message = failures == 0
          ? 'Cache temporaire vidé.'
          : 'Cache partiellement vidé : ' + failures.toString() + ' élément(s) temporaire(s) n’ont pas pu être supprimés.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) setState(() => _error = 'Échec du nettoyage du cache : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearDownloadedData() async {
    final confirmed = await _confirm(
      title: 'Supprimer les données téléchargées ?',
      message: 'Toutes les cartes hors connexion et tous les graphes d’itinéraires téléchargés seront supprimés. Les téléchargements en cours seront conservés. Cela ne supprime ni musique importée, ni compte, ni favoris, ni trajets, ni préférences.',
      action: 'Supprimer les téléchargements',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final manager = ref.read(offlineManagerProvider.notifier);
      final routingStore = ref.read(routingGraphStoreProvider.notifier);
      final regions = List.of(ref.read(offlineManagerProvider));
      final routeZones = List.of(ref.read(routingGraphStoreProvider));
      final mapIds = regions.map((region) => region.id).toSet();
      final activeIds = <String>{
        for (final region in regions)
          if (region.status == OfflineStatus.downloading) region.id,
        for (final zone in routeZones)
          if (zone.status == RoutingZoneStatus.downloading) zone.id,
      };
      var removedMaps = 0;
      var removedRoutes = 0;
      final preservedActive = activeIds.length;

      for (final region in regions) {
        if (activeIds.contains(region.id)) continue;
        await routingStore.delete(region.id);
        await manager.delete(region.id);
        removedMaps++;
      }

      for (final zone in routeZones) {
        if (mapIds.contains(zone.id) || activeIds.contains(zone.id)) continue;
        await routingStore.delete(zone.id);
        removedRoutes++;
      }

      await _refresh();
      if (!mounted) return;
      final preserved = preservedActive == 0
          ? ''
          : ' ' + preservedActive.toString() + ' téléchargement(s) en cours ont été conservés.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(removedMaps.toString() + ' zone(s) de carte et ' + removedRoutes.toString() + ' graphe(s) d’itinéraire supprimés.' + preserved)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Suppression incomplète des téléchargements : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maps = _downloadedMapBytes;
    final routing = _routingBytes;
    final downloaded = maps == null || routing == null ? null : maps + routing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stockage'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InfoBanner(icon: Icons.warning_amber_rounded, tone: BannerTone.warning, message: _error!),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Utilisation estimée', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _StorageRow(label: 'Cache temporaire', value: _cacheBytes == null ? '—' : formatBytes(_cacheBytes!)),
                  _StorageRow(label: 'Cartes hors connexion', value: maps == null ? '—' : formatBytes(maps), note: 'Estimation des zones téléchargées'),
                  _StorageRow(label: 'Itinéraires hors connexion', value: routing == null ? '—' : formatBytes(routing), note: 'Taille des graphes stockés'),
                  const Divider(height: 24),
                  _StorageRow(label: 'Total des téléchargements', value: downloaded == null ? '—' : formatBytes(downloaded)),
                  _StorageRow(label: 'Espace libre sur l’appareil', value: _freeBytes == null ? 'Inconnu' : formatBytes(_freeBytes!)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.cleaning_services_outlined, size: 26),
                  const SizedBox(height: 8),
                  Text('Cache temporaire', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text('Supprime les fichiers temporaires de l’application. Les téléchargements d’IPA dans Fichiers et un APK en attente d’installation sont préservés.'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy || _loading ? null : _clearCache,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Vider le cache'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.map_outlined, size: 26),
                  const SizedBox(height: 8),
                  Text('Données téléchargées', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text('Supprime les cartes et graphes d’itinéraires hors connexion. Les téléchargements en cours et toutes les données personnelles sont conservés.'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: _busy || _loading || (downloaded ?? 0) == 0 ? null : _clearDownloadedData,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Supprimer les données téléchargées'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'La musique importée, les favoris, collections, trajets planifiés, comptes et préférences ne sont jamais supprimés depuis cet écran.',
            style: TextStyle(fontSize: 12),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _StorageRow extends StatelessWidget {
  const _StorageRow({required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                if (note != null) Text(note!, style: TextStyle(fontSize: 11, color: secondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
