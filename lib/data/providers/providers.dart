import 'package:dio/dio.dart' show CancelToken;
import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/core/storage/app_database.dart';
import 'package:strasse/core/storage/preferences_store.dart';
import 'package:strasse/core/storage/secure_store.dart';
import 'package:strasse/data/providers/motis_client.dart';
import 'package:strasse/data/providers/otp_client.dart';
import 'package:strasse/data/providers/transit_lines_client.dart';
import 'package:strasse/data/providers/account_backend.dart';
import 'package:strasse/data/providers/strasse_api.dart';
import 'package:strasse/data/providers/supabase_backend.dart';
import 'package:strasse/data/providers/valhalla_client.dart';
import 'package:strasse/data/repositories/favorites_repository.dart';
import 'package:strasse/data/repositories/offline_repository.dart';
import 'package:strasse/data/repositories/places_repository.dart';
import 'package:strasse/data/repositories/trips_repository.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/assistant/assistant_engine.dart';
import 'package:strasse/features/location/location_service.dart';
import 'package:strasse/features/map/map_style_builder.dart';
import 'package:strasse/features/notifications/notifications_service.dart';
import 'package:strasse/features/offline_maps/offline_manager.dart';
import 'package:strasse/features/offline_routing/local_router.dart';
import 'package:strasse/features/offline_routing/routing_graph_store.dart';
import 'package:strasse/features/routing/routing_service.dart';
import 'package:strasse/features/settings/settings_controller.dart';
import 'package:strasse/features/settings/settings_model.dart';
import 'package:strasse/features/sync/auth_controller.dart';
import 'package:strasse/features/sync/sync_service.dart';
import 'package:strasse/features/traffic/traffic_controller.dart';
import 'package:strasse/features/voice/voice_service.dart';
import 'package:strasse/features/services/provider_resolver.dart';
import 'package:strasse/features/services/provider_models.dart';
import 'package:strasse/features/services/credentials_store.dart';
import 'package:strasse/data/providers/poi_service.dart';
import 'package:strasse/data/providers/place_info_service.dart';
import 'package:strasse/data/providers/google_places_reviews_client.dart';
import 'package:strasse/data/providers/strasse_cloud_backend.dart';
import 'package:strasse/data/providers/search_ranking.dart';
import 'package:strasse/features/navigation/speed_cameras.dart';
import 'package:strasse/data/providers/geocoding_service.dart';

export 'package:strasse/features/location/location_service.dart' show locationControllerProvider;

// ------------------------------------------------------- Valeurs injectées au démarrage

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment);
final preferencesStoreProvider = Provider<PreferencesStore>((ref) => throw UnimplementedError('Initialisé dans main'));
final secureStoreProvider = Provider<SecureStore>((ref) => throw UnimplementedError('Initialisé dans main'));
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('Initialisé dans main'));
final initialSettingsProvider = Provider<AppSettings>((ref) => const AppSettings());

// ------------------------------------------------------------------------- Réglages

final settingsProvider = StateNotifierProvider<SettingsController, AppSettings>((ref) {
  return SettingsController(ref.watch(preferencesStoreProvider), ref.read(initialSettingsProvider));
});

// ----------------------------------------------------------------------------- Dépôts

final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) => FavoritesRepository(ref.watch(databaseProvider)));
final tripsRepositoryProvider = Provider<TripsRepository>((ref) => TripsRepository(ref.watch(databaseProvider)));
final placesRepositoryProvider = Provider<PlacesRepository>((ref) => PlacesRepository(ref.watch(databaseProvider)));
final offlineRepositoryProvider = Provider<OfflineRepository>((ref) => OfflineRepository(ref.watch(databaseProvider)));

// ------------------------------------------------------------------------- Réseau

/// Vrai si l'appareil a une connexion (Wi-Fi, mobile…). Ne garantit pas l'accès à un serveur donné.
final onlineProvider = StreamProvider<bool>((ref) async* {
  final c = Connectivity();
  bool online(List<ConnectivityResult> results) => results.any((result) => result != ConnectivityResult.none);
  try {
    yield online(await c.checkConnectivity());
  } catch (_) {
    yield true;
  }
  yield* c.onConnectivityChanged.map(online);
});

/// Identifiants des fournisseurs (coffre sécurisé), chargés au démarrage.
final credentialsProvider = StateNotifierProvider<CredentialsNotifier, Map<String, String>>(
  (ref) => CredentialsNotifier(ref.watch(secureStoreProvider)),
);

