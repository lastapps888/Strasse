import 'package:flutter/material.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';

enum MapStyleChoice {
  auto('Automatique'),
  light('Clair'),
  dark('Sombre'),
  contrast('Contrasté'),
  custom('Personnalisé');

  const MapStyleChoice(this.label);
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
    this.showNavLabels = true,
    // Carte
    this.mapStyle = MapStyleChoice.auto,
    this.customRoadColor = 0xFFFFFFFF,
    this.customBuildingColor = 0xFFD9D4CC,
    this.customWaterColor = 0xFF8EC3E8,
    this.customGreenColor = 0xFFBFDDB0,
    this.showBuildings = true,
    this.showPoi = true,
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
    this.apiUrl = '',
    this.tilesUrl = '',
    this.glyphsUrl = '',
    this.valhallaUrl = '',
    this.geocoderUrl = '',
    this.otpUrl = '',
    this.overpassUrl = '',
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
  final bool showNavLabels;

  final MapStyleChoice mapStyle;
  final int customRoadColor;
  final int customBuildingColor;
  final int customWaterColor;
  final int customGreenColor;
  final bool showBuildings;
  final bool showPoi;
  final bool showTransit;
  final bool showCycleways;

  /// 0 = épuré, 1 = normal, 2 = détaillé.
  final int mapDensity;
  final bool showTrafficEvents;
  final int markerColor;

  final TravelMode defaultMode;
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

  final String apiUrl;
  final String tilesUrl;
  final String glyphsUrl;
  final String valhallaUrl;
  final String geocoderUrl;
  final String otpUrl;
  final String overpassUrl;

  final List<HomeSection> homeSections;
  final bool onboardingDone;

  Color get primary => Color(primaryColor);
  Color get secondary => Color(secondaryColor);

  // Adresses effectives : réglage de l'utilisateur, sinon valeur de compilation.
  String effectiveApiUrl(AppConfig c) => _pick(apiUrl, c.apiUrl);
  String effectiveTilesUrl(AppConfig c) => _pick(tilesUrl, c.tilesUrl);
  String effectiveGlyphsUrl(AppConfig c) => _pick(glyphsUrl, c.glyphsUrl);
  String effectiveValhallaUrl(AppConfig c) => _pick(valhallaUrl, c.valhallaUrl);
  String effectiveGeocoderUrl(AppConfig c) => _pick(geocoderUrl, c.geocoderUrl);
  String effectiveOtpUrl(AppConfig c) => _pick(otpUrl, c.otpUrl);
  String effectiveOverpassUrl(AppConfig c) => _pick(overpassUrl, c.overpassUrl);

  static String _pick(String user, String fallback) {
    final u = user.trim();
    final v = u.isNotEmpty ? u : fallback.trim();
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? primaryColor,
    int? secondaryColor,
    int? routeColor,
    double? uiScale,
    bool? reduceAnimations,
    bool? compactUi,
    bool? useDynamicColor,
    bool? showNavLabels,
    MapStyleChoice? mapStyle,
    int? customRoadColor,
    int? customBuildingColor,
    int? customWaterColor,
    int? customGreenColor,
    bool? showBuildings,
    bool? showPoi,
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
    String? apiUrl,
    String? tilesUrl,
    String? glyphsUrl,
    String? valhallaUrl,
    String? geocoderUrl,
    String? otpUrl,
    String? overpassUrl,
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
        showNavLabels: showNavLabels ?? this.showNavLabels,
        mapStyle: mapStyle ?? this.mapStyle,
        customRoadColor: customRoadColor ?? this.customRoadColor,
        customBuildingColor: customBuildingColor ?? this.customBuildingColor,
        customWaterColor: customWaterColor ?? this.customWaterColor,
        customGreenColor: customGreenColor ?? this.customGreenColor,
        showBuildings: showBuildings ?? this.showBuildings,
        showPoi: showPoi ?? this.showPoi,
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
        apiUrl: apiUrl ?? this.apiUrl,
        tilesUrl: tilesUrl ?? this.tilesUrl,
        glyphsUrl: glyphsUrl ?? this.glyphsUrl,
        valhallaUrl: valhallaUrl ?? this.valhallaUrl,
        geocoderUrl: geocoderUrl ?? this.geocoderUrl,
        otpUrl: otpUrl ?? this.otpUrl,
        overpassUrl: overpassUrl ?? this.overpassUrl,
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
        'showNavLabels': showNavLabels,
        'mapStyle': mapStyle.name,
        'customRoadColor': customRoadColor,
        'customBuildingColor': customBuildingColor,
        'customWaterColor': customWaterColor,
        'customGreenColor': customGreenColor,
        'showBuildings': showBuildings,
        'showPoi': showPoi,
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
        'apiUrl': apiUrl,
        'tilesUrl': tilesUrl,
        'glyphsUrl': glyphsUrl,
        'valhallaUrl': valhallaUrl,
        'geocoderUrl': geocoderUrl,
        'otpUrl': otpUrl,
        'overpassUrl': overpassUrl,
        'homeSections': homeSections.map((s) => s.name).toList(),
        'onboardingDone': onboardingDone,
      };

  /// Préférences synchronisables : jamais les adresses de serveurs ni l'état d'installation.
  Map<String, dynamic> toSyncJson() {
    final j = toJson();
    for (final k in ['apiUrl', 'tilesUrl', 'glyphsUrl', 'valhallaUrl', 'geocoderUrl', 'otpUrl', 'overpassUrl', 'onboardingDone', 'voiceName']) {
      j.remove(k);
    }
    return j;
  }

  /// Applique des préférences reçues du serveur sur les réglages locaux.
  AppSettings mergedWithSync(Map<String, dynamic> remote) {
    final local = toJson();
    final merged = {...local, ...remote};
    for (final k in ['apiUrl', 'tilesUrl', 'glyphsUrl', 'valhallaUrl', 'geocoderUrl', 'otpUrl', 'overpassUrl', 'onboardingDone', 'voiceName']) {
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
      showNavLabels: b('showNavLabels', d.showNavLabels),
      mapStyle: enumOf(MapStyleChoice.values, j['mapStyle'], d.mapStyle),
      customRoadColor: i('customRoadColor', d.customRoadColor),
      customBuildingColor: i('customBuildingColor', d.customBuildingColor),
      customWaterColor: i('customWaterColor', d.customWaterColor),
      customGreenColor: i('customGreenColor', d.customGreenColor),
      showBuildings: b('showBuildings', d.showBuildings),
      showPoi: b('showPoi', d.showPoi),
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
      apiUrl: s('apiUrl'),
      tilesUrl: s('tilesUrl'),
      glyphsUrl: s('glyphsUrl'),
      valhallaUrl: s('valhallaUrl'),
      geocoderUrl: s('geocoderUrl'),
      otpUrl: s('otpUrl'),
      overpassUrl: s('overpassUrl'),
      homeSections: sections.isEmpty ? d.homeSections : sections,
      onboardingDone: b('onboardingDone', d.onboardingDone),
    );
  }
}
