import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/features/map/poi_badges.dart';

void main() {
  group('Strasse map POI badges', () {
    test('uses a lodging badge for hotels', () {
      expect(PoiBadges.forPoi('hotel', null).image, 'poi-lodging');
    });

    test('uses the restaurant badge for restaurants', () {
      expect(PoiBadges.forPoi('restaurant', null).image, 'poi-food');
    });

    test('uses the tourism category badge when available', () {
      expect(PoiBadges.forPoi('tourism', 'museum').image, 'poi-culture');
      expect(PoiBadges.forPoi('tourism', 'viewpoint').image, 'poi-culture');
    });

    test('uses a generic badge rather than inventing an unsupported category', () {
      expect(PoiBadges.forPoi('tourism', 'unknown-kind').image, 'poi-other');
    });
  });
}
