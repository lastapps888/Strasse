import 'package:flutter/material.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/services/provider_models.dart';

enum MapStyleChoice {
  auto('Automatique'),
  light('Clair'),
  dark('Sombre'),
  contrast('Contrasté'),
  custom('Personnalisé');

  const MapStyleChoice(this.label);
  final String label;
}


/// Représentation du véhicule sur la carte (dessinée par le code, voir vehicle_icons.dart).
enum VehicleIcon {
  car('Voiture'),
  compact('Voiture compacte'),
  electric('Voiture électrique'),
  sport('Coupé'),
  suv('SUV'),
  motorcycle('Moto'),
  bicycle('Vélo'),
  van('Camionnette'),
  truck('Camion'),
  arrow('Flèche');

  const VehicleIcon(this.label);
  final String label;
}

enum NightMode {
  auto('Automatique'),
  on('Toujours sombre'),
  off('Toujours clair');

  const NightMode(this.label);
  final String label;
}

/// Sections de l'écran d'accueil, réordonnables et masquables.
enum HomeSection {
  shortcuts('Raccourcis'),
  resume('Reprise de navigation'),
  recents('Destinations récentes'),
  frequent('Destinations fréquentes'),
  favorites('Favoris'),
  nearby('Autour de moi'),
  map('Accès à la carte');

  const HomeSection(this.label);
  final String label;
}

const List<int> kPalette = [
  0xFF5B8F57, 0xFF2F8CFF, 0xFF3E9B4F, 0xFF1F7FD1, 0xFF00897B, 0xFF5E35B1, 0xFFD81B60, 0xFFE64A19,
  0xFFF9A825, 0xFF455A64, 0xFF6D4C41, 0xFF00ACC1,
];

/// Réglages de l'utilisateur, persistés localement (JSON dans les préférences).
class AppSettings {
  const AppSettings({
    // Apparence
    this.themeMode = ThemeMode.system,
    this.primaryColor = 0xFF5B8F57,
    this.secondaryColor = 0xFF3E8FD6,
    this.routeColor = 0xFF2F8CFF,
    this.uiScale = 1.0,
    this.reduceAnimations = false,
    this.compactUi = false,
    this.useDynamicColor = true,
    this.providerSelections = const {},
    this.customProviders = const [],
    this.autoFallback = true,
    this.vehicleType = VehicleType.car,
    this.vehicleIcon = VehicleIcon.car,
    this.truckHeightM = 4.0,
    this.truckWidthM = 2.55,
    this.truckLengthM = 12.0,
    this.truckWeightT = 19.0,
    this.fuelConsumption = 0,
    this.fuelPrice = 0,
    this.speedAlertEnabled = true,
    this.speedAlertSound = false,
    this.speedAlertMarginKmh = 3,
    this.appIcon = 'clair',
    this.musicSource = '',
    this.showNavLabels = true,
    // Carte
    this.mapStyle = MapStyleChoice.auto,
    this.customRoadColor = 0xFFFFFFFF,
    this.customBuildingColor = 0xFFD9D4CC,
    this.customWaterColor = 0xFF8EC3E8,
    this.customGreenColor = 0xFFBFDDB0,
    this.showBuildings = true,
    this.showPoi = true,
    this.language = '',
    this.showHotels = false,
    this.showRestaurants = false,
    this.showTourismSites = false,
    this.showTransit = false,
    this.showCycleways = true,
    this.mapDensity = 1,
    this.showTrafficEvents = true,
    this.markerColor = 0xFFD32F2F,
    // Navigation
    this.defaultMode = TravelMode.car,
    this.routePrefs = const RoutePrefs(),
    this.voiceEnabled = true,
    this.voiceName,
    this.voiceVolume = 1.0,
    this.voiceRate = 0.5,
    this.units = Units.metric,
    this.showSpeed = true,
    this.nightMode = NightMode.auto,
    this.simpleDrivingMode = false,
    this.keepScreenOn = true,
    this.announceReports = true,
    // Confidentialité & modules facultatifs
    this.historyEnabled = true,
    this.statsEnabled = true,
    this.assistantEnabled = true,
    this.autoSync = true,
    // Notifications (facultatives, demandées seulement à l'activation)
    this.notifyDownloads = false,
    this.notifySync = false,
    this.notifyTrips = false,
    // Services (vide = valeur de compilation)
    // Accueil
    this.homeSections = const [
      HomeSection.shortcuts,
      HomeSection.resume,
      HomeSection.recents,
      HomeSection.frequent,
      HomeSection.favorites,
      HomeSection.nearby,
      HomeSection.map,
    ],
    this.onboardingDone = false,
  });