/// Fournisseur actif de chaque catégorie de services, avec ses remplaçants.
final providerResolverProvider = Provider<ProviderResolver>((ref) {
  return ProviderResolver(ref.watch(settingsProvider), ref.watch(appConfigProvider), ref.watch(credentialsProvider));
});

final geocoderProvider = Provider<GeocodingService>((ref) {
  return GeocodingService.fromResolver(ref.watch(providerResolverProvider));
});

final placeInfoServiceProvider = Provider<PlaceInfoService>((ref) {
  final cfg = ref.watch(appConfigProvider);
  return PlaceInfoService(language: ref.watch(settingsProvider.select((s) => s.language)), userAgent: cfg.userAgent);
});

/// Photo + résumé Wikipédia/Commons d'un lieu nommé (clé : nom et coordonnées).
final placeInfoProvider = FutureProvider.autoDispose.family<PlaceInfo, (String, double, double)>((ref, k) {
  final token = CancelToken();
  ref.onDispose(token.cancel);
  return ref.watch(placeInfoServiceProvider).lookup(Place(id: 'info', name: k.$1, point: GeoPoint(k.$2, k.$3)), cancel: token);
});

/// Notes et avis Google Maps facultatifs ; aucune requête n'est faite sans clé API renseignée.
final placeReviewsProvider = FutureProvider.autoDispose.family<GooglePlaceReviews?, (String, double, double)>((ref, k) {
  final resolver = ref.watch(providerResolverProvider);
  final provider = resolver.selected(ServiceCategory.googlePlacesReviews);
  final apiKey = resolver.credential(provider, 'apiKey');
  if (apiKey.isEmpty) return null;
  final place = Place(id: 'google-review', name: k.$1, point: GeoPoint(k.$2, k.$3));
  return GooglePlacesReviewsClient(apiKey).forPlace(place);
});

final poiServiceProvider = Provider<PoiService>((ref) {
  return PoiService.fromResolver(ref.watch(providerResolverProvider));
});

final routingServiceProvider = Provider<RoutingService>((ref) {
  final r = ref.watch(providerResolverProvider);
  final transitSel = r.selected(ServiceCategory.transit);
  final transitUrl = ProviderResolver.normalize(r.urlOf(transitSel));
  final store = ref.watch(routingGraphStoreProvider.notifier);
  ref.watch(routingGraphStoreProvider); // recalcul quand une zone devient disponible ou est supprimée
  return RoutingService(
    valhalla: [
      for (final p in r.candidates(ServiceCategory.routing)) ValhallaClient(ProviderResolver.normalize(r.urlOf(p)), userAgent: r.config.userAgent),
    ],
    transit: transitUrl.isEmpty
        ? const UnavailableTransitRouter()
        : (transitSel.adapter == 'motis' ? MotisTransitRouter(transitUrl, userAgent: r.config.userAgent) : OtpTransitRouter(transitUrl)),
    local: LocalRouter(store.graphs),
  );
});

/// Arrêts, horaires et lignes pour la couche « Transports » de la carte.
/// Les horaires exigent un fournisseur MOTIS ; les lignes viennent toujours d'OpenStreetMap.
class TransitData {
  const TransitData({this.motis, required this.lines});
  final MotisTransitRouter? motis;
  final TransitLinesClient lines;
  bool get hasTimetables => motis != null;
}

final transitDataProvider = Provider<TransitData>((ref) {
  final r = ref.watch(providerResolverProvider);
  final sel = r.selected(ServiceCategory.transit);
  final url = ProviderResolver.normalize(r.urlOf(sel));
  final endpoints = [for (final p in r.candidates(ServiceCategory.roadData)) ProviderResolver.normalize(r.urlOf(p))];
  return TransitData(
    motis: sel.adapter == 'motis' && url.isNotEmpty ? MotisTransitRouter(url, userAgent: r.config.userAgent) : null,
    lines: TransitLinesClient(endpoints, userAgent: r.config.userAgent),
  );
});

final speedCameraClientProvider = Provider<SpeedCameraClient>((ref) {
  final r = ref.watch(providerResolverProvider);
  final endpoints = [for (final p in r.candidates(ServiceCategory.roadData)) ProviderResolver.normalize(r.urlOf(p))];
  return SpeedCameraClient(endpoints, userAgent: r.config.userAgent);
});

