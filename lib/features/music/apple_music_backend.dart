import 'dart:io';

import 'package:flutter/services.dart';
import 'package:strasse/features/music/music_backend.dart';
import 'package:strasse/features/music/music_models.dart';

/// Apple Music via MusicKit (code natif Swift dans AppDelegate). iOS 15+ uniquement, abonnement requis pour la lecture.
/// La lecture est faite par le lecteur système MusicKit : Strasse ne reçoit pas le flux audio.
class AppleMusicBackend implements MusicBackend {
  static const _ch = MethodChannel('fr.strasse.strasse/applemusic');

  bool _connected = false;
  bool _canPlay = false;

  @override
  MusicSource get source => MusicSource.appleMusic;

  /// Pas de réglage du volume : MusicKit utilise le volume du système.
  @override
  MusicCapabilities get capabilities => const MusicCapabilities(
        seek: true,
        shuffle: true,
        repeat: true,
        search: true,
        browse: {CollectionKind.playlist, CollectionKind.album, CollectionKind.artist},
      );

  @override
  Future<bool> isAvailable() async => Platform.isIOS;

  @override
  Future<String?> unavailableReason() async => Platform.isIOS ? null : 'Apple Music (MusicKit) n\'est disponible que sur iOS dans cette version.';

  Future<T> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      final r = await _ch.invokeMethod<T>(method, args);
      return r as T;
    } on PlatformException catch (e) {
      throw MusicException(e.message ?? 'Erreur Apple Music.');
    } on MissingPluginException {
      throw const MusicException('Apple Music n\'est pas disponible dans cette compilation.');
    }
  }

  @override
  Future<bool> connect() async {
    if (!Platform.isIOS) throw MusicException((await unavailableReason())!);
    final status = await _call<String>('authorize');
    if (status != 'authorized') {
      throw const MusicException('Autorisation Apple Music refusée. Activez-la dans Réglages > Confidentialité > Médias et Apple Music.');
    }
    _canPlay = await _call<bool>('canPlay');
    _connected = true;
    return true;
  }

  @override
  bool get connected => _connected;

  bool get canPlay => _canPlay;

  @override
  Future<void> disconnect() async {
    if (_connected) {
      try {
        await _call<bool>('pause');
      } on MusicException {
        // ignoré
      }
    }
    _connected = false;
  }

  MusicTrack? _track(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], title = raw['title'];
    if (id == null || title is! String) return null;
    return MusicTrack(id: 'am$id', title: title, artist: '${raw['artist'] ?? ''}', album: '${raw['album'] ?? ''}', artUrl: raw['art'] as String?, durationMs: (raw['durationMs'] as num?)?.toInt() ?? 0, uri: '$id');
  }

  MusicCollection? _collection(Object? raw, {CollectionKind? kind}) {
    if (raw is! Map) return null;
    final k = kind ?? switch (raw['kind']) { 'artist' => CollectionKind.artist, 'playlist' => CollectionKind.playlist, _ => CollectionKind.album };
    return MusicCollection(id: '${raw['id']}', kind: k, title: '${raw['title']}', subtitle: '${raw['subtitle'] ?? ''}', artUrl: raw['art'] as String?);
  }

  @override
  Future<MusicResults> search(String query) async {
    final r = await _call<Map<Object?, Object?>>('search', {'query': query.trim()});
    return MusicResults(
      tracks: [for (final t in (r['tracks'] as List? ?? const [])) if (_track(t) case final x?) x],
      collections: [for (final c in (r['collections'] as List? ?? const [])) if (_collection(c) case final x?) x],
    );
  }

  /// Éléments de la bibliothèque (le marqueur `library` est mémorisé dans l'identifiant pour la lecture ultérieure).
  final Set<String> _libraryIds = {};

  @override
  Future<List<MusicCollection>> library(CollectionKind kind) async {
    if (kind == CollectionKind.track) return const [];
    final raw = await _call<List<Object?>>('library', {'kind': kind.name});
    final out = [for (final c in raw) if (_collection(c, kind: kind) case final x?) x];
    _libraryIds.addAll(out.map((c) => '${c.kind.name}:${c.id}'));
    return out;
  }

  bool _isLibrary(MusicCollection c) => _libraryIds.contains('${c.kind.name}:${c.id}');

  @override
  Future<List<MusicTrack>> tracksOf(MusicCollection c) async {
    if (c.kind == CollectionKind.artist) return const [];
    final raw = await _call<List<Object?>>('tracks', {'kind': c.kind.name, 'id': c.id, 'library': _isLibrary(c)});
    return [for (final t in raw) if (_track(t) case final x?) x];
  }

  @override
  Future<void> playTrack(MusicTrack t, {List<MusicTrack> queue = const []}) async {
    _requirePlayback();
    await _call<bool>('playSong', {'id': t.id.substring(2)});
  }

  @override
  Future<void> playCollection(MusicCollection c) async {
    _requirePlayback();
    await _call<bool>('playCollection', {'kind': c.kind.name, 'id': c.id, 'library': _isLibrary(c)});
  }

  void _requirePlayback() {
    if (!_canPlay) throw const MusicException('Un abonnement Apple Music actif est nécessaire pour lire de la musique.');
  }

  @override
  Future<PlaybackSnapshot> snapshot() async {
    final m = await _call<Map<Object?, Object?>>('state');
    final title = m['title'];
    return PlaybackSnapshot(
      track: title is String ? MusicTrack(id: 'am${m['id'] ?? ''}', title: title, artist: '${m['artist'] ?? ''}', artUrl: m['art'] as String?, durationMs: (m['durationMs'] as num?)?.toInt() ?? 0) : null,
      playing: m['playing'] == true,
      positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
      shuffle: m['shuffle'] == true,
      repeat: switch (m['repeat']) { 'all' => RepeatMode.all, 'one' => RepeatMode.one, _ => RepeatMode.off },
    );
  }

  @override
  Future<void> play() => _call<bool>('play');
  @override
  Future<void> pause() => _call<bool>('pause');
  @override
  Future<void> next() => _call<bool>('next');
  @override
  Future<void> previous() => _call<bool>('previous');
  @override
  Future<void> seek(int positionMs) => _call<bool>('seek', {'ms': positionMs});
  @override
  Future<void> setVolume(double volume) async => throw const MusicException('Le volume d\'Apple Music se règle avec les boutons de l\'appareil.');
  @override
  Future<void> setShuffle(bool on) => _call<bool>('shuffle', {'on': on});
  @override
  Future<void> setRepeat(RepeatMode mode) => _call<bool>('repeat', {'mode': mode.name});

  @override
  void dispose() {}
}
