import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/core/core.dart';

void main() {
  test('distance Paris–Lyon environ 392 km', () {
    final d = distanceM(const GeoPoint(48.8566, 2.3522), const GeoPoint(45.7640, 4.8357));
    expect(d / 1000, closeTo(392, 5));
  });

  test('normalizeDeg et angleDiffDeg', () {
    expect(normalizeDeg(-90), 270);
    expect(normalizeDeg(450), 90);
    expect(angleDiffDeg(10, 350), 20);
    expect(angleDiffDeg(350, 10), -20);
  });

  test('GeoBounds.contains', () {
    final b = GeoBounds(south: 0, west: 0, north: 1, east: 1);
    expect(b.contains(const GeoPoint(0.5, 0.5)), isTrue);
    expect(b.contains(const GeoPoint(1.5, 0.5)), isFalse);
  });
}