/// Réseaux routiers téléchargés pour le calcul d'itinéraires hors connexion.
final routingGraphStoreProvider = StateNotifierProvider<RoutingGraphStore, List<RoutingZone>>((ref) {
  return RoutingGraphStore(
    directory: () async => Directory('${(await getApplicationSupportDirectory()).path}/routing'),
    overpassUrl: () => ref.read(providerResolverProvider).url(ServiceCategory.roadData),
  );
});

/// Backend de compte et de synchronisation (facultatif) choisi dans Réglages > Services.
final strasseApiProvider = Provider<AccountBackend>((ref) {
  final r = ref.watch(providerResolverProvider);
  final secure = ref.watch(secureStoreProvider);
  return _buildBackend(r, r.selected(ServiceCategory.account), secure, onRecoveryKey: (k) => ref.read(recoveryKeyProvider.notifier).state = k);
});

/// Clé de récupération fraîchement créée, à montrer une seule fois (puis effacée de la mémoire).
final recoveryKeyProvider = StateProvider<String?>((ref) => null);

/// Backend des signalements. Il suit le compte lorsque les deux utilisent le même service ; sinon il lit le
/// service choisi pour les signalements (lecture publique, écriture réservée aux comptes).
final reportsBackendProvider = Provider<AccountBackend>((ref) {
  final r = ref.watch(providerResolverProvider);
  final secure = ref.watch(secureStoreProvider);
  final reports = r.selected(ServiceCategory.reports);
  final account = r.selected(ServiceCategory.account);
  if (reports.adapter == account.adapter) return ref.watch(strasseApiProvider);
  return _buildBackend(r, reports, secure, fallback: account);
});

AccountBackend _buildBackend(ProviderResolver r, ServiceProvider p, SecureStore secure, {ServiceProvider? fallback, void Function(String)? onRecoveryKey}) {
  if (p.adapter == 'strasse-cloud') {
    return StrasseCloudBackend(baseUrl: ProviderResolver.normalize(r.urlOf(p)), secure: secure, onRecoveryKey: onRecoveryKey);
  }
  if (p.adapter == 'supabase') {
    String field(String key) {
      final v = r.credential(p, key);
      if (v.isNotEmpty || fallback == null || fallback.adapter != 'supabase') return v;
      return r.credential(fallback, key);
    }

    return SupabaseBackend(url: field('url'), anonKey: field('anonKey'), secure: secure);
  }
  return StrasseApi(baseUrl: p.adapter == 'strasse-api' ? ProviderResolver.normalize(r.urlOf(p)) : '', secure: secure);
}

// ------------------------------------------------------------------------- Services

final notificationsProvider = Provider<NotificationsService>((ref) => NotificationsService());

final voiceProvider = Provider<VoiceService>((ref) => VoiceService());

final assistantProvider = Provider<AssistantEngine>((ref) => const LocalRuleAssistant());

final locationFixOnceProvider = Provider<GeoPoint?>((ref) => ref.read(locationControllerProvider).fix?.point);

// ------------------------------------------------------------------ Cartes hors connexion

final offlineManagerProvider = StateNotifierProvider<OfflineManager, List<OfflineRegionInfo>>((ref) {
  return OfflineManager(
    repo: ref.watch(offlineRepositoryProvider),
    notifications: ref.watch(notificationsProvider),
    notifyEnabled: () => ref.read(settingsProvider).notifyDownloads,
    writeStyleFile: () async {
      final s = ref.read(settingsProvider);
      final c = ref.read(appConfigProvider);
      final src = ref.read(providerResolverProvider).mapSource();
      if (!src.available) {
        throw const Failure(FailureKind.notConfigured, 'Aucun serveur de cartes n\'est configuré : téléchargement impossible. Renseignez-le dans Réglages > Services.');
      }
      // Style prêt à l'emploi d'un fournisseur : téléchargé tel quel.
      if (src.styleUrl != null) return src.styleUrl!;
      final json = MapStyleBuilder.build(
        palette: MapPalette.forSettings(s, Brightness.light),
        settings: s,
        tilesUrl: src.tilesUrl,
        glyphsUrl: src.glyphsUrl,
        font: c.mapFont,
        attribution: c.tilesAttribution,
      );
      return OfflineManager.writeStyle(json);
    },
  );
});

