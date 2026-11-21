import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:strasse/features/music/audio_engine.dart';
import 'package:strasse/features/music/music_backend.dart';
import 'package:strasse/features/music/music_models.dart';

/// Musique de l'appareil : MediaStore (Android), bibliothèque Musique (iOS) et fichiers choisis avec le sélecteur.
/// Rien n'est envoyé hors de l'appareil.
class LocalMusicBackend implements MusicBackend {
  LocalMusicBackend({required this.engine});

  static const _channel = MethodChannel('fr.strasse.strasse/music');
  final AudioEngine engine;

  bool _connected = false;
  List<MusicTrack> _device = const [];
  final List<MusicTrack> _picked = [];

  @override
  MusicSource get source => MusicSource.local;

  @override
  MusicCapabilities get capabilities => MusicCapabilities(
        seek: true,
        volume: true,
        shuffle: true,
        repeat: true,
        search: true,
        browse: {CollectionKind.track, CollectionKind.album, CollectionKind.artist, if (Platform.isIOS) CollectionKind.playlist},
      );

  @override
  Future<bool> isAvailable() async => Platform.isAndroid || Platform.isIOS;

  @override
  Future<String?> unavailableReason() async => (Platform.isAndroid || Platform.isIOS) ? null : 'Plateforme non prise en charge.';

  Future<bool> _permission() async {
    if (Platform.isIOS) return (await Permission.mediaLibrary.request()).isGranted;
    // Android 13+ : READ_MEDIA_AUDIO ; avant : READ_EXTERNAL_STORAGE.
    if ((await Permission.audio.request()).isGranted) return true;
    return (await Permission.storage.request()).isGranted;
  }

  @override
  Future<bool> connect() async {
    if (!await _permission()) {
      throw const MusicException('Autorisez l\'accès à la musique dans les réglages du système pour lister les titres. Vous pouvez aussi choisir des fichiers.');
    }
    await refresh();
    _connected = true;
    return true;
  }

  @override
  bool get connected => _connected;