  final ThemeMode themeMode;
  final int primaryColor;
  final int secondaryColor;
  final int routeColor;
  final double uiScale;
  final bool reduceAnimations;
  final bool compactUi;

  /// Material You : reprend les couleurs du fond d'écran (Android 12+). Ailleurs, la couleur principale de Strasse est utilisée.
  final bool useDynamicColor;

  /// Fournisseur choisi par catégorie (identifiant de catégorie → identifiant de fournisseur). Absent : recommandé.
  final Map<String, String> providerSelections;

  /// Fournisseurs ajoutés par l'utilisateur (adresse HTTPS personnalisée).
  final List<ServiceProvider> customProviders;

  /// Bascule automatique vers un fournisseur équivalent en cas de panne.
  final bool autoFallback;

  final VehicleType vehicleType;
  final VehicleIcon vehicleIcon;
  final double truckHeightM;
  final double truckWidthM;
  final double truckLengthM;
  final double truckWeightT;

  /// Consommation aux 100 km (L ou kWh) et prix du litre / du kWh : 0 = non renseigné, aucun coût n'est alors estimé.
  final double fuelConsumption;
  final double fuelPrice;

  final bool speedAlertEnabled;
  final bool speedAlertSound;

  /// Dépassement (km/h) à partir duquel l'alerte se déclenche.
  final int speedAlertMarginKmh;

  /// Identifiant de l'icône d'application choisie (voir app_icons.dart).
  final String appIcon;

  /// Dernière source musicale utilisée.
  final String musicSource;
  final bool showNavLabels;

  final MapStyleChoice mapStyle;
  final int customRoadColor;
  final int customBuildingColor;
  final int customWaterColor;
  final int customGreenColor;
  final bool showBuildings;
  final bool showPoi;

  /// Code de langue (fr, en, de…) ; vide = suivre la langue de l'appareil.
  final String language;
  final bool showHotels;
  final bool showRestaurants;
  final bool showTourismSites;
  final bool showTransit;
  final bool showCycleways;

  /// 0 = épuré, 1 = normal, 2 = détaillé.
  final int mapDensity;
  final bool showTrafficEvents;
  final int markerColor;

  final TravelMode defaultMode;

  /// Préférences d'itinéraire par défaut, complétées par le véhicule choisi dans Réglages > Véhicule.
  RoutePrefs get effectiveRoutePrefs => routePrefs.copyWith(
        vehicle: vehicleType,
        truckHeightM: truckHeightM,
        truckWidthM: truckWidthM,
        truckLengthM: truckLengthM,
        truckWeightT: truckWeightT,
      );
  final RoutePrefs routePrefs;
  final bool voiceEnabled;
  final String? voiceName;
  final double voiceVolume;
  final double voiceRate;
  final Units units;
  final bool showSpeed;
  final NightMode nightMode;
  final bool simpleDrivingMode;
  final bool keepScreenOn;
  final bool announceReports;

  final bool historyEnabled;
  final bool statsEnabled;
  final bool assistantEnabled;
  final bool autoSync;

  final bool notifyDownloads;
  final bool notifySync;
  final bool notifyTrips;


  final List<HomeSection> homeSections;
  final bool onboardingDone;

  Color get primary => Color(primaryColor);
  Color get secondary => Color(secondaryColor);