// ------------------------------------------------------------------ Compte et synchronisation

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    api: ref.watch(strasseApiProvider),
    favorites: ref.watch(favoritesRepositoryProvider),
    trips: ref.watch(tripsRepositoryProvider),
    prefs: ref.watch(preferencesStoreProvider),
    readSettings: () => ref.read(settingsProvider),
    applySettings: (remote) => ref.read(settingsProvider.notifier).applyRemote(remote),
  );
});

final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    api: ref.watch(strasseApiProvider),
    sync: ref.watch(syncServiceProvider),
    secure: ref.watch(secureStoreProvider),
    prefs: ref.watch(preferencesStoreProvider),
    notifications: ref.watch(notificationsProvider),
    settings: () => ref.read(settingsProvider),
  );
});

// ---------------------------------------------------------------------------- Trafic

final trafficProvider = StateNotifierProvider<TrafficController, TrafficState>((ref) {
  final controller = TrafficController(ref.read(reportsBackendProvider));
  ref.listen<AccountBackend>(reportsBackendProvider, (_, next) => controller.updateApi(next));
  return controller;
});

// ------------------------------------------------------ Données de l'utilisateur (listes)

final favoritesProvider = FutureProvider<List<Favorite>>((ref) => ref.watch(favoritesRepositoryProvider).all());
final collectionsProvider = FutureProvider<List<PlaceCollection>>((ref) => ref.watch(favoritesRepositoryProvider).collections());
final homeFavoriteProvider = FutureProvider<Favorite?>((ref) async {
  await ref.watch(favoritesProvider.future);
  return ref.watch(favoritesRepositoryProvider).byKind(FavoriteKind.home);
});
final workFavoriteProvider = FutureProvider<Favorite?>((ref) async {
  await ref.watch(favoritesProvider.future);
  return ref.watch(favoritesRepositoryProvider).byKind(FavoriteKind.work);
});
final recentPlacesProvider = FutureProvider<List<Place>>((ref) async {
  final list = await ref.watch(placesRepositoryProvider).recents(limit: 12);
  SearchRanking.personalPlaces = list;
  return list;
});
final searchQueriesProvider = FutureProvider<List<String>>((ref) => ref.watch(placesRepositoryProvider).queries());
final historyProvider = FutureProvider.family<List<TripRecord>, String>((ref, q) => ref.watch(tripsRepositoryProvider).history(query: q));
final frequentDestinationsProvider = FutureProvider<List<({TripRecord trip, int count})>>((ref) => ref.watch(tripsRepositoryProvider).frequentDestinations());
final plannedTripsProvider = FutureProvider<List<PlannedTrip>>((ref) => ref.watch(tripsRepositoryProvider).plannedTrips());
final tripStatsProvider = FutureProvider<TripStats>((ref) => ref.watch(tripsRepositoryProvider).stats());

/// Actions sur les données utilisateur : modifient la base, rafraîchissent les listes et planifient la synchronisation.
class DataActions {
  DataActions(this._ref);
  final Ref _ref;

  void _changed({bool favorites = false, bool trips = false, bool places = false}) {
    if (favorites) {
      _ref.invalidate(favoritesProvider);
      _ref.invalidate(collectionsProvider);
      _ref.invalidate(homeFavoriteProvider);
      _ref.invalidate(workFavoriteProvider);
    }
    if (trips) {
      _ref.invalidate(plannedTripsProvider);
    }
    if (places) {
      _ref.invalidate(recentPlacesProvider);
      _ref.invalidate(searchQueriesProvider);
    }
    if (favorites || trips) _ref.read(authProvider.notifier).schedule();
  }

  FavoritesRepository get _fav => _ref.read(favoritesRepositoryProvider);
  TripsRepository get _trips => _ref.read(tripsRepositoryProvider);
  PlacesRepository get _places => _ref.read(placesRepositoryProvider);

  Future<Favorite> addFavorite(Place p, {String? collectionId}) async {
    final f = await _fav.addPlace(p, collectionId: collectionId);
    _changed(favorites: true);
    return f;
  }

  Future<void> setSpecial(FavoriteKind kind, Place p) async {
    await _fav.setSpecial(kind, p);
    _changed(favorites: true);
  }

  Future<void> updateFavorite(Favorite f) async {
    await _fav.update(f);
    _changed(favorites: true);
  }

