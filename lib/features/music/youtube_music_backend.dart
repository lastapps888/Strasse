import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:strasse/features/music/music_backend.dart';
import 'package:strasse/features/music/music_models.dart';
import 'package:url_launcher/url_launcher.dart';

/// YouTube Music : connexion Google OAuth, playlists privées et catalogue musical via YouTube Data API.
/// La lecture est explicitement ouverte dans l'application YouTube Music (ou le navigateur) :
/// l'API Data ne fournit pas le flux audio et Strasse ne tente pas de le récupérer.
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
  Future<void>? _initialization;
  bool _connected = false;

  @override
  MusicSource get source => MusicSource.youtubeMusic;

  @override
  MusicCapabilities get capabilities => const MusicCapabilities(
        // L'API YouTube ne fournit pas de contrôle de lecture audio depuis Strasse.
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
    if (Platform.isIOS) return iosClientId.trim().isNotEmpty;
    return serverClientId.trim().isNotEmpty;
  }

  @override
  Future<String?> unavailableReason() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return 'La connexion Google de YouTube Music est disponible sur Android et iOS.';
    }
    if (Platform.isIOS && iosClientId.trim().isEmpty) {
      return 'Le Client ID OAuth iOS de Google doit être renseigné dans les variables Codemagic avant de compiler l’application.';
    }
    if (serverClientId.trim().isEmpty) {
      return 'Le Client ID OAuth Web (server client ID) de Google doit être renseigné dans les variables Codemagic.';
    }
    return null;
  }

  Future<void> _initialize() {
    return _initialization ??= _signIn.initialize(
      clientId: Platform.isIOS ? iosClientId.trim() : null,
      serverClientId: serverClientId.trim(),
    );
  }

  /// Restaure la session Google sans ouvrir systématiquement une fenêtre de connexion.
  Future<bool> restore() async {
    if (!await isAvailable()) return false;
    await _initialize();
    final attempt = _signIn.attemptLightweightAuthentication();
    if (attempt != null) {
      _account = await attempt;
    }
    _connected = _account != null;
    return _connected;
  }

  @override
  Future<bool> connect() async {
    final reason = await unavailableReason();
    if (reason != null) throw MusicException(reason);

    await _initialize();
    try {
      _account = await _signIn.authenticate(scopeHint: _scopes);
      // authenticate(scopeHint:) ne garantit pas que l'autorisation YouTube est déjà délivrée.
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
      // La session locale est tout de même effacée.
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
      final authorization = await account.authorizationClient.authorizationForScopes(_scopes) ??
          await account.authorizationClient.authorizeScopes(_scopes);
      if (authorization.accessToken.isEmpty) {
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
        throw const MusicException('YouTube a refusé l’accès. Vérifiez l’autorisation du compte et l’activation de YouTube Data API v3.', needsLogin: true);
      }
      if (error.response?.statusCode == 429) {
        throw const MusicException('Le quota YouTube Data API est temporairement dépassé. Réessayez plus tard.');
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

  MusicTrack? _track(Object? raw) {
    if (raw is! Map) return null;
    final snippet = raw['snippet'];
    final id = raw['id'];
    if (snippet is! Map || id is! Map) return null;
    final videoId = id['videoId'] ?? (id['kind'] == 'youtube#video' ? id['videoId'] : null);
    final title = snippet['title'];
    if (videoId is! String || videoId.isEmpty || title is! String) return null;
    return MusicTrack(
      id: 'yt$videoId',
      title: title,
      artist: '${snippet['channelTitle'] ?? ''}',
      artUrl: _thumbnail(Map<String, dynamic>.from(snippet)),
      uri: videoId,
    );
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
    return MusicResults(
      tracks: [
        for (final item in (items is List ? items : const []))
          if (_track(item) case final track?) track,
      ],
    );
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
    return [
      for (final item in items)
        if (item is Map && item['id'] is String && item['snippet'] is Map)
          MusicCollection(
            id: item['id'] as String,
            kind: CollectionKind.playlist,
            title: '${(item['snippet'] as Map)['title'] ?? 'Playlist YouTube'}',
            subtitle: '${(item['snippet'] as Map)['channelTitle'] ?? 'YouTube Music'}',
            artUrl: _thumbnail(Map<String, dynamic>.from(item['snippet'] as Map)),
            uri: 'https://music.youtube.com/playlist?list=${item['id']}',
          ),
    ];
  }

  @override
  Future<List<MusicTrack>> tracksOf(MusicCollection collection) async {
    if (collection.kind != CollectionKind.playlist) return const [];
    final output = <MusicTrack>[];
    String? pageToken;
    // Deux pages maximum : 100 éléments suffisent pour une première navigation et évitent
    // de consommer le quota API inutilement sur de très longues playlists.
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
        for (final item in items) {
          if (item is! Map || item['snippet'] is! Map) continue;
          final snippet = Map<String, dynamic>.from(item['snippet'] as Map);
          final resource = snippet['resourceId'];
          final videoId = resource is Map ? resource['videoId'] : null;
          final title = snippet['title'];
          if (videoId is! String || videoId.isEmpty || title is! String || title == 'Deleted video' || title == 'Private video') continue;
          output.add(MusicTrack(
            id: 'yt$videoId',
            title: title,
            artist: '${snippet['videoOwnerChannelTitle'] ?? snippet['channelTitle'] ?? ''}',
            artUrl: _thumbnail(snippet),
            uri: videoId,
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
    if (videoId == null || videoId.isEmpty) throw const MusicException('Identifiant vidéo YouTube manquant.');
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
