import 'package:flutter/material.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/data/providers/transit_lines_client.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/features/map/strasse_map.dart';
import 'package:dio/dio.dart';

/// Couleur de repli par mode quand la ligne n'a pas de couleur propre dans OpenStreetMap.
Color transitModeColor(String mode) {
  switch (mode.toLowerCase()) {
    case 'bus':
    case 'trolleybus':
      return const Color(0xFF1565C0);
    case 'coach':
      return const Color(0xFF6A1B9A);
    case 'tram':
    case 'light_rail':
      return const Color(0xFFE65100);
    case 'subway':
    case 'metro':
      return const Color(0xFFC62828);
    case 'train':
    case 'rail':
    case 'regional_rail':
      return const Color(0xFF2E7D32);
    case 'funicular':
      return const Color(0xFF8D6E63);
    case 'ferry':
      return const Color(0xFF00838F);
    case 'aerialway':
    case 'cable_car':
    case 'gondola':
      return const Color(0xFFAD1457);
    default:
      return const Color(0xFF546E7A);
  }
}

IconData transitModeIcon(String mode) {
  switch (mode.toLowerCase()) {
    case 'bus':
    case 'trolleybus':
    case 'coach':
      return Icons.directions_bus_rounded;
    case 'tram':
    case 'light_rail':
      return Icons.tram_rounded;
    case 'subway':
    case 'metro':
      return Icons.subway_rounded;
    case 'train':
    case 'rail':
    case 'regional_rail':
    case 'highspeed_rail':
    case 'long_distance':
      return Icons.train_rounded;
    case 'ferry':
      return Icons.directions_boat_rounded;
    case 'funicular':
      return Icons.directions_railway_rounded;
    case 'aerialway':
    case 'cable_car':
    case 'gondola':
    case 'aerial_lift':
      return Icons.airline_seat_recline_normal_rounded;
    default:
      return Icons.directions_transit_rounded;
  }
}

Color _parse(String hex) {
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  final v = h.length == 6 ? int.tryParse(h, radix: 16) : null;
  return v == null ? const Color(0xFF546E7A) : Color(0xFF000000 | v);
}

/// Ce que la couche « Transports » affiche pour une zone.
class TransitOverlayData {
  const TransitOverlayData({this.lines = const [], this.stops = const [], this.zoomHint = false, this.error});
  final List<TransitLine> lines;
  final List<TransitStop> stops;

  /// Zone trop grande pour interroger les lignes.
  final bool zoomHint;
  final Object? error;
}

class TransitOverlay {
  TransitOverlay._();

  /// Arrêts visibles uniquement en zone resserrée (≈ zoom 15) pour ne pas noyer la carte.
  static const double maxStopSpan = 0.04;
  static const int maxPolylines = 300;
  static const int maxStops = 160;

  static Future<TransitOverlayData> load(TransitData data, GeoBounds b, {CancelToken? cancel}) async {
    final span = b.latSpan > b.lonSpan ? b.latSpan : b.lonSpan;
    if (span > TransitLinesClient.maxSpanHeavy) return const TransitOverlayData(zoomHint: true);
    Object? error;
    final osmLines = data.lines.linesIn(b, cancel: cancel).catchError((Object e) {
      error = e;
      return <TransitLine>[];
    });
    final stops = (data.motis != null && span <= maxStopSpan)
        ? data.motis!.stopsIn(b, cancel: cancel).catchError((Object e) {
            error ??= e;
            return <TransitStop>[];
          })
        : Future.value(<TransitStop>[]);
    // Transitous agrège les flux GTFS ouverts. Il complète Overpass même lorsque certaines relations OSM
    // existent déjà : une réponse OSM partielle ne doit pas masquer les lignes des opérateurs non cartographiées.
    final timetableLines = (data.motis != null && span <= maxStopSpan * 3)
        ? data.motis!.linesIn(b, cancel: cancel).catchError((Object e) {
            error ??= e;
            return <TransitLine>[];
          })
        : Future.value(<TransitLine>[]);
    final osm = await osmLines;
    final s = await stops;
    final gtfs = await timetableLines;
    final merged = mergeLines(osm, gtfs);
    return TransitOverlayData(lines: merged, stops: s, error: merged.isEmpty && s.isEmpty ? error : null);
  }