  Future<void> deleteFavorite(String id) async {
    await _fav.delete(id);
    _changed(favorites: true);
  }

  Future<void> restoreFavorite(String id) async {
    await _fav.restore(id);
    _changed(favorites: true);
  }

  Future<PlaceCollection> createCollection(String name, {String? description}) async {
    final c = await _fav.createCollection(name, description: description);
    _changed(favorites: true);
    return c;
  }

  Future<void> updateCollection(PlaceCollection c) async {
    await _fav.updateCollection(c);
    _changed(favorites: true);
  }

  Future<void> deleteCollection(String id) async {
    await _fav.deleteCollection(id);
    _changed(favorites: true);
  }

  Future<void> reorderCollections(List<PlaceCollection> ordered) async {
    await _fav.reorderCollections(ordered);
    _changed(favorites: true);
  }

  Future<PlannedTrip> savePlannedTrip(PlannedTrip t) async {
    final saved = await _trips.savePlannedTrip(t);
    _changed(trips: true);
    return saved;
  }

  Future<void> deletePlannedTrip(String id) async {
    await _trips.deletePlannedTrip(id);
    _changed(trips: true);
  }

  Future<void> rememberPlace(Place p) async {
    await _places.addRecent(p);
    _changed(places: true);
  }

  Future<void> rememberQuery(String q) async {
    await _places.addQuery(q);
    _changed(places: true);
  }

  Future<void> removeRecent(String id) async {
    await _places.removeRecent(id);
    _changed(places: true);
  }

  Future<void> removeQuery(String q) async {
    await _places.removeQuery(q);
    _changed(places: true);
  }

  Future<void> clearSearchData() async {
    await _places.clearRecents();
    await _places.clearQueries();
    _changed(places: true);
  }

  Future<void> deleteTrip(String id) async {
    await _trips.deleteTrip(id);
    _ref.invalidate(historyProvider);
    _ref.invalidate(tripStatsProvider);
    _ref.invalidate(frequentDestinationsProvider);
  }

  Future<void> clearHistory() async {
    await _trips.clearHistory();
    _ref.invalidate(historyProvider);
    _ref.invalidate(tripStatsProvider);
    _ref.invalidate(frequentDestinationsProvider);
  }

  /// Efface TOUTES les données locales de l'utilisateur (favoris, historique, voyages, recherches, régions).
  Future<void> wipeAllLocalData() async {
    final offline = _ref.read(offlineManagerProvider);
    for (final r in List.of(offline)) {
      await _ref.read(offlineManagerProvider.notifier).delete(r.id);
    }
    for (final z in List.of(_ref.read(routingGraphStoreProvider))) {
      await _ref.read(routingGraphStoreProvider.notifier).delete(z.id);
    }
    await _ref.read(databaseProvider).wipeAll();
    await _ref.read(preferencesStoreProvider).clearActiveNavigation();
    for (final p in <ProviderOrFamily>[
      favoritesProvider, collectionsProvider, homeFavoriteProvider, workFavoriteProvider, recentPlacesProvider,
      searchQueriesProvider, historyProvider, frequentDestinationsProvider, plannedTripsProvider, tripStatsProvider,
    ]) {
      _ref.invalidate(p);
    }
  }
}

final dataActionsProvider = Provider<DataActions>((ref) => DataActions(ref));

// ------------------------------------------------------------------------- Navigation de l'interface

/// Onglet sélectionné de la barre principale (0 Accueil, 1 Carte, 2 Trajets, 3 Favoris, 4 Réglages).
final shellIndexProvider = StateProvider<int>((ref) => 0);

/// Sous-onglet de « Enregistrés » : 0 = favoris, 1 = trajets.
final librarySubProvider = StateProvider<int>((ref) => 0);

/// Demande d'affichage sur la carte (depuis l'accueil, les favoris, une recherche…).
class MapFocus {
  const MapFocus({required this.place, this.zoom = 16});
  final Place place;
  final double zoom;
}

final mapFocusProvider = StateProvider<MapFocus?>((ref) => null);

/// Demande d'affichage d'un ensemble de résultats sur la carte (recherche par catégorie).
final mapResultsProvider = StateProvider<List<Place>>((ref) => const []);

/// Zone en cours de visualisation sur la carte, pour la recherche « dans cette zone ».
final mapViewportProvider = StateProvider<GeoBounds?>((ref) => null);
