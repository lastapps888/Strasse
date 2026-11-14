import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/data/providers/motis_client.dart';
import 'package:strasse/data/providers/transit_lines_client.dart';

void main() {
  test('MOTIS : arrêts', () {
    final stops = MotisTransitRouter.parseStops([
      {'stopId': 'fr-x_123', 'name': 'Gare', 'lat': 48.58, 'lon': 7.75, 'modes': ['RAIL', 'TRAM']},
      {'name': 'sans identifiant', 'lat': 1, 'lon': 1},
    ]);
    expect(stops.length, 1);
    expect(stops.first.modes, ['RAIL', 'TRAM']);
  });

  test('MOTIS : passages triés, temps réel et retard', () {
    final deps = MotisTransitRouter.parseDepartures({
      'stopTimes': [
        {
          'mode': 'BUS',
          'routeShortName': '12',
          'headsign': 'Centre',
          'realTime': true,
          'place': {'scheduledDeparture': '2026-11-08T10:05:00Z', 'departure': '2026-11-08T10:08:00Z'},
        },
        {
          'mode': 'TRAM',
          'routeShortName': 'A',
          'place': {'scheduledDeparture': '2026-11-08T10:01:00Z'},
        },
      ],
    });
    expect(deps.first.routeName, 'A');
    expect(deps.last.delay.inMinutes, 3);
    expect(deps.last.realTime, isTrue);
  });

  test('MOTIS : itinéraire avec marche et bus', () {
    final its = MotisTransitRouter.parsePlan({
      'itineraries': [
        {
          'startTime': '2026-11-08T10:00:00Z',
          'endTime': '2026-11-08T10:30:00Z',
          'transfers': 0,
          'legs': [
            {'mode': 'WALK', 'from': {'name': 'A', 'lat': 48.0, 'lon': 7.0}, 'to': {'name': 'B', 'lat': 48.0, 'lon': 7.001}, 'startTime': '2026-11-08T10:00:00Z', 'endTime': '2026-11-08T10:05:00Z', 'distance': 300},
            {'mode': 'BUS', 'routeShortName': '4', 'from': {'name': 'B', 'lat': 48.0, 'lon': 7.001}, 'to': {'name': 'C', 'lat': 48.1, 'lon': 7.1}, 'startTime': '2026-11-08T10:05:00Z', 'endTime': '2026-11-08T10:30:00Z', 'distance': 9000},
          ],
        },
      ],
    });
    expect(its.single.legs.length, 2);
    expect(its.single.walkDistanceM, 300);
  });

  test('Overpass : relations de lignes et télécabine', () {
    final lines = TransitLinesClient.parse({
      'elements': [
        {
          'type': 'relation',
          'id': 1,
          'tags': {'route': 'tram', 'ref': 'A', 'colour': '#E2001A', 'from': 'X', 'to': 'Y'},
          'members': [
            {'type': 'way', 'role': '', 'geometry': [{'lat': 48.0, 'lon': 7.0}, {'lat': 48.1, 'lon': 7.1}]},
            {'type': 'node', 'role': 'stop'},
          ],
        },
        {
          'type': 'way',
          'id': 2,
          'tags': {'aerialway': 'gondola', 'name': 'Télécabine'},
          'geometry': [{'lat': 45.0, 'lon': 6.0}, {'lat': 45.01, 'lon': 6.01}],
        },
      ],
    });
    expect(lines.length, 2);
    expect(lines.first.colorHex, '#e2001a');
    expect(lines.last.mode, 'aerialway');
  });
}
