import 'dart:convert';
import 'dart:ui';

import 'package:strasse/core/core.dart';
import 'package:strasse/features/settings/settings_model.dart';

/// Palette complète d'un style de carte Strasse.
class MapPalette {
  const MapPalette({
    required this.background,
    required this.water,
    required this.green,
    required this.wood,
    required this.building,
    required this.roadMinor,
    required this.roadMajor,
    required this.roadMotorway,
    required this.roadCasing,
    required this.path,
    required this.rail,
    required this.cycleway,
    required this.label,
    required this.labelHalo,
    required this.poi,
    required this.roadWidthFactor,
  });

  final Color background;
  final Color water;
  final Color green;
  final Color wood;
  final Color building;
  final Color roadMinor;
  final Color roadMajor;
  final Color roadMotorway;
  final Color roadCasing;
  final Color path;
  final Color rail;
  final Color cycleway;
  final Color label;
  final Color labelHalo;
  final Color poi;

  /// Épaisseur relative des routes (le style contrasté les épaissit).
  final double roadWidthFactor;

  bool get isDark => luminance(background) < 0.2;

  static const light = MapPalette(
    background: Color(0xFFF4F1EA),
    water: Color(0xFF9CCBEA),
    green: Color(0xFFCFE5BE),
    wood: Color(0xFFB9D9A6),
    building: Color(0xFFE3DDD2),
    roadMinor: Color(0xFFFFFFFF),
    roadMajor: Color(0xFFFFE9A8),
    roadMotorway: Color(0xFFF7B955),
    roadCasing: Color(0xFFCFC8BA),
    path: Color(0xFF9A8F7C),
    rail: Color(0xFF8A8F99),
    cycleway: Color(0xFF2E9B54),
    label: Color(0xFF2B2F36),
    labelHalo: Color(0xFFFFFFFF),
    poi: Color(0xFF1F7FD1),
    roadWidthFactor: 1.0,
  );

  static const dark = MapPalette(
    background: Color(0xFF14181F),
    water: Color(0xFF0F3552),
    green: Color(0xFF1B3324),
    wood: Color(0xFF173021),
    building: Color(0xFF222833),
    roadMinor: Color(0xFF3A4250),
    roadMajor: Color(0xFF55607A),
    roadMotorway: Color(0xFF7A6A3C),
    roadCasing: Color(0xFF0E1116),
    path: Color(0xFF5B6372),
    rail: Color(0xFF59606E),
    cycleway: Color(0xFF3FBF73),
    label: Color(0xFFE3E7EE),
    labelHalo: Color(0xFF14181F),
    poi: Color(0xFF6FB4F2),
    roadWidthFactor: 1.0,
  );

  /// Contraste élevé : fond clair, routes noires épaisses, textes noirs gras.
  static const contrast = MapPalette(
    background: Color(0xFFFFFFFF),
    water: Color(0xFF6FA8E6),
    green: Color(0xFFB7E0A5),
    wood: Color(0xFF9ACF86),
    building: Color(0xFFD0D0D0),
    roadMinor: Color(0xFFFFFFFF),
    roadMajor: Color(0xFFFFE066),
    roadMotorway: Color(0xFFFF9F1C),
    roadCasing: Color(0xFF000000),
    path: Color(0xFF000000),
    rail: Color(0xFF000000),
    cycleway: Color(0xFF007A33),
    label: Color(0xFF000000),
    labelHalo: Color(0xFFFFFFFF),
    poi: Color(0xFF0050B3),
    roadWidthFactor: 1.35,
  );

  /// Style personnalisé : couleurs de l'utilisateur appliquées sur une base claire ou sombre.
  /// Les textes et le contour des routes restent lisibles quelles que soient les couleurs choisies.
  factory MapPalette.custom(AppSettings s, {required bool dark}) {
    final base = dark ? MapPalette.dark : MapPalette.light;
    final bg = dark ? base.background : base.background;
    final road = Color(s.customRoadColor);
    final water = Color(s.customWaterColor);
    final green = Color(s.customGreenColor);
    final building = Color(s.customBuildingColor);
    return MapPalette(
      background: bg,
      water: water,
      green: green,
      wood: Color.lerp(green, const Color(0xFF000000), 0.08)!,
      building: building,
      roadMinor: road,
      roadMajor: Color.lerp(road, const Color(0xFFFFC857), 0.45)!,
      roadMotorway: Color.lerp(road, const Color(0xFFF59E0B), 0.65)!,
      roadCasing: ensureContrast(Color.lerp(road, dark ? const Color(0xFF000000) : const Color(0xFF6B6558), 0.55)!, road, minRatio: 1.4),
      path: base.path,
      rail: base.rail,
      cycleway: base.cycleway,
      label: ensureContrast(base.label, bg, minRatio: 7),
      labelHalo: base.labelHalo,
      poi: base.poi,
      roadWidthFactor: 1.0,
    );
  }

