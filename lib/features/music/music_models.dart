import 'package:flutter/material.dart';

/// Source de musique. Chaque source déclare ce qu'elle sait réellement faire ([MusicCapabilities]).
enum MusicSource {
  spotify('Spotify', Icons.music_note_rounded),
  appleMusic('Apple Music', Icons.apple_rounded),
  deezer('Deezer', Icons.graphic_eq_rounded),
  youtubeMusic('YouTube Music', Icons.smart_display_rounded),
  local('Sur l\'appareil', Icons.phone_android_rounded);

  const MusicSource(this.label, this.icon);
  final String label;
  final IconData icon;

  static MusicSource? fromName(String? n) {
    for (final s in MusicSource.values) {
      if (s.name == n) return s;
    }
    return null;
  }
}

enum PlayerRepeatMode {
  off,
  all,
  one;

  PlayerRepeatMode get next => PlayerRepeatMode.values[(index + 1) % PlayerRepeatMode.values.length];
}

/// Commandes réellement supportées par une source : l'interface masque les autres.
class MusicCapabilities {
  const MusicCapabilities({
    this.playPause = true,
    this.skip = true,
    this.seek = false,
    this.volume = false,
    this.shuffle = false,
    this.repeat = false,
    this.search = false,
    this.browse = const {},
  });

  final bool playPause;
  final bool skip;
  final bool seek;
  final bool volume;
  final bool shuffle;
  final bool repeat;
  final bool search;

  /// Parties de la bibliothèque consultables.
  final Set<CollectionKind> browse;
}

enum CollectionKind {
  album('Albums'),
  artist('Artistes'),
  playlist('Playlists'),
  track('Titres');

  const CollectionKind(this.label);
  final String label;
}

class MusicTrack {
  const MusicTrack({required this.id, required this.title, this.artist = '', this.album = '', this.artUrl, this.durationMs = 0, this.uri, this.previewOnly = false});

  final String id;
  final String title;
  final String artist;
  final String album;
  final String? artUrl;
  final int durationMs;

  /// Adresse de lecture : URI Spotify, fichier, URL d'extrait…
  final String? uri;

  /// Extrait de 30 s seulement (Deezer) : l'interface le dit.
  final bool previewOnly;
}

class MusicCollection {
  const MusicCollection({required this.id, required this.kind, required this.title, this.subtitle = '', this.artUrl, this.uri});

  final String id;
  final CollectionKind kind;
  final String title;
  final String subtitle;
  final String? artUrl;
  final String? uri;
}

class MusicResults {
  const MusicResults({this.tracks = const [], this.collections = const []});
  final List<MusicTrack> tracks;
  final List<MusicCollection> collections;
  bool get isEmpty => tracks.isEmpty && collections.isEmpty;
}

class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.track,
    this.playing = false,
    this.positionMs = 0,
    this.durationMs = 0,
    this.volume,
    this.shuffle = false,
    this.repeat = PlayerRepeatMode.off,
    this.deviceName,
  });

  static const idle = PlaybackSnapshot();

  final MusicTrack? track;
  final bool playing;
  final int positionMs;
  final int durationMs;

  /// 0..1, null si la source ne le permet pas.
  final double? volume;
  final bool shuffle;
  final PlayerRepeatMode repeat;
  final String? deviceName;

  PlaybackSnapshot copyWith({MusicTrack? track, bool? playing, int? positionMs, int? durationMs, double? volume, bool? shuffle, PlayerRepeatMode? repeat, String? deviceName}) => PlaybackSnapshot(
        track: track ?? this.track,
        playing: playing ?? this.playing,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        volume: volume ?? this.volume,
        shuffle: shuffle ?? this.shuffle,
        repeat: repeat ?? this.repeat,
        deviceName: deviceName ?? this.deviceName,
      );
}

/// Erreur d'une source de musique, avec un message adapté à l'utilisateur.
class MusicException implements Exception {
  const MusicException(this.message, {this.needsLogin = false});
  final String message;
  final bool needsLogin;

  @override
  String toString() => message;
}

String formatMs(int ms) {
  final s = (ms / 1000).floor();
  final m = s ~/ 60;
  return '$m:${(s % 60).toString().padLeft(2, '0')}';
}
