import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/features/offline_maps/offline_manager.dart';

GeoBounds _box(GeoPoint c, double wKm, double hKm) {
  final dLat = hKm / 2 / 111.0;
  final dLon = wKm / 2 / (111.0 * 0.68);
  return GeoBounds(south: c.lat - dLat, west: c.lon - dLon, north: c.lat + dLat, east: c.lon + dLon);
}

void main() {
  const center = GeoPoint(47, 2);

  test('une zone de 200 × 200 km passe en zoom automatique', () {
    final b = _box(center, 200, 200);
    final z = maxZoomWithinLimit(b, 6, ceiling: 14);
    expect(z, isNotNull);
    expect(z!, greaterThanOrEqualTo(12));
    expect(regionLimitMessage(b, 6, z), isNull);
  });

  test('1 000 × 1 000 km est acceptée à un zoom réduit, refusée en détaillé', () {
    final b = _box(center, 990, 990);
    final z = maxZoomWithinLimit(b, 6, ceiling: 14);
    expect(z, isNotNull);
    expect(regionLimitMessage(b, 6, z!), isNull);
    expect(regionLimitMessage(b, 6, 14), isNotNull);
  });

  test('plus de 1 000 km de côté : refus', () {
    expect(regionLimitMessage(_box(center, 1300, 100), 6, 8), contains('maximum'));
  });

  test('forme rectangulaire libre 100 × 400 km', () {
    final b = _box(center, 100, 400);
    expect(boundsWidthKm(b).round(), closeTo(100, 3));
    expect(boundsHeightKm(b).round(), closeTo(400, 3));
    final z = maxZoomWithinLimit(b, 6, ceiling: 14)!;
    expect(regionLimitMessage(b, 6, z), isNull);
  });

  test('subBounds : la moitié de l\'écran couvre la moitié de la longitude', () {
    const view = GeoBounds(south: 40, west: 0, north: 50, east: 10);
    final b = subBounds(view, left: 0, top: 0, right: 0.5, bottom: 1);
    expect(b.east, closeTo(5, 1e-9));
    expect(b.north, closeTo(50, 1e-6));
    expect(b.south, closeTo(40, 1e-6));
  });

  test('l\'estimation de taille croît avec le zoom', () {
    final b = _box(center, 50, 50);
    expect(estimateRegionBytes(b, 6, 14), greaterThan(estimateRegionBytes(b, 6, 12)));
  });
}