  /// Fusionne les relations OSM et les tracés issus des voyages GTFS actifs.
  ///
  /// OSM garde la priorité pour ses noms, opérateurs et couleurs. Les formes de Transitous complètent
  /// les relations partielles ; des formes identiques ne sont ajoutées qu'une fois.
  static List<TransitLine> mergeLines(List<TransitLine> osm, List<TransitLine> gtfs) {
    final merged = <TransitLine>[...osm];
    final indexes = <String, List<int>>{};

    String normalize(String? value) => (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\\s+'), ' ');
    String shapeKey(List<GeoPoint> shape) => shape
        .map((point) => '${point.lat.toStringAsFixed(5)},${point.lon.toStringAsFixed(5)}')
        .join(';');

    for (var i = 0; i < merged.length; i++) {
      final line = merged[i];
      final route = normalize(line.ref);
      if (route.isEmpty) continue;
      final base = '${normalize(line.mode)}|$route';
      indexes.putIfAbsent(base, () => []).add(i);
    }

    for (final line in gtfs) {
      final route = normalize(line.ref);
      if (route.isEmpty) {
        merged.add(line);
        continue;
      }
      final base = '${normalize(line.mode)}|$route';
      final candidates = indexes[base] ?? const <int>[];
      final agency = normalize(line.operator);
      int? match;
      for (final index in candidates) {
        final existingAgency = normalize(merged[index].operator);
        if (agency.isEmpty || existingAgency.isEmpty || agency == existingAgency) {
          match = index;
          break;
        }
      }
      if (match == null) {
        final index = merged.length;
        merged.add(line);
        indexes.putIfAbsent(base, () => []).add(index);
        continue;
      }

      final existing = merged[match];
      final knownShapes = existing.shapes.map(shapeKey).toSet();
      final combinedShapes = <List<GeoPoint>>[
        ...existing.shapes,
        for (final shape in line.shapes)
          if (shape.length >= 2 && !knownShapes.contains(shapeKey(shape))) shape,
      ];
      merged[match] = TransitLine(
        id: existing.id,
        mode: existing.mode,
        ref: existing.ref,
        name: existing.name ?? line.name,
        colorHex: existing.colorHex ?? line.colorHex,
        from: existing.from ?? line.from,
        to: existing.to ?? line.to,
        operator: existing.operator ?? line.operator,
        shapes: combinedShapes,
      );
    }
    return merged;
  }

  static List<MapPolyline> polylines(List<TransitLine> lines) {
    final out = <MapPolyline>[];
    // Lourds d'abord : le rail et le tram restent visibles sous les bus.
    final sorted = [...lines]..sort((a, b) => _weight(a.mode).compareTo(_weight(b.mode)));
    for (final l in sorted) {
      final color = l.colorHex != null ? _parse(l.colorHex!) : transitModeColor(l.mode);
      final width = _weight(l.mode) <= 1 ? 5.0 : 3.5;
      for (final shape in l.shapes) {
        if (out.length >= maxPolylines) return out;
        out.add(MapPolyline(points: shape, color: color, width: width, tag: l));
      }
    }
    return out;
  }

  static int _weight(String mode) {
    switch (mode) {
      case 'train':
      case 'subway':
      case 'tram':
      case 'light_rail':
      case 'funicular':
      case 'aerialway':
        return 1;
      case 'ferry':
      case 'monorail':
        return 2;
      default:
        return 3;
    }
  }

  static List<MapPin> pins(List<TransitStop> stops, void Function(TransitStop) onTap) => [
        for (final s in stops.take(maxStops))
          MapPin(id: 'stop:${s.id}', point: s.point, color: transitModeColor(s.modes.isEmpty ? 'bus' : s.modes.first), radius: 6, onTap: () => onTap(s)),
      ];
}