  static MapPalette forSettings(AppSettings s, Brightness systemBrightness) {
    final dark = s.mapStyle == MapStyleChoice.dark ||
        (s.mapStyle == MapStyleChoice.auto && systemBrightness == Brightness.dark) ||
        (s.mapStyle == MapStyleChoice.custom && systemBrightness == Brightness.dark);
    switch (s.mapStyle) {
      case MapStyleChoice.contrast:
        return contrast;
      case MapStyleChoice.custom:
        return MapPalette.custom(s, dark: dark);
      case MapStyleChoice.light:
        return light;
      case MapStyleChoice.dark:
        return MapPalette.dark;
      case MapStyleChoice.auto:
        return dark ? MapPalette.dark : light;
    }
  }
}

/// Construit le style MapLibre (JSON, schéma de tuiles OpenMapTiles) de Strasse.
///
/// Le style est généré par le code : couleurs, densité, bâtiments, points d'intérêt, transports et pistes cyclables
/// répondent aux réglages de l'utilisateur. Sans serveur de tuiles configuré, il ne contient que le fond de carte.
class MapStyleBuilder {
  const MapStyleBuilder._();

  static String build({
    required MapPalette palette,
    required AppSettings settings,
    required String tilesUrl,
    required String glyphsUrl,
    required String font,
    String attribution = '',
  }) =>
      jsonEncode(buildMap(
        palette: palette,
        settings: settings,
        tilesUrl: tilesUrl,
        glyphsUrl: glyphsUrl,
        font: font,
        attribution: attribution,
      ));

  static Map<String, dynamic> buildMap({
    required MapPalette palette,
    required AppSettings settings,
    required String tilesUrl,
    required String glyphsUrl,
    required String font,
    String attribution = '',
  }) {
    final p = palette;
    final hasTiles = tilesUrl.trim().isNotEmpty;
    final density = settings.mapDensity; // 0 épuré, 1 normal, 2 détaillé
    final labelShift = const [1.0, 0.0, -1.0][density];
    final fonts = [font];
    final w = p.roadWidthFactor;

    Map<String, dynamic> source() {
      final attr = ['© OpenStreetMap contributors', if (attribution.isNotEmpty) attribution].join(' · ');
      if (tilesUrl.contains('{z}')) {
        return {'type': 'vector', 'tiles': [tilesUrl], 'minzoom': 0, 'maxzoom': 14, 'attribution': attr};
      }
      return {'type': 'vector', 'url': tilesUrl, 'attribution': attr};
    }

    dynamic width(double z5, double z12, double z16, double z19) => [
          'interpolate', ['exponential', 1.4], ['zoom'],
          5, z5 * w, 12, z12 * w, 16, z16 * w, 19, z19 * w,
        ];

    List<dynamic> classes(List<String> list) => ['match', ['get', 'class'], list, true, false];

    Map<String, dynamic> roadLayer(String id, List<String> cls, Color color, List<double> widths, {Color? casing, double minzoom = 0, bool casingLayer = false, List<double>? dash}) {
      return {
        'id': id,
        'type': 'line',
        'source': 'strasse',
        'source-layer': 'transportation',
        'minzoom': minzoom,
        'filter': ['all', classes(cls), ['!=', ['get', 'brunnel'], 'tunnel']],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': hex(casingLayer ? (casing ?? p.roadCasing) : color),
          'line-width': width(widths[0], widths[1], widths[2], widths[3]),
          if (dash != null) 'line-dasharray': dash,
        },
      };
    }

