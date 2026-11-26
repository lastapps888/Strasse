import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/features/music/music_controller.dart';
import 'package:strasse/features/music/music_models.dart';

void main() {
  group('Deezer catalogue mode', () {
    test('public catalogue availability is not an authenticated or playing session', () {
      const state = MusicState(
        source: MusicSource.deezer,
        connected: false,
        catalogAvailable: true,
      );

      expect(state.catalogAvailable, isTrue);
      expect(state.connected, isFalse);
    });

    test('starting and stopping previews does not remove catalogue access', () {
      const catalog = MusicState(
        source: MusicSource.deezer,
        connected: false,
        catalogAvailable: true,
      );

      final playing = catalog.copyWith(connected: true);
      final stopped = playing.copyWith(connected: false);

      expect(playing.catalogAvailable, isTrue);
      expect(stopped.catalogAvailable, isTrue);
      expect(stopped.connected, isFalse);
    });

    test('Spotify does not expose Deezer public catalogue mode', () {
      const spotify = MusicState(
        source: MusicSource.spotify,
        connected: false,
      );

      expect(spotify.catalogAvailable, isFalse);
    });
  });
}
