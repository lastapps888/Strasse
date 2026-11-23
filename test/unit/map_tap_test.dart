import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/features/map/strasse_map.dart';

void main() {
  group('MapLibre rendered POI hit testing', () {
    test('opens a named point from a provider POI source layer', () {
      final place = StrasseMapController.placeFromRenderedFeature({
        'id': 123,
        'sourceLayer': 'poi',
        'properties': {
          'name': 'Musée des beaux-arts',
          'class': 'tourism',
          'subclass': 'museum',
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [4.8357, 45.7640],
        },
      });

      expect(place, isNotNull);
      expect(place!.id, 'map:123');
      expect(place.name, 'Musée des beaux-arts');
      expect(place.category, 'museum');
      expect(place.point.lat, 45.7640);
      expect(place.point.lon, 4.8357);
    });

    test('accepts point features from custom layer names when their class is a POI', () {
      final place = StrasseMapController.placeFromRenderedFeature({
        'layer': {'id': 'strasse-custom-place-icons'},
        'properties': {
          'name:fr': 'Restaurant Exemple',
          'class': 'amenity',
          'subclass': 'restaurant',
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [2.3522, 48.8566],
        },
      });

      expect(place, isNotNull);
      expect(place!.name, 'Restaurant Exemple');
      expect(place.category, 'restaurant');
    });

    test('does not turn a road into a place sheet', () {
      final place = StrasseMapController.placeFromRenderedFeature({
        'sourceLayer': 'transportation',
        'properties': {'name': 'Rue de la République', 'class': 'primary'},
        'geometry': {
          'type': 'Point',
          'coordinates': [4.83, 45.76],
        },
      });

      expect(place, isNull);
    });

    test('does not turn polygon or unnamed features into a place sheet', () {
      final polygon = StrasseMapController.placeFromRenderedFeature({
        'sourceLayer': 'poi',
        'properties': {'name': 'Place'},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [],
        },
      });
      final unnamed = StrasseMapController.placeFromRenderedFeature({
        'sourceLayer': 'poi',
        'properties': {'class': 'tourism', 'subclass': 'museum'},
        'geometry': {
          'type': 'Point',
          'coordinates': [4.83, 45.76],
        },
      });

      expect(polygon, isNull);
      expect(unnamed, isNull);
    });
  });
}
