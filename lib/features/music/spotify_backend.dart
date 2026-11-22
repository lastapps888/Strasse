import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:strasse/core/storage/secure_store.dart';
import 'package:strasse/features/music/music_backend.dart';
import 'package:strasse/features/music/music_models.dart';
import 'package:url_launcher/url_launcher.dart';

/// PKCE (RFC 7636) : aucune clé secrète n'est nécessaire, seul l'identifiant client public de l'application est utilisé.
class Pkce {
  Pkce._(this.verifier, this.challenge);

  final String verifier;
  final String challenge;

  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  factory Pkce.generate({Random? random, int length = 64}) {
    final r = random ?? Random.secure();
    final v = List.generate(length.clamp(43, 128), (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
    return Pkce._(v, challengeFor(v));
  }

  static String challengeFor(String verifier) => base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
}

/// Spotify : connexion au compte (PKCE) puis commande de l'appareil de lecture actif via l'API Web.
/// Strasse ne lit pas l'audio : l'application Spotify doit être ouverte, et un compte Premium est requis pour les commandes.
class SpotifyBackend implements MusicBackend {
  SpotifyBackend({required this.clientId, required this.secure, this.redirectScheme = 'strasse', Dio? dio, Dio? authDio})
      : _api = dio ?? Dio(BaseOptions(baseUrl: 'https://api.spotify.com/v1', connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 15), validateStatus: (s) => s != null && s < 400)),
        _auth = authDio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 15), contentType: Headers.formUrlEncodedContentType));

  final String clientId;
  final SecureStore secure;
  final String redirectScheme;
  final Dio _api;
  final Dio _auth;

  static const _kAccess = 'spotify.access';
  static const _kRefresh = 'spotify.refresh';
  static const _kExpiry = 'spotify.expiry';
  static const scopes = 'user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private user-library-read user-follow-read';

  String? _access;
  String? _refresh;
  DateTime _expiry = DateTime.fromMillisecondsSinceEpoch(0);
  bool _loaded = false;

  String get redirectUri => '$redirectScheme://spotify-callback';

  @override
  MusicSource get source => MusicSource.spotify;

  @override
  MusicCapabilities get capabilities => const MusicCapabilities(
        seek: true,
        volume: true,
        shuffle: true,
        repeat: true,
        search: true,
        browse: {CollectionKind.playlist, CollectionKind.album, CollectionKind.artist},
      );

  @override
  Future<bool> isAvailable() async => clientId.isNotEmpty;

  @override
  Future<String?> unavailableReason() async => clientId.isEmpty ? 'Spotify n’est pas activé dans cette version : l’éditeur de Strasse doit configurer le Client ID de l’application et respecter les conditions d’accès Spotify.' : null;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    _access = await secure.readRaw(_kAccess);
    _refresh = await secure.readRaw(_kRefresh);
    final e = int.tryParse(await secure.readRaw(_kExpiry) ?? '');
    if (e != null) _expiry = DateTime.fromMillisecondsSinceEpoch(e);
  }

  @override
  bool get connected => _refresh != null || _access != null;

  /// Restaure une session précédente sans interaction.
  Future<bool> restore() async {
    await _load();
    return connected;
  }

  Future<void> _store(Map data) async {
    _access = data['access_token'] as String;
    _refresh = (data['refresh_token'] as String?) ?? _refresh;
    _expiry = DateTime.now().add(Duration(seconds: ((data['expires_in'] as num?) ?? 3600).toInt() - 60));
    await secure.writeRaw(_kAccess, _access);
    await secure.writeRaw(_kRefresh, _refresh);
    await secure.writeRaw(_kExpiry, _expiry.millisecondsSinceEpoch.toString());
  }

  @override
  Future<bool> connect() async {
    if (clientId.isEmpty) throw MusicException((await unavailableReason())!);
    final pkce = Pkce.generate();
    final state = Pkce.generate(length: 24).verifier;
    final url = Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'code_challenge_method': 'S256',
      'code_challenge': pkce.challenge,
      'scope': scopes,
      'state': state,
    });
    String result;
    try {
      result = await FlutterWebAuth2.authenticate(url: url.toString(), callbackUrlScheme: redirectScheme);
    } catch (_) {
      throw const MusicException('Connexion à Spotify annulée ou impossible.');
    }
    final q = Uri.parse(result).queryParameters;
    if (q['error'] != null) throw MusicException('Spotify a refusé la connexion (${q['error']}).');
    if (q['state'] != state || q['code'] == null) throw const MusicException('Réponse de connexion Spotify invalide.');
    try {
      final r = await _auth.post<Map<String, dynamic>>('https://accounts.spotify.com/api/token', data: {
        'grant_type': 'authorization_code',
        'code': q['code'],
        'redirect_uri': redirectUri,
        'client_id': clientId,
        'code_verifier': pkce.verifier,
      });
      await _store(r.data!);
    } on DioException catch (e) {
      throw MusicException(_authError(e));
    }
    return true;
  }

  String _authError(DioException e) {
    final d = e.response?.data;
    if (d is Map && d['error_description'] != null) return 'Spotify : ${d['error_description']}';
    return 'Échange de jeton Spotify impossible (réseau ou identifiant client incorrect).';
  }

  Future<String> _token() async {
    await _load();
    if (_access != null && DateTime.now().isBefore(_expiry)) return _access!;
    final rt = _refresh;
    if (rt == null) throw const MusicException('Connectez-vous à Spotify.', needsLogin: true);
    try {
      final r = await _auth.post<Map<String, dynamic>>('https://accounts.spotify.com/api/token', data: {'grant_type': 'refresh_token', 'refresh_token': rt, 'client_id': clientId});
      await _store(r.data!);
      return _access!;
    } on DioException catch (e) {
      if (e.response?.statusCode == 400 || e.response?.statusCode == 401) {
        await disconnect();
        throw const MusicException('Session Spotify expirée : reconnectez-vous.', needsLogin: true);
      }
      throw const MusicException('Spotify est injoignable.');
    }
  }

  @override
  Future<void> disconnect() async {
    _access = null;
    _refresh = null;
    _expiry = DateTime.fromMillisecondsSinceEpoch(0);
    await secure.writeRaw(_kAccess, null);
    await secure.writeRaw(_kRefresh, null);
    await secure.writeRaw(_kExpiry, null);
  }

  /// Ouvre l'application Spotify (schéma `spotify:`) pour qu'un appareil de lecture soit actif.
  Future<bool> openApp() async {
    try {
      return await launchUrl(Uri.parse('spotify:'), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<Response<dynamic>> _call(String method, String path, {Map<String, dynamic>? query, Object? body}) async {
    try {
      return await _api.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method, headers: {'Authorization': 'Bearer ${await _token()}'}),
      );
    } on DioException catch (e) {
      throw _apiError(e);
    }
  }

  MusicException _apiError(DioException e) {
    final status = e.response?.statusCode;
    final d = e.response?.data;
    final err = d is Map ? d['error'] : null;
    final reason = err is Map ? '${err['reason'] ?? ''}' : '';
    final message = err is Map ? '${err['message'] ?? ''}' : '';
    if (status == 401) return const MusicException('Session Spotify expirée : reconnectez-vous.', needsLogin: true);
    if (status == 403 && reason == 'PREMIUM_REQUIRED') return const MusicException('Un compte Spotify Premium est nécessaire pour commander la lecture.');
    if (status == 403) {
      return MusicException(message.isEmpty
          ? 'Action refusée par Spotify (application en mode développement : votre compte doit être ajouté aux utilisateurs autorisés).'
          : 'Spotify : $message');
    }
    if (status == 404 && reason == 'NO_ACTIVE_DEVICE') return const MusicException('Aucun appareil Spotify actif. Ouvrez l\'application Spotify, lancez un titre, puis réessayez.');
    if (status == 404) return const MusicException('Élément introuvable sur Spotify.');
    if (status == 429) return const MusicException('Spotify limite les requêtes : réessayez dans un instant.');
    if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) return const MusicException('Spotify est injoignable (réseau).');
    return MusicException(message.isEmpty ? 'Erreur Spotify (${status ?? 'réseau'}).' : 'Spotify : $message');
  }

  /// Exécute une commande de lecture ; sans appareil actif, tente l'unique appareil disponible.
  Future<void> _command(String method, String path, {Map<String, dynamic>? query, Object? body}) async {
    try {
      await _call(method, path, query: query, body: body);
    } on MusicException catch (e) {
      if (!e.message.contains('Aucun appareil Spotify actif')) rethrow;
      final id = await _singleDevice();
      if (id == null) rethrow;
      await _call(method, path, query: {...?query, 'device_id': id}, body: body);
    }
  }

  Future<String?> _singleDevice() async {
    final r = await _call('GET', '/me/player/devices');
    final list = ((r.data as Map?)?['devices'] as List?) ?? const [];
    final usable = [for (final d in list) if (d is Map && d['is_restricted'] != true) d];
    return usable.length == 1 ? usable.first['id'] as String? : null;
  }

  // ------------------------------------------------------------- Lecture

  MusicTrack? _track(Object? raw, {String? album, String? art}) {
    if (raw is! Map || raw['id'] == null) return null;
    final alb = raw['album'] is Map ? raw['album'] as Map : const {};
    final images = (alb['images'] as List?) ?? const [];
    return MusicTrack(
      id: 'sp${raw['id']}',
      title: '${raw['name']}',
      artist: [for (final a in (raw['artists'] as List?) ?? const []) if (a is Map) '${a['name']}'].join(', '),
      album: album ?? '${alb['name'] ?? ''}',
      artUrl: art ?? (images.isNotEmpty && images.first is Map ? (images.length > 1 ? (images[1] as Map)['url'] : (images.first as Map)['url']) as String? : null),
      durationMs: (raw['duration_ms'] as num?)?.toInt() ?? 0,
      uri: raw['uri'] as String?,
    );
  }

  @override
  Future<PlaybackSnapshot> snapshot() async {
    final r = await _call('GET', '/me/player');
    if (r.statusCode == 204 || r.data is! Map) return PlaybackSnapshot.idle;
    final m = r.data as Map;
    final dev = m['device'] is Map ? m['device'] as Map : const {};
    final item = _track(m['item']);
    return PlaybackSnapshot(
      track: item,
      playing: m['is_playing'] == true,
      positionMs: (m['progress_ms'] as num?)?.toInt() ?? 0,
      durationMs: item?.durationMs ?? 0,
      volume: dev['volume_percent'] is num ? (dev['volume_percent'] as num) / 100 : null,
      shuffle: m['shuffle_state'] == true,
      repeat: switch (m['repeat_state']) { 'context' => PlayerRepeatMode.all, 'track' => PlayerRepeatMode.one, _ => PlayerRepeatMode.off },
      deviceName: dev['name'] as String?,
    );
  }

  @override
  Future<void> play() => _command('PUT', '/me/player/play');
  @override
  Future<void> pause() => _command('PUT', '/me/player/pause');
  @override
  Future<void> next() => _command('POST', '/me/player/next');
  @override
  Future<void> previous() => _command('POST', '/me/player/previous');
  @override
  Future<void> seek(int positionMs) => _command('PUT', '/me/player/seek', query: {'position_ms': positionMs});
  @override
  Future<void> setVolume(double volume) => _command('PUT', '/me/player/volume', query: {'volume_percent': (volume.clamp(0.0, 1.0) * 100).round()});
  @override
  Future<void> setShuffle(bool on) => _command('PUT', '/me/player/shuffle', query: {'state': on});
  @override
  Future<void> setRepeat(PlayerRepeatMode mode) => _command('PUT', '/me/player/repeat', query: {'state': switch (mode) { PlayerRepeatMode.off => 'off', PlayerRepeatMode.all => 'context', PlayerRepeatMode.one => 'track' }});

  @override
  Future<void> playTrack(MusicTrack t, {List<MusicTrack> queue = const []}) {
    final uris = [for (final x in queue) if (x.uri != null) x.uri!];
    if (uris.length > 1 && uris.length <= 100 && t.uri != null) {
      return _command('PUT', '/me/player/play', body: {'uris': uris, 'offset': {'uri': t.uri}});
    }
    if (t.uri == null) throw const MusicException('Titre non lisible.');
    return _command('PUT', '/me/player/play', body: {'uris': [t.uri]});
  }

  @override
  Future<void> playCollection(MusicCollection c) {
    final uri = c.uri ?? 'spotify:${c.kind.name}:${c.id}';
    return _command('PUT', '/me/player/play', body: {'context_uri': uri});
  }

  // ------------------------------------------------------ Recherche et bibliothèque

  @override
  Future<MusicResults> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const MusicResults();
    final r = await _call('GET', '/search', query: {'q': q, 'type': 'track,album,artist', 'limit': 10});
    final d = r.data as Map;
    List<Object?> items(String k) => ((d[k] as Map?)?['items'] as List?)?.cast<Object?>() ?? const [];
    return MusicResults(
      tracks: [for (final t in items('tracks')) if (_track(t) case final x?) x],
      collections: [
        for (final a in items('albums')) if (_album(a) case final x?) x,
        for (final a in items('artists')) if (_artist(a) case final x?) x,
      ],
    );
  }

  String? _image(Object? images) {
    if (images is List && images.isNotEmpty && images.first is Map) {
      return ((images.length > 1 ? images[1] : images.first) as Map)['url'] as String?;
    }
    return null;
  }

  MusicCollection? _album(Object? a) {
    if (a is! Map || a['id'] == null) return null;
    return MusicCollection(
      id: '${a['id']}',
      kind: CollectionKind.album,
      title: '${a['name']}',
      subtitle: [for (final x in (a['artists'] as List?) ?? const []) if (x is Map) '${x['name']}'].join(', '),
      artUrl: _image(a['images']),
      uri: a['uri'] as String?,
    );
  }

  MusicCollection? _artist(Object? a) {
    if (a is! Map || a['id'] == null) return null;
    return MusicCollection(id: '${a['id']}', kind: CollectionKind.artist, title: '${a['name']}', artUrl: _image(a['images']), uri: a['uri'] as String?);
  }

  @override
  Future<List<MusicCollection>> library(CollectionKind kind) async {
    switch (kind) {
      case CollectionKind.playlist:
        final r = await _call('GET', '/me/playlists', query: {'limit': 50});
        return [
          for (final p in ((r.data as Map)['items'] as List?) ?? const [])
            if (p is Map && p['id'] != null)
              MusicCollection(id: '${p['id']}', kind: kind, title: '${p['name']}', subtitle: p['owner'] is Map ? '${(p['owner'] as Map)['display_name'] ?? ''}' : '', artUrl: _image(p['images']), uri: p['uri'] as String?),
        ];
      case CollectionKind.album:
        final r = await _call('GET', '/me/albums', query: {'limit': 50});
        return [
          for (final i in ((r.data as Map)['items'] as List?) ?? const [])
            if (i is Map)
              if (_album(i['album']) case final x?) x,
        ];
      case CollectionKind.artist:
        final r = await _call('GET', '/me/following', query: {'type': 'artist', 'limit': 50});
        return [for (final a in (((r.data as Map)['artists'] as Map?)?['items'] as List?) ?? const []) if (_artist(a) case final x?) x];
      case CollectionKind.track:
        return const [];
    }
  }

  @override
  Future<List<MusicTrack>> tracksOf(MusicCollection c) async {
    switch (c.kind) {
      case CollectionKind.playlist:
        // Depuis février 2026, `/tracks` est devenu `/items` (et l'élément s'appelle `item`) ; en mode développement,
        // seules les playlists dont l'utilisateur est propriétaire ou collaborateur renvoient leur contenu.
        try {
          final r = await _call('GET', '/playlists/${c.id}/items', query: {'limit': 100});
          return [
            for (final i in ((r.data as Map)['items'] as List?) ?? const [])
              if (i is Map)
                if (_track(i['item'] ?? i['track']) case final x?) x,
          ];
        } on MusicException catch (e) {
          if (e.needsLogin) rethrow;
          throw MusicException('Spotify ne donne pas accès au contenu de cette playlist (réservé aux playlists que vous possédez ou partagez). Vous pouvez tout de même la lancer.');
        }
      case CollectionKind.album:
        final r = await _call('GET', '/albums/${c.id}/tracks', query: {'limit': 50});
        return [for (final t in ((r.data as Map)['items'] as List?) ?? const []) if (_track(t, album: c.title, art: c.artUrl) case final x?) x];
      case CollectionKind.artist:
      case CollectionKind.track:
        return const [];
    }
  }

  @override
  void dispose() {}
}
