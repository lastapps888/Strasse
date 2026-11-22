import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static const String _pickedLibraryKey = 'strasse.music.imported_files.v1';
  bool _pickedLoaded = false;
  Future<void>? _pickedLoadFuture;

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
    await _ensurePickedLoaded();
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

  Future<void> _ensurePickedLoaded() {
    if (_pickedLoaded) return Future<void>.value();
    return _pickedLoadFuture ??= _restorePicked().then((_) {
      _pickedLoaded = true;
    }).whenComplete(() {
      _pickedLoadFuture = null;
    });
  }

  Future<Directory> _importDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'Strasse', 'Music', 'Imports'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _artworkDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'Strasse', 'Music', 'Artwork'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Map<Object?, Object?>> _readFileMetadata(String path) async {
    try {
      return await _channel.invokeMapMethod<Object?, Object?>('metadataForFile', {'path': path}) ?? const {};
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

  Future<String?> _saveArtwork(Object? value, String fileId) async {
    if (value is! Uint8List || value.isEmpty) return null;
    try {
      final directory = await _artworkDirectory();
      final file = File(p.join(directory.path, fileId + '.jpg'));
      await file.writeAsBytes(value, flush: true);
      return Uri.file(file.path).toString();
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _restorePicked() async {
    final preferences = await SharedPreferences.getInstance();
    final serialized = preferences.getStringList(_pickedLibraryKey) ?? const <String>[];
    final restored = <MusicTrack>[];
    var staleEntryFound = false;
    for (final entry in serialized) {
      try {
        final decoded = jsonDecode(entry);
        if (decoded is! Map<String, dynamic>) {
          staleEntryFound = true;
          continue;
        }
        final path = decoded['path'];
        final id = decoded['id'];
        final title = decoded['title'];
        if (path is! String || id is! String || title is! String || !await File(path).exists()) {
          staleEntryFound = true;
          continue;
        }
        restored.add(MusicTrack(
          id: id,
          title: title,
          artist: decoded['artist'] is String ? decoded['artist'] as String : 'Fichier',
          album: decoded['album'] is String ? decoded['album'] as String : '',
          durationMs: decoded['durationMs'] is num ? (decoded['durationMs'] as num).toInt() : 0,
          artUrl: decoded['artUrl'] is String && await File.fromUri(Uri.parse(decoded['artUrl'] as String)).exists() ? decoded['artUrl'] as String : null,
          uri: Uri.file(path).toString(),
        ));
      } catch (_) {
        staleEntryFound = true;
      }
    }
    _picked
      ..clear()
      ..addAll(restored);
    if (staleEntryFound) await _savePicked();
  }

  Future<void> _savePicked() async {
    final preferences = await SharedPreferences.getInstance();
    final entries = <String>[];
    for (final track in _picked) {
      final uri = Uri.tryParse(track.uri ?? '');
      if (uri == null || uri.scheme != 'file') continue;
      entries.add(jsonEncode({
        'id': track.id,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'durationMs': track.durationMs,
        if (track.artUrl != null) 'artUrl': track.artUrl,
        'path': uri.toFilePath(),
      }));
    }
    final saved = await preferences.setStringList(_pickedLibraryKey, entries);
    if (!saved) throw const MusicException('Impossible d’enregistrer la bibliothèque musicale importée.');
  }


  /// Copie chaque fichier sélectionné dans le répertoire persistant de l'application et mémorise ses métadonnées.
  /// Les fichiers importés restent disponibles après fermeture de Strasse et redémarrage du téléphone.
  Future<int> pickFiles() async {
    await _ensurePickedLoaded();
    final files = await FilePicker.pickFiles(type: FileType.audio);
    if (files.isEmpty) return 0;
    final directory = await _importDirectory();
    final imported = <MusicTrack>[];
    final copiedFiles = <File>[];
    final artworkFiles = <File>[];
    final stamp = DateTime.now().microsecondsSinceEpoch;
    var index = 0;

    for (final selected in files) {
      final sourcePath = selected.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        index++;
        continue;
      }

      final source = File(sourcePath);
      if (!await source.exists()) {
        index++;
        continue;
      }

      final originalName = p.basename(selected.name);
      final safeName = originalName.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
      final id = 'file' + stamp.toString() + '_' + index.toString();
      final destinationPath = p.join(directory.path, stamp.toString() + '_' + index.toString() + '_' + safeName);

      try {
        final copied = await source.copy(destinationPath);
        copiedFiles.add(copied);
        final metadata = await _readFileMetadata(copied.path);
        final rawTitle = metadata['title'];
        final rawArtist = metadata['artist'];
        final rawAlbum = metadata['album'];
        final rawDuration = metadata['durationMs'];
        final title = rawTitle is String && rawTitle.trim().isNotEmpty
            ? rawTitle.trim()
            : p.basenameWithoutExtension(originalName).trim();
        final artUrl = await _saveArtwork(metadata['artwork'], id);
        if (artUrl != null) artworkFiles.add(File.fromUri(Uri.parse(artUrl)));

        imported.add(MusicTrack(
          id: id,
          title: title.isEmpty ? 'Fichier audio' : title,
          artist: rawArtist is String && rawArtist.trim().isNotEmpty ? rawArtist.trim() : 'Fichier',
          album: rawAlbum is String ? rawAlbum.trim() : '',
          durationMs: rawDuration is num ? rawDuration.toInt() : 0,
          artUrl: artUrl,
          uri: Uri.file(copied.path).toString(),
        ));
      } on FileSystemException {
        // Un fichier inaccessible ne doit pas empêcher l'importation des autres.
      } on PlatformException {
        // Une erreur d'extraction de métadonnées ne doit pas empêcher l'importation du fichier.
      }
      index++;
    }


    if (imported.isEmpty) {
      throw const MusicException('Aucun des fichiers sélectionnés n’a pu être copié dans la bibliothèque Strasse.');
    }
    final previous = List<MusicTrack>.of(_picked);
    _picked.addAll(imported);
    try {
      await _savePicked();
    } catch (_) {
      _picked
        ..clear()
        ..addAll(previous);
      for (final file in copiedFiles) {
        try {
          await file.delete();
        } on FileSystemException {
          // Le nettoyage ne doit pas masquer l'erreur de sauvegarde.
        }
      }
      for (final file in artworkFiles) {
        try {
          await file.delete();
        } on FileSystemException {
          // Le nettoyage ne doit pas masquer l'erreur de sauvegarde.
        }
      }
      rethrow;
    }
    _connected = true;
    return imported.length;
  }

  @override
  Future<void> disconnect() async {
    await engine.stop();
    _connected = false;
  }

  @override
  Future<MusicResults> search(String query) async {
    await _ensurePickedLoaded();
    final q = _fold(query.trim());
    if (q.isEmpty) return const MusicResults();
    return MusicResults(tracks: [for (final t in _all) if (_fold('${t.title} ${t.artist} ${t.album}').contains(q)) t].take(60).toList());
  }

  static String _fold(String s) => s.toLowerCase().replaceAll(RegExp('[àâä]'), 'a').replaceAll(RegExp('[éèêë]'), 'e').replaceAll(RegExp('[îï]'), 'i').replaceAll(RegExp('[ôö]'), 'o').replaceAll(RegExp('[ùûü]'), 'u').replaceAll('ç', 'c');

  @override
  Future<List<MusicCollection>> library(CollectionKind kind) async {
    await _ensurePickedLoaded();
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
  Future<List<MusicTrack>> allTracks() async {
    await _ensurePickedLoaded();
    return _all;
  }

  @override
  Future<List<MusicTrack>> tracksOf(MusicCollection c) async {
    await _ensurePickedLoaded();
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
