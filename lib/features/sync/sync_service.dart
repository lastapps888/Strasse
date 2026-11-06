import 'package:strasse/core/core.dart';
import 'package:strasse/core/storage/preferences_store.dart';
import 'package:strasse/data/providers/strasse_api.dart';
import 'package:strasse/data/repositories/favorites_repository.dart';
import 'package:strasse/data/repositories/trips_repository.dart';
import 'package:strasse/features/settings/settings_model.dart';

class SyncReport {
  const SyncReport({required this.pulled, required this.at});
  final int pulled;
  final DateTime at;
}

/// Synchronisation facultative des favoris, collections, voyages et préférences.
/// Résolution des conflits : le plus récent gagne (`updatedAt`). L'historique GPS n'est JAMAIS synchronisé.
class SyncService {
  SyncService({
    required this.api,
    required this.favorites,
    required this.trips,
    required this.prefs,
    required this.readSettings,
    required this.applySettings,
  });

  final StrasseApi api;
  final FavoritesRepository favorites;
  final TripsRepository trips;
  final PreferencesStore prefs;
  final AppSettings Function() readSettings;
  final Future<void> Function(Map<String, dynamic> remote) applySettings;

  bool _running = false;

  DateTime? get lastSync => prefs.lastPull;

  /// Récupère les changements du serveur, les fusionne localement, puis envoie les modifications locales plus récentes.
  Future<SyncReport> syncNow() async {
    if (_running) return SyncReport(pulled: 0, at: DateTime.now());
    _running = true;
    try {
      final since = prefs.lastPull;
      final remote = await api.pull(since: since);

      var pulled = 0;
      pulled += await favorites.applyRemoteFavorites(remote.favorites);
      pulled += await favorites.applyRemoteCollections(remote.collections);
      pulled += await trips.applyRemotePlanned(remote.trips);

      final localPrefsAt = prefs.settingsUpdatedAt;
      if (remote.preferences != null &&
          remote.preferencesUpdatedAt != null &&
          (localPrefsAt == null || remote.preferencesUpdatedAt!.isAfter(localPrefsAt))) {
        await applySettings(remote.preferences!);
        await prefs.touchSettings(remote.preferencesUpdatedAt);
        pulled++;
      }

      final lastPush = prefs.lastPush;
      bool newer(DateTime t) => lastPush == null || t.isAfter(lastPush);
      final favs = (await favorites.allIncludingDeleted()).where((f) => newer(f.updatedAt)).toList();
      final cols = (await favorites.allCollectionsIncludingDeleted()).where((c) => newer(c.updatedAt)).toList();
      final tps = (await trips.allPlannedIncludingDeleted()).where((t) => newer(t.updatedAt)).toList();
      final prefsChanged = localPrefsAt != null && newer(localPrefsAt);

      final serverTime = await api.push(
        favorites: favs,
        collections: cols,
        trips: tps,
        preferences: prefsChanged ? readSettings().toSyncJson() : null,
        preferencesUpdatedAt: localPrefsAt,
      );
      await prefs.setLastPush(serverTime);
      await prefs.setLastPull(remote.serverTime);
      return SyncReport(pulled: pulled, at: DateTime.now());
    } finally {
      _running = false;
    }
  }
}
