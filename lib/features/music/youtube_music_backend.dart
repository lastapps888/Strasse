import 'dart:io';

import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:strasse/features/music/music_backend.dart';
import 'package:strasse/features/music/music_models.dart';
import 'package:url_launcher/url_launcher.dart';

/// YouTube Music : connexion Google OAuth, playlists privées et recherche vidéo musicale.
/// YouTube Data API ne livre pas le flux audio à Strasse : les sélections sont ouvertes dans
/// l'application YouTube Music ou dans le navigateur, conformément aux règles de l'API.
class YouTubeMusicBackend implements MusicBackend {
  YouTubeMusicBackend({
    required this.iosClientId,
    required this.serverClientId,
    GoogleSignIn? signIn,
    Dio? dio,
  })  : _signIn = signIn ?? GoogleSignIn.instance,
        _api = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://www.googleapis.com/youtube/v3',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              validateStatus: (status) => status != null && status < 400,
              headers: const {'Accept': 'application/json'},
            ));

  final String iosClientId;
  final String serverClientId;
  final GoogleSignIn _signIn;
  final Dio _api;

  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/youtube.readonly',
  ];

  GoogleSignInAccount? _account;
  static Future<void>? _globalInitialization;
  bool _connected = false;

  @override
  MusicSource get source => MusicSource.youtubeMusic;

  @override
  MusicCapabilities get capabilities => const MusicCapabilities(
        playPause: false,
        skip: false,
        seek: false,
        volume: false,
        shuffle: false,
        repeat: false,
        search: true,
        browse: {CollectionKind.playlist, CollectionKind.track},
      );

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    if (Platform.isIOS && iosClientId.trim().isEmpty) return false;
    return serverClientId.trim().isNotEmpty;
  }

  @override
  Future<String?> unavailableReason() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return 'YouTube Music est disponible sur Android et iOS.';
    }
    if (Platform.isIOS && iosClientId.trim().isEmpty) {
      return 'Le Client ID OAuth iOS doit être configuré dans les variables Codemagic.';
    }
    if (serverClientId.trim().isEmpty) {
      return 'Le Client ID OAuth Web de Google doit être configuré dans les variables Codemagic.';
    }
    return null;
  }

  Future<void> _initialize() {
    // GoogleSignIn.instance est un singleton : une seule initialisation même si Riverpod recrée le backend.
    return _globalInitialization ??= _signIn.initialize(
      clientId: Platform.isIOS ? iosClientId.trim() : null,
      serverClientId: serverClientId.trim(),
    );
  }

  /// Restaure une session Google existante sans ouvrir systématiquement l'écran de connexion.
  Future<bool> restore() async {
    if (!await isAvailable()) return false;
    try {
      await _initialize();
      final attempt = _signIn.attemptLightweightAuthentication();
      if (attempt != null) _account = await attempt;
      _connected = _account != null;
      return _connected;
    } catch (_) {
      _account = null;
      _connected = false;
      return false;
    }
  }

  @override
  Future<bool> connect() async {
    final reason = await unavailableReason();
    if (reason != null) throw MusicException(reason);
    await _initialize();
    try {
      _account = await _signIn.authenticate(scopeHint: _scopes);
      final authorization = await _account!.authorizationClient.authorizationForScopes(_scopes) ??
          await _account!.authorizationClient.authorizeScopes(_scopes);
      if (authorization.accessToken.isEmpty) {
        throw const MusicException('Google n’a pas fourni de jeton d’accès YouTube.');
      }
      _connected = true;
      return true;
    } on GoogleSignInException catch (error) {
      _account = null;
      _connected = false;
      throw MusicException('Connexion Google impossible : ${error.description ?? error.code.name}.');
    } on MusicException {
      rethrow;
    } catch (error) {
      _account = null;
      _connected = false;
      throw MusicException('Connexion à YouTube Music impossible : ${error.runtimeType}.');
    }
  }

  @override
  bool get connected => _connected && _account != null;

  @override
  Future<void> disconnect() async {
    try {
      await _signIn.signOut();
    } on GoogleSignInException {
      // La session locale est effacée même si Google ne peut pas confirmer la déconnexion.
    }
    _account = null;
    _connected = false;
  }

  Future<String> _accessToken() async {
    final account = _account;
    if (!_connected || account == null) {
      throw const MusicException('Connectez-vous à votre compte Google pour accéder à vos playlists.', needsLogin: true);
    }
    try {
      final authorization = await account.authorizationClient.authorizationForScopes(_scopes);
      if (authorization == null || authorization.accessToken.isEmpty) {
        throw const MusicException('Autorisation YouTube expirée. Reconnectez votre compte Google.', needsLogin: true);
      }
      return authorization.accessToken;
    } on GoogleSignInException catch (error) {
      throw MusicException('Autorisation YouTube refusée : ${error.description ?? error.code.name}.', needsLogin: true);
    }
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, dynamic> query) async {
    try {
      final token = await _accessToken();
      final response = await _api.get<Map<String, dynamic>>(
        path,
        queryParameters: query,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data ?? const {};
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 || error.response?.statusCode == 403) {
        throw const MusicException(
          'YouTube a refusé l’accès. Vérifiez le compte Google et l’activation de YouTube Data API v3.',
          needsLogin: true,
        );
      }
      if (error.response?.statusCode == 429) {
        throw const MusicException('Le quota YouTube Data API est dépassé. Réessayez plus tard.');
      }
      throw const MusicException('YouTube Music est momentanément injoignable.');
    }
  }

  String? _thumbnail(Map<String, dynamic> snippet) {
    final thumbnails = snippet['thumbnails'];
    if (thumbnails is! Map) return null;
    for (final key in const ['high', 'medium', 'default']) {
      final value = thumbnails[key];
      if (value is Map && value['url'] is String) return value['url'] as String;
    }
    return null;
  }

  @override
  Future<MusicResults> search(String query) async {
    final term = query.trim();
    if (term.isEmpty) return const MusicResults();
    final data = await _get('/search', {
      'part': 'snippet',
      'type': 'video',
      'videoCategoryId': '10',
      'q': term,
      'maxResults': 20,
      'relevanceLanguage': 'fr',
      'regionCode': 'FR',
    });
    final items = data['items'];
    final tracks = <MusicTrack>[];
    if (items is List) {
      for (final raw in items) {
        if (raw is! Map || raw['snippet'] is! Map || raw['id'] is! Map) continue;
        final id = (raw['id'] as Map)['videoId'];
        final snippet = Map<String, dynamic>.from(raw['snippet'] as Map);
        final title = snippet['title'];
        if (id is! String || id.isEmpty || title is! String) continue;
        tracks.add(MusicTrack(
          id: 'yt$id',
          title: title,
          artist: '${snippet['channelTitle'] ?? ''}',
          artUrl: _thumbnail(snippet),
          uri: id,
        ));
      }
    }
    return MusicResults(tracks: tracks);
  }

  @override
  Future<List<MusicCollection>> library(CollectionKind kind) async {
    if (kind != CollectionKind.playlist) return const [];
    final data = await _get('/playlists', {
      'part': 'snippet,contentDetails',
      'mine': 'true',
      'maxResults': 50,
    });
    final items = data['items'];
    if (items is! List) return const [];
    final collections = <MusicCollection>[];
    for (final raw in items) {
      if (raw is! Map || raw['id'] is! String || raw['snippet'] is! Map) continue;
      final snippet = Map<String, dynamic>.from(raw['snippet'] as Map);
      final id = raw['id'] as String;
      collections.add(MusicCollection(
        id: id,
        kind: CollectionKind.playlist,
        title: '${snippet['title'] ?? 'Playlist YouTube'}',
        subtitle: '${snippet['channelTitle'] ?? 'YouTube Music'}',
        artUrl: _thumbnail(snippet),
        uri: 'https://music.youtube.com/playlist?list=$id',
      ));
    }
    return collections;
  }

  @override
  Future<List<MusicTrack>> tracksOf(MusicCollection collection) async {
    if (collection.kind != CollectionKind.playlist) return const [];
    final output = <MusicTrack>[];
    String? pageToken;
    // Deux pages maximum (100 titres) : limite la consommation de quota lors de la consultation.
    for (var page = 0; page < 2; page++) {
      final query = <String, dynamic>{
        'part': 'snippet,contentDetails',
        'playlistId': collection.id,
        'maxResults': 50,
      };
      if (pageToken != null) query['pageToken'] = pageToken;
      final data = await _get('/playlistItems', query);
      final items = data['items'];
      if (items is List) {
        for (final raw in items) {
          if (raw is! Map || raw['snippet'] is! Map) continue;
          final snippet = Map<String, dynamic>.from(raw['snippet'] as Map);
          final resource = snippet['resourceId'];
          final id = resource is Map ? resource['videoId'] : null;
          final title = snippet['title'];
          if (id is! String || id.isEmpty || title is! String || title == 'Deleted video' || title == 'Private video') continue;
          output.add(MusicTrack(
            id: 'yt$id',
            title: title,
            artist: '${snippet['videoOwnerChannelTitle'] ?? snippet['channelTitle'] ?? ''}',
            artUrl: _thumbnail(snippet),
            uri: id,
          ));
        }
      }
      pageToken = data['nextPageToken'] as String?;
      if (pageToken == null || pageToken.isEmpty) break;
    }
    return output;
  }

  Future<bool> _open(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
      return await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> playTrack(MusicTrack track, {List<MusicTrack> queue = const []}) async {
    final videoId = track.uri;
    if (videoId == null || videoId.isEmpty) throw const MusicException('Identifiant YouTube manquant.');
    if (!await _open('https://music.youtube.com/watch?v=$videoId')) {
      throw const MusicException('Impossible d’ouvrir YouTube Music sur cet appareil.');
    }
  }

  @override
  Future<void> playCollection(MusicCollection collection) async {
    final url = collection.uri ?? 'https://music.youtube.com/playlist?list=${collection.id}';
    if (!await _open(url)) throw const MusicException('Impossible d’ouvrir YouTube Music sur cet appareil.');
  }

  @override
  Future<PlaybackSnapshot> snapshot() async => PlaybackSnapshot.idle;

  @override
  Future<void> play() async => throw const MusicException('La lecture se contrôle dans l’application YouTube Music.');
  @override
  Future<void> pause() async => throw const MusicException('La lecture se contrôle dans l’application YouTube Music.');
  @override
  Future<void> next() async => throw const MusicException('La lecture se contrôle dans l’application YouTube Music.');
  @override
  Future<void> previous() async => throw const MusicException('La lecture se contrôle dans l’application YouTube Music.');
  @override
  Future<void> seek(int positionMs) async => throw const MusicException('La lecture se contrôle dans l’application YouTube Music.');
  @override
  Future<void> setVolume(double volume) async => throw const MusicException('Le volume se règle dans l’application YouTube Music.');
  @override
  Future<void> setShuffle(bool on) async => throw const MusicException('L’aléatoire se règle dans l’application YouTube Music.');
  @override
  Future<void> setRepeat(PlayerRepeatMode mode) async => throw const MusicException('La répétition se règle dans l’application YouTube Music.');

  @override
  void dispose() {}
}