  // Les adresses des services sont résolues par ProviderResolver (features/services) : choix de l'utilisateur,
  // sinon valeur de compilation, sinon fournisseur recommandé.

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? primaryColor,
    int? secondaryColor,
    int? routeColor,
    double? uiScale,
    bool? reduceAnimations,
    bool? compactUi,
    bool? useDynamicColor,
    Map<String, String>? providerSelections,
    List<ServiceProvider>? customProviders,
    bool? autoFallback,
    VehicleType? vehicleType,
    VehicleIcon? vehicleIcon,
    double? truckHeightM,
    double? truckWidthM,
    double? truckLengthM,
    double? truckWeightT,
    double? fuelConsumption,
    double? fuelPrice,
    bool? speedAlertEnabled,
    bool? speedAlertSound,
    int? speedAlertMarginKmh,
    String? appIcon,
    String? musicSource,
    bool? showNavLabels,
    MapStyleChoice? mapStyle,
    int? customRoadColor,
    int? customBuildingColor,
    int? customWaterColor,
    int? customGreenColor,
    bool? showBuildings,
    bool? showPoi,
    String? language,
    bool? showHotels,
    bool? showRestaurants,
    bool? showTourismSites,
    bool? showTransit,
    bool? showCycleways,
    int? mapDensity,
    bool? showTrafficEvents,
    int? markerColor,
    TravelMode? defaultMode,
    RoutePrefs? routePrefs,
    bool? voiceEnabled,
    String? voiceName,
    bool clearVoiceName = false,
    double? voiceVolume,
    double? voiceRate,
    Units? units,
    bool? showSpeed,
    NightMode? nightMode,
    bool? simpleDrivingMode,
    bool? keepScreenOn,
    bool? announceReports,
    bool? historyEnabled,
    bool? statsEnabled,
    bool? assistantEnabled,
    bool? autoSync,
    bool? notifyDownloads,
    bool? notifySync,
    bool? notifyTrips,
    List<HomeSection>? homeSections,
    bool? onboardingDone,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        primaryColor: primaryColor ?? this.primaryColor,
        secondaryColor: secondaryColor ?? this.secondaryColor,
        routeColor: routeColor ?? this.routeColor,
        uiScale: uiScale ?? this.uiScale,
        reduceAnimations: reduceAnimations ?? this.reduceAnimations,
        compactUi: compactUi ?? this.compactUi,
        useDynamicColor: useDynamicColor ?? this.useDynamicColor,
        providerSelections: providerSelections ?? this.providerSelections,
        customProviders: customProviders ?? this.customProviders,
        autoFallback: autoFallback ?? this.autoFallback,
        vehicleType: vehicleType ?? this.vehicleType,
        vehicleIcon: vehicleIcon ?? this.vehicleIcon,
        truckHeightM: truckHeightM ?? this.truckHeightM,
        truckWidthM: truckWidthM ?? this.truckWidthM,
        truckLengthM: truckLengthM ?? this.truckLengthM,
        truckWeightT: truckWeightT ?? this.truckWeightT,
        fuelConsumption: fuelConsumption ?? this.fuelConsumption,
        fuelPrice: fuelPrice ?? this.fuelPrice,
        speedAlertEnabled: speedAlertEnabled ?? this.speedAlertEnabled,
        speedAlertSound: speedAlertSound ?? this.speedAlertSound,
        speedAlertMarginKmh: speedAlertMarginKmh ?? this.speedAlertMarginKmh,
        appIcon: appIcon ?? this.appIcon,
        musicSource: musicSource ?? this.musicSource,
        showNavLabels: showNavLabels ?? this.showNavLabels,
        mapStyle: mapStyle ?? this.mapStyle,
        customRoadColor: customRoadColor ?? this.customRoadColor,
        customBuildingColor: customBuildingColor ?? this.customBuildingColor,
        customWaterColor: customWaterColor ?? this.customWaterColor,
        customGreenColor: customGreenColor ?? this.customGreenColor,
        showBuildings: showBuildings ?? this.showBuildings,
        showPoi: showPoi ?? this.showPoi,
        language: language ?? this.language,
        showHotels: showHotels ?? this.showHotels,
        showRestaurants: showRestaurants ?? this.showRestaurants,
        showTourismSites: showTourismSites ?? this.showTourismSites,
        showTransit: showTransit ?? this.showTransit,
        showCycleways: showCycleways ?? this.showCycleways,
        mapDensity: mapDensity ?? this.mapDensity,
        showTrafficEvents: showTrafficEvents ?? this.showTrafficEvents,
        markerColor: markerColor ?? this.markerColor,
        defaultMode: defaultMode ?? this.defaultMode,
        routePrefs: routePrefs ?? this.routePrefs,
        voiceEnabled: voiceEnabled ?? this.voiceEnabled,
        voiceName: clearVoiceName ? null : (voiceName ?? this.voiceName),
        voiceVolume: voiceVolume ?? this.voiceVolume,
        voiceRate: voiceRate ?? this.voiceRate,
        units: units ?? this.units,
        showSpeed: showSpeed ?? this.showSpeed,
        nightMode: nightMode ?? this.nightMode,
        simpleDrivingMode: simpleDrivingMode ?? this.simpleDrivingMode,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        announceReports: announceReports ?? this.announceReports,
        historyEnabled: historyEnabled ?? this.historyEnabled,
        statsEnabled: statsEnabled ?? this.statsEnabled,
        assistantEnabled: assistantEnabled ?? this.assistantEnabled,
        autoSync: autoSync ?? this.autoSync,
        notifyDownloads: notifyDownloads ?? this.notifyDownloads,
        notifySync: notifySync ?? this.notifySync,
        notifyTrips: notifyTrips ?? this.notifyTrips,
        homeSections: homeSections ?? this.homeSections,
        onboardingDone: onboardingDone ?? this.onboardingDone,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'primaryColor': primaryColor,
        'secondaryColor': secondaryColor,
        'routeColor': routeColor,
        'uiScale': uiScale,
        'reduceAnimations': reduceAnimations,
        'compactUi': compactUi,
        'useDynamicColor': useDynamicColor,
        'providerSelections': providerSelections,
        'customProviders': customProviders.map((p) => p.toJson()).toList(),
        'autoFallback': autoFallback,
        'vehicleType': vehicleType.name,
        'vehicleIcon': vehicleIcon.name,
        'truckHeightM': truckHeightM,
        'truckWidthM': truckWidthM,
        'truckLengthM': truckLengthM,
        'truckWeightT': truckWeightT,
        'fuelConsumption': fuelConsumption,
        'fuelPrice': fuelPrice,
        'speedAlertEnabled': speedAlertEnabled,
        'speedAlertSound': speedAlertSound,
        'speedAlertMarginKmh': speedAlertMarginKmh,
        'appIcon': appIcon,
        'musicSource': musicSource,
        'showNavLabels': showNavLabels,
        'mapStyle': mapStyle.name,
        'customRoadColor': customRoadColor,
        'customBuildingColor': customBuildingColor,
        'customWaterColor': customWaterColor,
        'customGreenColor': customGreenColor,
        'showBuildings': showBuildings,
        'showPoi': showPoi,
        'language': language,
        'showHotels': showHotels,
        'showRestaurants': showRestaurants,
        'showTourismSites': showTourismSites,
        'showTransit': showTransit,
        'showCycleways': showCycleways,
        'mapDensity': mapDensity,
        'showTrafficEvents': showTrafficEvents,
        'markerColor': markerColor,
        'defaultMode': defaultMode.name,
        'routePrefs': routePrefs.toJson(),
        'voiceEnabled': voiceEnabled,
        'voiceName': voiceName,
        'voiceVolume': voiceVolume,
        'voiceRate': voiceRate,
        'units': units.name,
        'showSpeed': showSpeed,
        'nightMode': nightMode.name,
        'simpleDrivingMode': simpleDrivingMode,
        'keepScreenOn': keepScreenOn,
        'announceReports': announceReports,
        'historyEnabled': historyEnabled,
        'statsEnabled': statsEnabled,
        'assistantEnabled': assistantEnabled,
        'autoSync': autoSync,
        'notifyDownloads': notifyDownloads,
        'notifySync': notifySync,
        'notifyTrips': notifyTrips,
        'homeSections': homeSections.map((s) => s.name).toList(),
        'onboardingDone': onboardingDone,
      };

  /// Préférences synchronisables : jamais les adresses de serveurs ni l'état d'installation.
  Map<String, dynamic> toSyncJson() {
    final j = toJson();
    for (final k in ['providerSelections', 'customProviders', 'onboardingDone', 'voiceName', 'appIcon']) {
      j.remove(k);
    }
    return j;
  }

  /// Applique des préférences reçues du serveur sur les réglages locaux.
  AppSettings mergedWithSync(Map<String, dynamic> remote) {
    final local = toJson();
    final merged = {...local, ...remote};
    for (final k in ['providerSelections', 'customProviders', 'onboardingDone', 'voiceName', 'appIcon']) {
      merged[k] = local[k];
    }
    return AppSettings.fromJson(merged);
  }

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    T enumOf<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);
    int i(String k, int fb) => (j[k] as num?)?.toInt() ?? fb;
    double dbl(String k, double fb) => (j[k] as num?)?.toDouble() ?? fb;
    bool b(String k, bool fb) => j[k] is bool ? j[k] as bool : fb;
    String s(String k) => (j[k] as String?) ?? '';
    // Réglages d'une version précédente : les adresses saisies à la main deviennent des fournisseurs personnalisés.
    final selections = <String, String>{
      if (j['providerSelections'] is Map)
        for (final e in (j['providerSelections'] as Map).entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
    };
    final customs = <ServiceProvider>[
      if (j['customProviders'] is List)
        for (final e in j['customProviders'] as List)
          if (ServiceProvider.fromJson(e) != null) ServiceProvider.fromJson(e)!,
    ];
    const legacy = <(String, ServiceCategory, String)>[
      ('apiUrl', ServiceCategory.account, 'strasse-api'),
      ('apiUrl', ServiceCategory.reports, 'strasse-api'),
      ('tilesUrl', ServiceCategory.tiles, 'tilejson'),
      ('glyphsUrl', ServiceCategory.glyphs, 'glyphs'),
      ('valhallaUrl', ServiceCategory.routing, 'valhalla'),
      ('geocoderUrl', ServiceCategory.geocoding, 'nominatim'),
      ('otpUrl', ServiceCategory.transit, 'otp'),
      ('overpassUrl', ServiceCategory.roadData, 'overpass'),
    ];
    for (final l in legacy) {
      final url = s(l.$1).trim();
      if (url.isEmpty || selections.containsKey(l.$2.id)) continue;
      final id = 'legacy-${l.$2.id}';
      customs.add(ServiceProvider(id: id, category: l.$2, name: 'Adresse personnalisée', description: 'Adresse saisie dans une version précédente.', baseUrl: url, adapter: l.$3, custom: true));
      selections[l.$2.id] = id;
    }
    final sections = <HomeSection>[];
    if (j['homeSections'] is List) {
      for (final n in j['homeSections'] as List) {
        final s = HomeSection.values.where((v) => v.name == n);
        if (s.isNotEmpty) sections.add(s.first);
      }
    }
    return AppSettings(
      themeMode: enumOf(ThemeMode.values, j['themeMode'], d.themeMode),
      primaryColor: i('primaryColor', d.primaryColor),
      secondaryColor: i('secondaryColor', d.secondaryColor),
      routeColor: i('routeColor', d.routeColor),
      uiScale: dbl('uiScale', d.uiScale).clamp(0.85, 1.4),
      reduceAnimations: b('reduceAnimations', d.reduceAnimations),
      compactUi: b('compactUi', d.compactUi),
      useDynamicColor: b('useDynamicColor', d.useDynamicColor),
      providerSelections: selections,
      customProviders: customs,
      autoFallback: b('autoFallback', d.autoFallback),
      vehicleType: enumOf(VehicleType.values, j['vehicleType'], d.vehicleType),
      vehicleIcon: enumOf(VehicleIcon.values, j['vehicleIcon'], d.vehicleIcon),
      truckHeightM: dbl('truckHeightM', d.truckHeightM).clamp(1.5, 6.0),
      truckWidthM: dbl('truckWidthM', d.truckWidthM).clamp(1.5, 4.0),
      truckLengthM: dbl('truckLengthM', d.truckLengthM).clamp(3.0, 25.0),
      truckWeightT: dbl('truckWeightT', d.truckWeightT).clamp(1.0, 60.0),
      fuelConsumption: dbl('fuelConsumption', d.fuelConsumption).clamp(0.0, 80.0),
      fuelPrice: dbl('fuelPrice', d.fuelPrice).clamp(0.0, 10.0),
      speedAlertEnabled: b('speedAlertEnabled', d.speedAlertEnabled),
      speedAlertSound: b('speedAlertSound', d.speedAlertSound),
      speedAlertMarginKmh: i('speedAlertMarginKmh', d.speedAlertMarginKmh).clamp(1, 30),
      appIcon: (j['appIcon'] as String?) ?? d.appIcon,
      musicSource: (j['musicSource'] as String?) ?? d.musicSource,
      showNavLabels: b('showNavLabels', d.showNavLabels),
      mapStyle: enumOf(MapStyleChoice.values, j['mapStyle'], d.mapStyle),
      customRoadColor: i('customRoadColor', d.customRoadColor),
      customBuildingColor: i('customBuildingColor', d.customBuildingColor),
      customWaterColor: i('customWaterColor', d.customWaterColor),
      customGreenColor: i('customGreenColor', d.customGreenColor),
      showBuildings: b('showBuildings', d.showBuildings),
      showPoi: b('showPoi', d.showPoi),
      language: s('language'),
      showHotels: b('showHotels', d.showHotels),
      showRestaurants: b('showRestaurants', d.showRestaurants),
      showTourismSites: b('showTourismSites', d.showTourismSites),
      showTransit: b('showTransit', d.showTransit),
      showCycleways: b('showCycleways', d.showCycleways),
      mapDensity: i('mapDensity', d.mapDensity).clamp(0, 2),
      showTrafficEvents: b('showTrafficEvents', d.showTrafficEvents),
      markerColor: i('markerColor', d.markerColor),
      defaultMode: TravelMode.fromName(j['defaultMode'] as String?),
      routePrefs: RoutePrefs.fromJson(j['routePrefs'] is Map ? Map<String, dynamic>.from(j['routePrefs'] as Map) : null),
      voiceEnabled: b('voiceEnabled', d.voiceEnabled),
      voiceName: j['voiceName'] as String?,
      voiceVolume: dbl('voiceVolume', d.voiceVolume).clamp(0.0, 1.0),
      voiceRate: dbl('voiceRate', d.voiceRate).clamp(0.2, 0.9),
      units: enumOf(Units.values, j['units'], d.units),
      showSpeed: b('showSpeed', d.showSpeed),
      nightMode: enumOf(NightMode.values, j['nightMode'], d.nightMode),
      simpleDrivingMode: b('simpleDrivingMode', d.simpleDrivingMode),
      keepScreenOn: b('keepScreenOn', d.keepScreenOn),
      announceReports: b('announceReports', d.announceReports),
      historyEnabled: b('historyEnabled', d.historyEnabled),
      statsEnabled: b('statsEnabled', d.statsEnabled),
      assistantEnabled: b('assistantEnabled', d.assistantEnabled),
      autoSync: b('autoSync', d.autoSync),
      notifyDownloads: b('notifyDownloads', d.notifyDownloads),
      notifySync: b('notifySync', d.notifySync),
      notifyTrips: b('notifyTrips', d.notifyTrips),
      homeSections: sections.isEmpty ? d.homeSections : sections,
      onboardingDone: b('onboardingDone', d.onboardingDone),
    );
  }
}
