import 'package:dio/dio.dart';
import 'package:strasse/features/music/audio_engine.dart';
import 'package:strasse/features/music/music_backend.dart';
import 'package:strasse/features/music/music_models.dart';

/// Deezer, API publique sans authentification : recherche, classements et extraits de 30 secondes.
/// Pas de compte ni de lecture complète (Deezer n'ouvre plus ces droits à de nouvelles applications).
class DeezerBackend implements MusicBackend {
  DeezerBackend({required String baseUrl, required this.engine, Dio? dio, String userAgent = ''})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl.replaceAll(RegExp(r'/+$'), ''),
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 15),
              headers: {if (userAgent.isNotEmpty) 'User-Agent': userAgent},
            ));

  final Dio _dio;
  final AudioEngine engine;
  bool _connected = false;

  @override
  MusicSource get source => MusicSource.deezer;

  @override
  MusicCapabilities get capabilities => const MusicCapabilities(
        seek: true,
        volume: true,
        shuffle: true,
        repeat: true,
        search: true,
        browse: {CollectionKind.track, CollectionKind.album, CollectionKind.artist, CollectionKind.playlist},
      );

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> unavailableReason() async => null;

  /// Aucune authentification : « se connecter » vérifie seulement que l'API répond.
  @override
  Future<bool> connect() async {
    try {
      await _get('/chart/0/tracks', {'limit': 1});
      _connected = true;
    } on MusicException {
      _connected = false;
      rethrow;
    }
    return _connected;
  }

  @override
  bool get connected => _connected;

  @override
  Future<void> disconnect() async {
    await engine.stop();
    _connected = false;
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, dynamic>? q]) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(path, queryParameters: q);
      final d = r.data ?? const {};
      if (d['error'] is Map) {
        throw MusicException('Deezer a refusé la demande : ${(d['error'] as Map)['message'] ?? 'erreur inconnue'}.');
      }
      return d;
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) throw const MusicException('Deezer limite le nombre de requêtes : réessayez dans un instant.');
      throw const MusicException('Deezer est injoignable (réseau ou service indisponible).');
    }
  }

  MusicTrack? _track(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    if (id == null || title is! String) return null;
    final album = raw['album'] is Map ? raw['album'] as Map : const {};
    final preview = raw['preview'];
    return MusicTrack(
      id: 'dz$id',
      title: title,
      artist: raw['artist'] is Map ? '${(raw['artist'] as Map)['name'] ?? ''}' : '',
      album: '${album['title'] ?? ''}',
      artUrl: (album['cover_medium'] ?? album['cover']) as String?,
      durationMs: ((raw['duration'] as num?) ?? 0).toInt() * 1000,
      uri: preview is String && preview.isNotEmpty ? preview : null,
      previewOnly: true,
    );
  }

  List<MusicTrack> _tracks(Object? data, {String? album, String? art}) {
    final out = <MusicTrack>[];
    for (final e in (data as List?) ?? const []) {
      final t = _track(e);
      if (t == null) continue;
      out.add(album == null ? t : MusicTrack(id: t.id, title: t.title, artist: t.artist, album: album, artUrl: t.artUrl ?? art, durationMs: t.durationMs, uri: t.uri, previewOnly: true));
    }
    return out;
  }

  @override
  Future<MusicResults> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const MusicResults();
    final res = await Future.wait([_get('/search', {'q': q, 'limit': 25}), _get('/search/album', {'q': q, 'limit': 10}), _get('/search/artist', {'q': q, 'limit': 10})]);
    return MusicResults(
      tracks: _tracks(res[0]['data']),
      collections: [
        for (final a in (res[1]['data'] as List?) ?? const [])
          if (a is Map) MusicCollection(id: '${a['id']}', kind: CollectionKind.album, title: '${a['title']}', subtitle: a['artist'] is Map ? '${(a['artist'] as Map)['name']}' : '', artUrl: a['cover_medium'] as String?),
        for (final a in (res[2]['data'] as List?) ?? const [])
          if (a is Map) MusicCollection(id: '${a['id']}', kind: CollectionKind.artist, title: '${a['name']}', artUrl: a['picture_medium'] as String?),
      ],
    );
  }

  /// Classements publics de Deezer (pas de bibliothèque personnelle sans compte).
  @override
  Future<List<MusicCollection>> library(CollectionKind kind) async {
    switch (kind) {
      case CollectionKind.album:
        final d = await _get('/chart/0/albums', {'limit': 30});
        return [for (final a in (d['data'] as List?) ?? const []) if (a is Map) MusicCollection(id: '${a['id']}', kind: kind, title: '${a['title']}', subtitle: a['artist'] is Map ? '${(a['artist'] as Map)['name']}' : '', artUrl: a['cover_medium'] as String?)];
      case CollectionKind.artist:
        final d = await _get('/chart/0/artists', {'limit': 30});
        return [for (final a in (d['data'] as List?) ?? const []) if (a is Map) MusicCollection(id: '${a['id']}', kind: kind, title: '${a['name']}', artUrl: a['picture_medium'] as String?)];
      case CollectionKind.playlist:
        final d = await _get('/chart/0/playlists', {'limit': 30});
        return [for (final a in (d['data'] as List?) ?? const []) if (a is Map) MusicCollection(id: '${a['id']}', kind: kind, title: '${a['title']}', subtitle: 'Classement Deezer', artUrl: a['picture_medium'] as String?)];
      case CollectionKind.track:
        return const [];
    }
  }

  @override
  Future<List<MusicTrack>> tracksOf(MusicCollection c) async {
    switch (c.kind) {
      case CollectionKind.album:
        final d = await _get('/album/${c.id}/tracks', {'limit': 100});
        return _tracks(d['data'], album: c.title, art: c.artUrl);
      case CollectionKind.artist:
        final d = await _get('/artist/${c.id}/top', {'limit': 30});
        return _tracks(d['data']);
      case CollectionKind.playlist:
        final d = await _get('/playlist/${c.id}/tracks', {'limit': 100});
        return _tracks(d['data']);
      case CollectionKind.track:
        return const [];
    }
  }

  Future<List<MusicTrack>> chartTracks() async => _tracks((await _get('/chart/0/tracks', {'limit': 30}))['data']);

  @override
  Future<void> playTrack(MusicTrack t, {List<MusicTrack> queue = const []}) {
    final list = queue.isEmpty ? [t] : queue;
    final i = list.indexWhere((x) => x.id == t.id);
    return engine.playQueue(list, i < 0 ? 0 : i);
  }

  @override
  Future<void> playCollection(MusicCollection c) async {
    final tracks = await tracksOf(c);
    if (tracks.isEmpty) throw const MusicException('Cette sélection ne contient aucun extrait lisible.');
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
  Future<void> setRepeat(RepeatMode mode) => engine.setRepeat(mode);

  @override
  void dispose() {}
}
