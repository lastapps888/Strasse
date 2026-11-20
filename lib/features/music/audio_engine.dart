import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:strasse/features/music/music_models.dart';

/// Lecteur audio interne (just_audio) utilisé par les sources dont l'audio est lu par Strasse : Deezer (extraits) et musique locale.
/// just_audio_background affiche les commandes dans la notification / l'écran verrouillé et garde la lecture en arrière-plan.
class AudioEngine {
  AudioEngine() : _player = AudioPlayer();

  final AudioPlayer _player;
  List<MusicTrack> _queue = const [];

  AudioPlayer get player => _player;

  bool get hasQueue => _queue.isNotEmpty;

  Future<void> playQueue(List<MusicTrack> tracks, int index) async {
    final playable = <MusicTrack>[for (final t in tracks) if (t.uri != null) t];
    if (playable.isEmpty) throw const MusicException('Aucun titre lisible dans cette sélection.');
    final start = tracks[index].uri == null ? 0 : playable.indexWhere((t) => t.id == tracks[index].id).clamp(0, playable.length - 1);
    _queue = playable;
    try {
      final sources = [
        for (final t in playable)
          AudioSource.uri(
            Uri.parse(t.uri!),
            tag: MediaItem(
              id: t.id,
              title: t.title,
              artist: t.artist.isEmpty ? null : t.artist,
              album: t.album.isEmpty ? null : t.album,
              artUri: t.artUrl == null ? null : Uri.tryParse(t.artUrl!),
              duration: t.durationMs > 0 ? Duration(milliseconds: t.durationMs) : null,
            ),
          ),
      ];
      await _player.setAudioSource(ConcatenatingAudioSource(children: sources), initialIndex: start);
      unawaited(_player.play());
    } on PlayerException catch (e) {
      throw MusicException('Lecture impossible : ${e.message ?? 'format non pris en charge'}.');
    } on PlayerInterruptedException {
      // Une nouvelle lecture a remplacé celle-ci : rien à signaler.
    }
  }

  PlaybackSnapshot snapshot({PlayerRepeatMode? repeat}) {
    final i = _player.currentIndex;
    final track = (i != null && i >= 0 && i < _queue.length) ? _queue[i] : null;
    return PlaybackSnapshot(
      track: track,
      playing: _player.playing,
      positionMs: _player.position.inMilliseconds,
      durationMs: _player.duration?.inMilliseconds ?? track?.durationMs ?? 0,
      volume: _player.volume,
      shuffle: _player.shuffleModeEnabled,
      repeat: switch (_player.loopMode) {
        LoopMode.off => PlayerRepeatMode.off,
        LoopMode.all => PlayerRepeatMode.all,
        LoopMode.one => PlayerRepeatMode.one,
      },
    );
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> next() => _player.seekToNext();
  Future<void> previous() async {
    // Comme la plupart des lecteurs : au-delà de 3 s, « précédent » recommence le titre.
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  Future<void> seek(int ms) => _player.seek(Duration(milliseconds: ms));
  Future<void> setVolume(double v) => _player.setVolume(v.clamp(0.0, 1.0));
  Future<void> setShuffle(bool on) async {
    if (on) await _player.shuffle();
    await _player.setShuffleModeEnabled(on);
  }

  Future<void> setRepeat(PlayerRepeatMode m) => _player.setLoopMode(switch (m) {
        PlayerRepeatMode.off => LoopMode.off,
        PlayerRepeatMode.all => LoopMode.all,
        PlayerRepeatMode.one => LoopMode.one,
      });

  Future<void> stop() async {
    await _player.stop();
    _queue = const [];
  }

  Future<void> dispose() => _player.dispose();
}