  Future<void> refresh() async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('listTracks') ?? const [];
      _device = [for (final m in raw) if (_parse(m) case final t?) t];
    } on PlatformException catch (e) {
      throw MusicException(e.message ?? 'Lecture de la bibliothèque impossible.');
    } on MissingPluginException {
      throw const MusicException('Bibliothèque musicale indisponible sur cette plateforme.');
    }
  }

  MusicTrack? _parse(Map<Object?, Object?> m) {
    final id = m['id'], title = m['title'], uri = m['uri'];
    if (id == null || title is! String || uri is! String) return null;
    return MusicTrack(
      id: 'loc$id',
      title: title.isEmpty ? 'Sans titre' : title,
      artist: '${m['artist'] ?? ''}',
      album: '${m['album'] ?? ''}',
      durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
      uri: uri,
    );
  }

  List<MusicTrack> get _all => [..._picked, ..._device];

  /// Ajoute des fichiers audio choisis par l'utilisateur. Sur Android, le sélecteur copie les fichiers dans le cache de
  /// l'application : ils sont oubliés au redémarrage (la bibliothèque de l'appareil, elle, est conservée).
  Future<int> pickFiles() async {
    final files = await FilePicker.pickFiles(type: FileType.audio);
    if (files.isEmpty) return 0;
    var n = 0;
    for (final f in files) {
      final path = f.path;
      if (path == null) continue;
      final name = f.name.replaceFirst(RegExp(r'\.[A-Za-z0-9]{2,5}$'), '');
      _picked.add(MusicTrack(id: 'file${path.hashCode}', title: name, artist: 'Fichier', uri: Uri.file(path).toString()));
      n++;
    }
    _connected = true;
    return n;
  }

  @override
  Future<void> disconnect() async {
    await engine.stop();
    _connected = false;
  }

  @override
  Future<MusicResults> search(String query) async {
    final q = _fold(query.trim());
    if (q.isEmpty) return const MusicResults();
    return MusicResults(tracks: [for (final t in _all) if (_fold('${t.title} ${t.artist} ${t.album}').contains(q)) t].take(60).toList());
  }

  static String _fold(String s) => s.toLowerCase().replaceAll(RegExp('[àâä]'), 'a').replaceAll(RegExp('[éèêë]'), 'e').replaceAll(RegExp('[îï]'), 'i').replaceAll(RegExp('[ôö]'), 'o').replaceAll(RegExp('[ùûü]'), 'u').replaceAll('ç', 'c');

  @override
  Future<List<MusicCollection>> library(CollectionKind kind) async {
    switch (kind) {
      case CollectionKind.album:
        final byAlbum = <String, List<MusicTrack>>{};
        for (final t in _all) {
          if (t.album.isEmpty) continue;
          byAlbum.putIfAbsent('${t.album}|${t.artist}', () => []).add(t);
        }
        return [for (final e in byAlbum.entries) MusicCollection(id: 'album:${e.key}', kind: kind, title: e.value.first.album, subtitle: '${e.value.first.artist} · ${e.value.length} titre(s)')]
          ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case CollectionKind.artist:
        final byArtist = <String, int>{};
        for (final t in _all) {
          if (t.artist.isEmpty) continue;
          byArtist[t.artist] = (byArtist[t.artist] ?? 0) + 1;
        }
        return [for (final e in byArtist.entries) MusicCollection(id: 'artist:${e.key}', kind: kind, title: e.key, subtitle: '${e.value} titre(s)')]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case CollectionKind.playlist:
        if (!Platform.isIOS) return const [];
        try {
          final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('listPlaylists') ?? const [];
          return [for (final m in raw) MusicCollection(id: 'playlist:${m['id']}', kind: kind, title: '${m['title']}', subtitle: '${m['count'] ?? 0} titre(s)')];
        } on PlatformException catch (e) {
          throw MusicException(e.message ?? 'Playlists indisponibles.');
        }
      case CollectionKind.track:
        return const [];
    }
  }

  /// Tous les titres (onglet « Titres »).
  List<MusicTrack> allTracks() => _all;

  @override
  Future<List<MusicTrack>> tracksOf(MusicCollection c) async {
    if (c.id.startsWith('album:')) {
      final key = c.id.substring(6);
      return [for (final t in _all) if ('${t.album}|${t.artist}' == key) t];
    }
    if (c.id.startsWith('artist:')) {
      final a = c.id.substring(7);
      return [for (final t in _all) if (t.artist == a) t];
    }
    if (c.id.startsWith('playlist:')) {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('playlistTracks', {'id': c.id.substring(9)}) ?? const [];
      return [for (final m in raw) if (_parse(m) case final t?) t];
    }
    return const [];
  }

  @override
  Future<void> playTrack(MusicTrack t, {List<MusicTrack> queue = const []}) {
    final list = queue.isEmpty ? [t] : queue;
    final i = list.indexWhere((x) => x.id == t.id);
    return engine.playQueue(list, i < 0 ? 0 : i);
  }

  @override
  Future<void> playCollection(MusicCollection c) async {
    final tracks = await tracksOf(c);
    if (tracks.isEmpty) throw const MusicException('Aucun titre lisible dans cette sélection.');
    await engine.playQueue(tracks, 0);
  }

  @override
  Future<PlaybackSnapshot> snapshot() async => engine.snapshot();
  @override
  Future<void> play() => engine.play();
  @override
  Future<void> pause() => engine.pause();
  @override
  Future<void> next() => engine.next();
  @override
  Future<void> previous() => engine.previous();
  @override
  Future<void> seek(int positionMs) => engine.seek(positionMs);
  @override
  Future<void> setVolume(double volume) => engine.setVolume(volume);
  @override
  Future<void> setShuffle(bool on) => engine.setShuffle(on);
  @override
  Future<void> setRepeat(PlayerRepeatMode mode) => engine.setRepeat(mode);

  @override
  void dispose() {}
}