    final layers = <Map<String, dynamic>>[
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': hex(p.background)},
      },
    ];

    if (hasTiles) {
      layers.addAll([
        {
          'id': 'landcover',
          'type': 'fill',
          'source': 'strasse',
          'source-layer': 'landcover',
          'filter': classes(['grass', 'farmland', 'wetland']),
          'paint': {'fill-color': hex(p.green), 'fill-opacity': 0.75},
        },
        {
          'id': 'wood',
          'type': 'fill',
          'source': 'strasse',
          'source-layer': 'landcover',
          'filter': classes(['wood']),
          'paint': {'fill-color': hex(p.wood), 'fill-opacity': 0.85},
        },
        {
          'id': 'park',
          'type': 'fill',
          'source': 'strasse',
          'source-layer': 'park',
          'paint': {'fill-color': hex(p.green), 'fill-opacity': 0.7},
        },
        {
          'id': 'water',
          'type': 'fill',
          'source': 'strasse',
          'source-layer': 'water',
          'paint': {'fill-color': hex(p.water)},
        },
        {
          'id': 'waterway',
          'type': 'line',
          'source': 'strasse',
          'source-layer': 'waterway',
          'paint': {'line-color': hex(p.water), 'line-width': width(0.4, 1.2, 3, 8)},
        },
      ]);

      if (settings.showBuildings) {
        layers.addAll([
          {
            'id': 'building',
            'type': 'fill',
            'source': 'strasse',
            'source-layer': 'building',
            'minzoom': 13,
            'maxzoom': 15,
            'paint': {'fill-color': hex(p.building), 'fill-opacity': 0.8},
          },
          {
            'id': 'building-3d',
            'type': 'fill-extrusion',
            'source': 'strasse',
            'source-layer': 'building',
            'minzoom': 15,
            'paint': {
              'fill-extrusion-color': hex(p.building),
              'fill-extrusion-height': ['coalesce', ['get', 'render_height'], 6],
              'fill-extrusion-base': ['coalesce', ['get', 'render_min_height'], 0],
              'fill-extrusion-opacity': p.isDark ? 0.85 : 0.75,
            },
          },
        ]);
      }

      if (settings.showTransit) {
        layers.add({
          'id': 'rail',
          'type': 'line',
          'source': 'strasse',
          'source-layer': 'transportation',
          'minzoom': 8,
          'filter': classes(['rail', 'transit']),
          'paint': {
            'line-color': hex(p.rail),
            'line-width': width(0.5, 1.2, 2.2, 4),
            'line-dasharray': [3, 2],
          },
        });
      }

      // Routes : contour puis remplissage, de la moins importante à la plus importante.
      const minor = ['minor', 'service'];
      const secondary = ['tertiary', 'secondary'];
      const major = ['primary', 'trunk'];
      const motorway = ['motorway'];
      layers.addAll([
        roadLayer('road-path', ['path', 'track', 'pedestrian'], p.path, [0.2, 0.6, 1.2, 2.4], minzoom: 13, dash: [2, 2]),
        roadLayer('road-minor-casing', minor, p.roadMinor, [0.4, 1.6, 6, 22], casingLayer: true, minzoom: 12),
        roadLayer('road-minor', minor, p.roadMinor, [0.3, 1.2, 4.6, 18], minzoom: 12),
        roadLayer('road-secondary-casing', secondary, p.roadMinor, [0.6, 2.6, 8, 26], casingLayer: true, minzoom: 9),
        roadLayer('road-secondary', secondary, p.roadMajor, [0.4, 2, 6.4, 22], minzoom: 9),
        roadLayer('road-major-casing', major, p.roadMajor, [0.8, 3.2, 9, 28], casingLayer: true, minzoom: 6),
        roadLayer('road-major', major, p.roadMajor, [0.6, 2.6, 7.4, 24], minzoom: 6),
        roadLayer('road-motorway-casing', motorway, p.roadMotorway, [1, 3.6, 10, 30], casingLayer: true, minzoom: 4),
        roadLayer('road-motorway', motorway, p.roadMotorway, [0.8, 3, 8, 26], minzoom: 4),
      ]);

      if (settings.showCycleways) {
        layers.add({
          'id': 'cycleway',
          'type': 'line',
          'source': 'strasse',
          'source-layer': 'transportation',
          'minzoom': 12,
          'filter': ['all', ['==', ['get', 'class'], 'path'], ['==', ['get', 'subclass'], 'cycleway']],
          'layout': {'line-cap': 'round', 'line-join': 'round'},
          'paint': {
            'line-color': hex(p.cycleway),
            'line-width': width(0.8, 1.6, 2.6, 4),
            'line-dasharray': [1.6, 1.2],
          },
        });
      }

      // Étiquettes de rues.
      layers.add({
        'id': 'road-labels',
        'type': 'symbol',
        'source': 'strasse',
        'source-layer': 'transportation_name',
        'minzoom': 14 + labelShift,
        'layout': {
          'symbol-placement': 'line',
          'text-field': ['coalesce', ['get', 'name:fr'], ['get', 'name']],
          'text-font': fonts,
          'text-size': ['interpolate', ['linear'], ['zoom'], 14, 10, 18, 13],
          'text-letter-spacing': 0.02,
        },
        'paint': {
          'text-color': hex(p.label),
          'text-halo-color': hex(p.labelHalo),
          'text-halo-width': 1.6,
        },
      });

      // Points d'intérêt : pastille + nom, selon la densité choisie.
      if (settings.showPoi) {
        layers.addAll([
          {
            'id': 'poi-dots',
            'type': 'circle',
            'source': 'strasse',
            'source-layer': 'poi',
            'minzoom': 15 + labelShift,
            'filter': ['<=', ['get', 'rank'], density == 0 ? 8 : (density == 1 ? 20 : 50)],
            'paint': {
              'circle-radius': ['interpolate', ['linear'], ['zoom'], 15, 3, 19, 6],
              'circle-color': hex(p.poi),
              'circle-stroke-color': hex(p.labelHalo),
              'circle-stroke-width': 1.4,
            },
          },
          {
            'id': 'poi-labels',
            'type': 'symbol',
            'source': 'strasse',
            'source-layer': 'poi',
            'minzoom': 16 + labelShift,
            'filter': ['<=', ['get', 'rank'], density == 0 ? 8 : (density == 1 ? 20 : 50)],
            'layout': {
              'text-field': ['coalesce', ['get', 'name:fr'], ['get', 'name']],
              'text-font': fonts,
              'text-size': 11,
              'text-offset': [0, 0.9],
              'text-anchor': 'top',
              'text-optional': true,
            },
            'paint': {
              'text-color': hex(p.label),
              'text-halo-color': hex(p.labelHalo),
              'text-halo-width': 1.4,
            },
          },
        ]);
      }

      if (settings.showTransit) {
        layers.add({
          'id': 'transit-stops',
          'type': 'symbol',
          'source': 'strasse',
          'source-layer': 'poi',
          'minzoom': 15 + labelShift,
          'filter': classes(['railway', 'bus']),
          'layout': {
            'text-field': ['coalesce', ['get', 'name:fr'], ['get', 'name']],
            'text-font': fonts,
            'text-size': 11,
            'text-optional': true,
          },
          'paint': {
            'text-color': hex(p.poi),
            'text-halo-color': hex(p.labelHalo),
            'text-halo-width': 1.4,
          },
        });
      }

      // Lieux : pays, régions, villes, quartiers.
      Map<String, dynamic> place(String id, List<String> cls, double minzoom, double maxzoom, List<double> size, {bool upper = false}) => {
            'id': id,
            'type': 'symbol',
            'source': 'strasse',
            'source-layer': 'place',
            'minzoom': minzoom,
            'maxzoom': maxzoom,
            'filter': classes(cls),
            'layout': {
              'text-field': ['coalesce', ['get', 'name:fr'], ['get', 'name']],
              'text-font': fonts,
              'text-size': ['interpolate', ['linear'], ['zoom'], minzoom, size[0], maxzoom, size[1]],
              if (upper) 'text-transform': 'uppercase',
              'text-max-width': 8,
            },
            'paint': {
              'text-color': hex(p.label),
              'text-halo-color': hex(p.labelHalo),
              'text-halo-width': 1.8,
            },
          };
      layers.addAll([
        place('place-country', ['country'], 1, 6, [11, 17], upper: true),
        place('place-state', ['state'], 4 + labelShift, 8, [10, 14], upper: true),
        place('place-city', ['city'], 4, 14, [13, 22]),
        place('place-town', ['town'], 8 + labelShift, 15, [11, 18]),
        place('place-village', ['village', 'suburb'], 11 + labelShift, 16, [10, 15]),
        place('place-hamlet', ['hamlet', 'neighbourhood', 'quarter'], 13 + labelShift, 17, [10, 13]),
      ]);
    }

    return {
      'version': 8,
      'name': 'Strasse',
      'glyphs': glyphsUrl.isEmpty ? 'https://invalid.local/{fontstack}/{range}.pbf' : glyphsUrl,
      if (hasTiles) 'sources': {'strasse': source()} else 'sources': <String, dynamic>{},
      'layers': layers,
    };
  }
}
