import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/transit/transit_style.dart';

TransitLine _line({
  required String id,
  required String mode,
  required String ref,
  required List<List<GeoPoint>> shapes,
  String? name,
  String? color,
  String? operator,
}) =>
    TransitLine(
      id: id,
      mode: mode,
      ref: ref,
      shapes: shapes,
      name: name,
      colorHex: color,
      operator: operator,
    );

void main() {
  group('Transit OSM and GTFS line merge', () {
    final a = GeoPoint(45.0, 4.0);
    final b = GeoPoint(45.01, 4.01);
    final c = GeoPoint(45.02, 4.02);
    final d = GeoPoint(45.03, 4.03);

    test('adds timetable shapes to a partially mapped OSM route', () {
      final osm = _line(
        id: 'relation/123',
        mode: 'bus',
        ref: '10',
        name: 'Centre – Gare',
        color: '#123456',
        operator: 'Réseau A',
        shapes: [[a, b]],
      );
      final gtfs = _line(
        id: 'motis/1',
        mode: 'bus',
        ref: '10',
        name: 'Route 10',
        color: '#abcdef',
        operator: 'Réseau A',
        shapes: [[b, c], [c, d]],
      );

      final result = TransitOverlay.mergeLines([osm], [gtfs]);

      expect(result, hasLength(1));
      expect(result.single.id, 'relation/123');
      expect(result.single.name, 'Centre – Gare');
      expect(result.single.colorHex, '#123456');
      expect(result.single.shapes, [[a, b], [b, c], [c, d]]);
    });

    test('does not duplicate identical geometry returned by both providers', () {
      final shape = [a, b, c];
      final result = TransitOverlay.mergeLines(
        [_line(id: 'relation/1', mode: 'tram', ref: 'T1', shapes: [shape])],
        [_line(id: 'motis/2', mode: 'tram', ref: 'T1', shapes: [[a, b, c]])],
      );

      expect(result, hasLength(1));
      expect(result.single.shapes, [shape]);
    });

    test('preserves different operators using the same line reference', () {
      final result = TransitOverlay.mergeLines(
        [_line(id: 'relation/1', mode: 'bus', ref: '1', operator: 'Operator A', shapes: [[a, b]])],
        [_line(id: 'motis/2', mode: 'bus', ref: '1', operator: 'Operator B', shapes: [[c, d]])],
      );

      expect(result, hasLength(2));
    });

    test('keeps unnumbered lines instead of merging unrelated routes', () {
      final result = TransitOverlay.mergeLines(
        [_line(id: 'relation/1', mode: 'bus', ref: '', name: 'Shuttle A', shapes: [[a, b]])],
        [_line(id: 'motis/2', mode: 'bus', ref: '', name: 'Shuttle B', shapes: [[c, d]])],
      );

      expect(result, hasLength(2));
    });
  });
}
