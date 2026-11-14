import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/core/core.dart';

void main() {
  test('optimizeWaypointOrder garde départ et arrivée et raccourcit le trajet', () {
    const pts = [GeoPoint(0, 0), GeoPoint(0, 3), GeoPoint(0, 1), GeoPoint(0, 2), GeoPoint(0, 4)];
    final order = optimizeWaypointOrder(pts);
    expect(order.first, 0);
    expect(order.last, 4);
    expect(order, [0, 2, 3, 1, 4]);
  });
}
