import 'dart:async';

import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/core/storage/secure_store.dart';
import 'package:strasse/data/providers/account_backend.dart';
import 'package:strasse/domain/domain.dart';

/// Backend Supabase (projet de l'utilisateur) : GoTrue pour le compte, PostgREST pour la synchronisation,
/// fonctions SQL (RPC) pour les signalements. Seule la clé publique « anon » est utilisée : la sécurité repose
/// sur les politiques RLS décrites dans `supabase/`. Aucune clé privilégiée ne doit jamais être saisie ici.
class SupabaseBackend implements AccountBackend {
  SupabaseBackend({required String url, required String anonKey, required this.secure, Dio? dio})
      : anonKey = anonKey.trim().isNotEmpty ? anonKey.trim() : AppConfig.defaultSupabasePublishableKey,
        baseUrl = (url.trim().isNotEmpty ? url.trim() : AppConfig.defaultSupabaseUrl).replaceAll(RegExp(r'/+
    final options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json', 'apikey': this.anonKey},
      validateStatus: (s) => s != null && s >= 200 && s < 300,
    );
    _dio = dio ?? Dio(options);
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, handler) {
        final isAuthCall = o.path.startsWith('/auth/v1/token') || o.path.startsWith('/auth/v1/signup') || o.path.startsWith('/auth/v1/recover');
        final token = secure.accessToken;
        if (!isAuthCall && token != null && token.isNotEmpty) {
          o.headers['Authorization'] = 'Bearer $token';
        } else {
          // Les clés sb_publishable_ ne sont pas des JWT : elles restent exclusivement dans l'en-tête apikey.
          o.headers.remove('Authorization');
        }
        handler.next(o);
      },
      onError: (e, handler) async {
        final req = e.requestOptions;
        final expired = e.response?.statusCode == 401 || (e.response?.statusCode == 400 && '${e.response?.data}'.contains('JWT'));
        if (expired && secure.refreshToken != null && !req.path.startsWith('/auth/v1/') && req.extra['retried'] != true) {
          if (await _refresh()) {
            req.extra['retried'] = true;
            try {
              handler.resolve(await _dio.fetch(req));
              return;
            } on DioException catch (e2) {
              handler.next(e2);
              return;
            }
          }
        }
        handler.next(e);
      },
    ));
  }

  final String baseUrl;
  final String anonKey;
  final SecureStore secure;
  late final Dio _dio;
  Future<bool>? _refreshing;

  @override
  bool get configured => baseUrl.startsWith('http') && anonKey.isNotEmpty;

  @override
  String get label => 'Supabase';

  @override
  bool get supportsPasswordReset => true;

  Future<T> _guard<T>(Future<T> Function() run) async {
    if (!configured) {
      throw Failure.notConfigured('Supabase', hint: 'Cette fonction est facultative : renseignez l\'adresse du projet et la clé publique dans Réglages > Services.');
    }
    try {
      return await run();
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  /// Messages GoTrue / PostgREST : `msg`, `message`, `error_description`, `error_code`.
  Failure _failure(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final code = (data['error_code'] ?? data['code'] ?? '').toString();
      final raw = (data['msg'] ?? data['message'] ?? data['error_description'] ?? data['error'] ?? '').toString();
      final status = e.response?.statusCode;
      if (code == 'invalid_credentials' || raw.toLowerCase().contains('invalid login')) {
        return const Failure(FailureKind.client, 'E-mail ou mot de passe incorrect.', code: 'invalid_credentials');
      }
      if (code == 'email_not_confirmed' || raw.toLowerCase().contains('not confirmed')) {
        return const Failure(FailureKind.client, 'Adresse e-mail non confirmée. Ouvrez le message reçu puis reconnectez-vous.', code: 'email_not_confirmed');
      }
      if (code == 'user_already_exists' || raw.toLowerCase().contains('already registered')) {
        return const Failure(FailureKind.client, 'Un compte existe déjà avec cette adresse.', code: 'user_already_exists');
      }
      if (code == 'weak_password') {
        return Failure(FailureKind.client, raw.isEmpty ? 'Mot de passe trop faible.' : raw, code: code);
      }
      if (code == 'over_email_send_rate_limit' || code == 'over_request_rate_limit' || status == 429) {
        return const Failure(FailureKind.client, 'Trop de demandes. Réessayez dans quelques minutes.', code: 'rate_limited');
      }
      if (code == '42501' || status == 403) {
        return const Failure(FailureKind.unauthorized, 'Action refusée : connectez-vous pour continuer.', code: 'forbidden');
      }
      if (status != null && status >= 400 && status < 500 && raw.isNotEmpty) {
        return Failure(FailureKind.client, raw, code: code.isEmpty ? null : code);
      }
    }
    return Failure.fromDio(e);
  }

  Future<bool> _refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final rt = secure.refreshToken;
    if (rt == null) return false;
    try {
      final r = await _dio.post('/auth/v1/token', queryParameters: {'grant_type': 'refresh_token'}, data: {'refresh_token': rt});
      final d = r.data as Map;
      await secure.saveSession(access: d['access_token'] as String, refresh: d['refresh_token'] as String);
      return true;
    } on DioException catch (e) {
      // Seule une réponse du serveur invalide la session ; une panne réseau la conserve.
      if (e.response != null) await secure.clearSession();
      return false;
    }
  }

  // --------------------------------------------------------------- Compte

  @override
  Future<String> register(String email, String password) => _guard(() async {
        final r = await _dio.post('/auth/v1/signup', data: {'email': email, 'password': password});
        final d = r.data as Map;
        if (d['access_token'] is String && d['refresh_token'] is String) {
          return _save(d, email);
        }
        throw const Failure(FailureKind.client, 'Compte créé. Confirmez votre adresse e-mail grâce au message reçu, puis connectez-vous.', code: 'confirm_email');
      });

  @override
  Future<String> login(String email, String password) => _guard(() async {
        final r = await _dio.post('/auth/v1/token', queryParameters: {'grant_type': 'password'}, data: {'email': email, 'password': password});
        return _save(r.data as Map, email);
      });

  Future<String> _save(Map d, String fallbackEmail) async {
    final email = ((d['user'] as Map?)?['email'] as String?) ?? fallbackEmail;
    await secure.saveSession(access: d['access_token'] as String, refresh: d['refresh_token'] as String, email: email);
    return email;
  }

  @override
  Future<void> logout() async {
    try {
      if (configured && secure.accessToken != null) {
        await _dio.post('/auth/v1/logout', queryParameters: {'scope': 'local'});
      }
    } catch (_) {
      // La déconnexion locale doit toujours aboutir.
    } finally {
      await secure.clearSession();
    }
  }

  @override
  Future<void> resetPassword(String email) => _guard(() async {
        await _dio.post('/auth/v1/recover', data: {'email': email});
      });

  @override
  Future<void> deleteAccount() => _guard(() async {
        await _dio.post('/rest/v1/rpc/delete_my_account', data: const {});
        await secure.clearSession();
      });

  // ---------------------------------------------------------- Synchronisation

  static const _page = 500;

  Future<DateTime> _serverTime() async {
    final r = await _dio.post('/rest/v1/rpc/server_time', data: const {});
    return DateTime.parse('${r.data}').toUtc();
  }

  @override
  Future<SyncPayload> pull({DateTime? since}) => _guard(() async {
        final serverTime = await _serverTime();
        final rows = <Map<String, dynamic>>[];
        var offset = 0;
        while (true) {
          final r = await _dio.get('/rest/v1/sync_items', queryParameters: {
            'select': 'kind,id,data,updated_at,deleted',
            if (since != null) 'updated_at': 'gt.${since.toUtc().toIso8601String()}',
            'order': 'updated_at.asc,id.asc',
            'limit': _page,
            'offset': offset,
          });
          final list = (r.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          rows.addAll(list);
          if (list.length < _page) break;
          offset += _page;
        }
        List<T> take<T>(String kind, T Function(Map<String, dynamic>) f) {
          final out = <T>[];
          for (final row in rows.where((x) => x['kind'] == kind)) {
            final data = Map<String, dynamic>.from(row['data'] as Map);
            data['id'] = row['id'];
            data['updatedAt'] = row['updated_at'];
            data['deleted'] = row['deleted'] == true;
            try {
              out.add(f(data));
            } catch (_) {
              // Ligne illisible (ancienne version, modification manuelle) : ignorée sans bloquer la synchronisation.
            }
          }
          return out;
        }

        Map<String, dynamic>? prefs;
        DateTime? prefsAt;
        for (final row in rows.where((x) => x['kind'] == 'preferences')) {
          prefs = Map<String, dynamic>.from(row['data'] as Map);
          prefsAt = DateTime.parse(row['updated_at'] as String).toUtc();
        }
        return SyncPayload(
          serverTime: serverTime,
          favorites: take('favorite', Favorite.fromSyncJson),
          collections: take('collection', PlaceCollection.fromSyncJson),
          trips: take('trip', PlannedTrip.fromSyncJson),
          preferences: prefs,
          preferencesUpdatedAt: prefsAt,
        );
      });

  Map<String, dynamic> _row(String kind, String id, Map<String, dynamic> json, {required String updatedAt, bool deleted = false}) {
    final data = Map<String, dynamic>.from(json)
      ..remove('id')
      ..remove('updatedAt')
      ..remove('deleted');
    return {'kind': kind, 'id': id, 'data': data, 'updated_at': updatedAt, 'deleted': deleted};
  }

  @override
  Future<DateTime> push({
    required List<Favorite> favorites,
    required List<PlaceCollection> collections,
    required List<PlannedTrip> trips,
    Map<String, dynamic>? preferences,
    DateTime? preferencesUpdatedAt,
  }) =>
      _guard(() async {
        final rows = <Map<String, dynamic>>[
          for (final f in favorites) _row('favorite', f.id, f.toSyncJson(), updatedAt: f.updatedAt.toUtc().toIso8601String(), deleted: f.deleted),
          for (final c in collections) _row('collection', c.id, c.toSyncJson(), updatedAt: c.updatedAt.toUtc().toIso8601String(), deleted: c.deleted),
          for (final t in trips) _row('trip', t.id, t.toSyncJson(), updatedAt: t.updatedAt.toUtc().toIso8601String(), deleted: t.deleted),
          if (preferences != null)
            {'kind': 'preferences', 'id': 'preferences', 'data': preferences, 'updated_at': (preferencesUpdatedAt ?? DateTime.now()).toUtc().toIso8601String(), 'deleted': false},
        ];
        for (var i = 0; i < rows.length; i += _page) {
          final chunk = rows.sublist(i, i + _page > rows.length ? rows.length : i + _page);
          await _dio.post(
            '/rest/v1/sync_items',
            queryParameters: {'on_conflict': 'user_id,kind,id'},
            data: chunk,
            options: Options(headers: {'Prefer': 'resolution=merge-duplicates,return=minimal'}),
          );
        }
        return _serverTime();
      });

  // ------------------------------------------------------------- Signalements

  CommunityReport _report(Object? raw) => CommunityReport.fromJson(Map<String, dynamic>.from(raw as Map));

  @override
  Future<List<CommunityReport>> reports(GeoBounds b) => _guard(() async {
        final r = await _dio.post('/rest/v1/rpc/reports_in_bbox', data: {'p_west': b.west, 'p_south': b.south, 'p_east': b.east, 'p_north': b.north});
        return [for (final e in (r.data as List)) _report(e)];
      });

  @override
  Future<ReportResult> createReport(ReportType type, GeoPoint p) => _guard(() async {
        if (secure.accessToken == null) {
          throw const Failure(FailureKind.unauthorized, 'Connectez-vous pour signaler un événement.', code: 'sign_in_required');
        }
        final r = await _dio.post('/rest/v1/rpc/create_report', data: {'p_type': type.name, 'p_lat': p.lat, 'p_lon': p.lon});
        final d = Map<String, dynamic>.from(r.data as Map);
        return ReportResult(CommunityReport.fromJson(d), merged: d['merged'] == true);
      });

  Future<CommunityReport> _vote(String id, bool confirm) => _guard(() async {
        if (secure.accessToken == null) {
          throw const Failure(FailureKind.unauthorized, 'Connectez-vous pour confirmer ou contester un signalement.', code: 'sign_in_required');
        }
        final r = await _dio.post('/rest/v1/rpc/vote_report', data: {'p_id': id, 'p_confirm': confirm});
        return _report(r.data);
      });

  @override
  Future<CommunityReport> confirmReport(String id) => _vote(id, true);

  @override
  Future<CommunityReport> rejectReport(String id) => _vote(id, false);

  // ------------------------------------------------------------------ Trafic

  @override
  Future<IncidentsResult> incidents(GeoBounds bounds) async => (available: false, provider: null, incidents: <ExternalIncident>[]);
}), '') {
    final options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json', 'apikey': anonKey},
      validateStatus: (s) => s != null && s >= 200 && s < 300,
    );
    _dio = dio ?? Dio(options);
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, handler) {
        final isAuthCall = o.path.startsWith('/auth/v1/token') || o.path.startsWith('/auth/v1/signup') || o.path.startsWith('/auth/v1/recover');
        final token = secure.accessToken;
        o.headers['Authorization'] = 'Bearer ${(token != null && !isAuthCall) ? token : anonKey}';
        handler.next(o);
      },
      onError: (e, handler) async {
        final req = e.requestOptions;
        final expired = e.response?.statusCode == 401 || (e.response?.statusCode == 400 && '${e.response?.data}'.contains('JWT'));
        if (expired && secure.refreshToken != null && !req.path.startsWith('/auth/v1/') && req.extra['retried'] != true) {
          if (await _refresh()) {
            req.extra['retried'] = true;
            try {
              handler.resolve(await _dio.fetch(req));
              return;
            } on DioException catch (e2) {
              handler.next(e2);
              return;
            }
          }
        }
        handler.next(e);
      },
    ));
  }

  final String baseUrl;
  final String anonKey;
  final SecureStore secure;
  late final Dio _dio;
  Future<bool>? _refreshing;

  @override
  bool get configured => baseUrl.startsWith('http') && anonKey.isNotEmpty;

  @override
  String get label => 'Supabase';

  @override
  bool get supportsPasswordReset => true;

  Future<T> _guard<T>(Future<T> Function() run) async {
    if (!configured) {
      throw Failure.notConfigured('Supabase', hint: 'Cette fonction est facultative : renseignez l\'adresse du projet et la clé publique dans Réglages > Services.');
    }
    try {
      return await run();
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  /// Messages GoTrue / PostgREST : `msg`, `message`, `error_description`, `error_code`.
  Failure _failure(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final code = (data['error_code'] ?? data['code'] ?? '').toString();
      final raw = (data['msg'] ?? data['message'] ?? data['error_description'] ?? data['error'] ?? '').toString();
      final status = e.response?.statusCode;
      if (code == 'invalid_credentials' || raw.toLowerCase().contains('invalid login')) {
        return const Failure(FailureKind.client, 'E-mail ou mot de passe incorrect.', code: 'invalid_credentials');
      }
      if (code == 'email_not_confirmed' || raw.toLowerCase().contains('not confirmed')) {
        return const Failure(FailureKind.client, 'Adresse e-mail non confirmée. Ouvrez le message reçu puis reconnectez-vous.', code: 'email_not_confirmed');
      }
      if (code == 'user_already_exists' || raw.toLowerCase().contains('already registered')) {
        return const Failure(FailureKind.client, 'Un compte existe déjà avec cette adresse.', code: 'user_already_exists');
      }
      if (code == 'weak_password') {
        return Failure(FailureKind.client, raw.isEmpty ? 'Mot de passe trop faible.' : raw, code: code);
      }
      if (code == 'over_email_send_rate_limit' || code == 'over_request_rate_limit' || status == 429) {
        return const Failure(FailureKind.client, 'Trop de demandes. Réessayez dans quelques minutes.', code: 'rate_limited');
      }
      if (code == '42501' || status == 403) {
        return const Failure(FailureKind.unauthorized, 'Action refusée : connectez-vous pour continuer.', code: 'forbidden');
      }
      if (status != null && status >= 400 && status < 500 && raw.isNotEmpty) {
        return Failure(FailureKind.client, raw, code: code.isEmpty ? null : code);
      }
    }
    return Failure.fromDio(e);
  }

  Future<bool> _refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final rt = secure.refreshToken;
    if (rt == null) return false;
    try {
      final r = await _dio.post('/auth/v1/token', queryParameters: {'grant_type': 'refresh_token'}, data: {'refresh_token': rt});
      final d = r.data as Map;
      await secure.saveSession(access: d['access_token'] as String, refresh: d['refresh_token'] as String);
      return true;
    } on DioException catch (e) {
      // Seule une réponse du serveur invalide la session ; une panne réseau la conserve.
      if (e.response != null) await secure.clearSession();
      return false;
    }
  }

  // --------------------------------------------------------------- Compte

  @override
  Future<String> register(String email, String password) => _guard(() async {
        final r = await _dio.post('/auth/v1/signup', data: {'email': email, 'password': password});
        final d = r.data as Map;
        if (d['access_token'] is String && d['refresh_token'] is String) {
          return _save(d, email);
        }
        throw const Failure(FailureKind.client, 'Compte créé. Confirmez votre adresse e-mail grâce au message reçu, puis connectez-vous.', code: 'confirm_email');
      });

  @override
  Future<String> login(String email, String password) => _guard(() async {
        final r = await _dio.post('/auth/v1/token', queryParameters: {'grant_type': 'password'}, data: {'email': email, 'password': password});
        return _save(r.data as Map, email);
      });

  Future<String> _save(Map d, String fallbackEmail) async {
    final email = ((d['user'] as Map?)?['email'] as String?) ?? fallbackEmail;
    await secure.saveSession(access: d['access_token'] as String, refresh: d['refresh_token'] as String, email: email);
    return email;
  }

  @override
  Future<void> logout() async {
    try {
      if (configured && secure.accessToken != null) {
        await _dio.post('/auth/v1/logout', queryParameters: {'scope': 'local'});
      }
    } catch (_) {
      // La déconnexion locale doit toujours aboutir.
    } finally {
      await secure.clearSession();
    }
  }

  @override
  Future<void> resetPassword(String email) => _guard(() async {
        await _dio.post('/auth/v1/recover', data: {'email': email});
      });

  @override
  Future<void> deleteAccount() => _guard(() async {
        await _dio.post('/rest/v1/rpc/delete_my_account', data: const {});
        await secure.clearSession();
      });

  // ---------------------------------------------------------- Synchronisation

  static const _page = 500;

  Future<DateTime> _serverTime() async {
    final r = await _dio.post('/rest/v1/rpc/server_time', data: const {});
    return DateTime.parse('${r.data}').toUtc();
  }

  @override
  Future<SyncPayload> pull({DateTime? since}) => _guard(() async {
        final serverTime = await _serverTime();
        final rows = <Map<String, dynamic>>[];
        var offset = 0;
        while (true) {
          final r = await _dio.get('/rest/v1/sync_items', queryParameters: {
            'select': 'kind,id,data,updated_at,deleted',
            if (since != null) 'updated_at': 'gt.${since.toUtc().toIso8601String()}',
            'order': 'updated_at.asc,id.asc',
            'limit': _page,
            'offset': offset,
          });
          final list = (r.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          rows.addAll(list);
          if (list.length < _page) break;
          offset += _page;
        }
        List<T> take<T>(String kind, T Function(Map<String, dynamic>) f) {
          final out = <T>[];
          for (final row in rows.where((x) => x['kind'] == kind)) {
            final data = Map<String, dynamic>.from(row['data'] as Map);
            data['id'] = row['id'];
            data['updatedAt'] = row['updated_at'];
            data['deleted'] = row['deleted'] == true;
            try {
              out.add(f(data));
            } catch (_) {
              // Ligne illisible (ancienne version, modification manuelle) : ignorée sans bloquer la synchronisation.
            }
          }
          return out;
        }

        Map<String, dynamic>? prefs;
        DateTime? prefsAt;
        for (final row in rows.where((x) => x['kind'] == 'preferences')) {
          prefs = Map<String, dynamic>.from(row['data'] as Map);
          prefsAt = DateTime.parse(row['updated_at'] as String).toUtc();
        }
        return SyncPayload(
          serverTime: serverTime,
          favorites: take('favorite', Favorite.fromSyncJson),
          collections: take('collection', PlaceCollection.fromSyncJson),
          trips: take('trip', PlannedTrip.fromSyncJson),
          preferences: prefs,
          preferencesUpdatedAt: prefsAt,
        );
      });

  Map<String, dynamic> _row(String kind, String id, Map<String, dynamic> json, {required String updatedAt, bool deleted = false}) {
    final data = Map<String, dynamic>.from(json)
      ..remove('id')
      ..remove('updatedAt')
      ..remove('deleted');
    return {'kind': kind, 'id': id, 'data': data, 'updated_at': updatedAt, 'deleted': deleted};
  }

  @override
  Future<DateTime> push({
    required List<Favorite> favorites,
    required List<PlaceCollection> collections,
    required List<PlannedTrip> trips,
    Map<String, dynamic>? preferences,
    DateTime? preferencesUpdatedAt,
  }) =>
      _guard(() async {
        final rows = <Map<String, dynamic>>[
          for (final f in favorites) _row('favorite', f.id, f.toSyncJson(), updatedAt: f.updatedAt.toUtc().toIso8601String(), deleted: f.deleted),
          for (final c in collections) _row('collection', c.id, c.toSyncJson(), updatedAt: c.updatedAt.toUtc().toIso8601String(), deleted: c.deleted),
          for (final t in trips) _row('trip', t.id, t.toSyncJson(), updatedAt: t.updatedAt.toUtc().toIso8601String(), deleted: t.deleted),
          if (preferences != null)
            {'kind': 'preferences', 'id': 'preferences', 'data': preferences, 'updated_at': (preferencesUpdatedAt ?? DateTime.now()).toUtc().toIso8601String(), 'deleted': false},
        ];
        for (var i = 0; i < rows.length; i += _page) {
          final chunk = rows.sublist(i, i + _page > rows.length ? rows.length : i + _page);
          await _dio.post(
            '/rest/v1/sync_items',
            queryParameters: {'on_conflict': 'user_id,kind,id'},
            data: chunk,
            options: Options(headers: {'Prefer': 'resolution=merge-duplicates,return=minimal'}),
          );
        }
        return _serverTime();
      });

  // ------------------------------------------------------------- Signalements

  CommunityReport _report(Object? raw) => CommunityReport.fromJson(Map<String, dynamic>.from(raw as Map));

  @override
  Future<List<CommunityReport>> reports(GeoBounds b) => _guard(() async {
        final r = await _dio.post('/rest/v1/rpc/reports_in_bbox', data: {'p_west': b.west, 'p_south': b.south, 'p_east': b.east, 'p_north': b.north});
        return [for (final e in (r.data as List)) _report(e)];
      });

  @override
  Future<ReportResult> createReport(ReportType type, GeoPoint p) => _guard(() async {
        if (secure.accessToken == null) {
          throw const Failure(FailureKind.unauthorized, 'Connectez-vous pour signaler un événement.', code: 'sign_in_required');
        }
        final r = await _dio.post('/rest/v1/rpc/create_report', data: {'p_type': type.name, 'p_lat': p.lat, 'p_lon': p.lon});
        final d = Map<String, dynamic>.from(r.data as Map);
        return ReportResult(CommunityReport.fromJson(d), merged: d['merged'] == true);
      });

  Future<CommunityReport> _vote(String id, bool confirm) => _guard(() async {
        if (secure.accessToken == null) {
          throw const Failure(FailureKind.unauthorized, 'Connectez-vous pour confirmer ou contester un signalement.', code: 'sign_in_required');
        }
        final r = await _dio.post('/rest/v1/rpc/vote_report', data: {'p_id': id, 'p_confirm': confirm});
        return _report(r.data);
      });

  @override
  Future<CommunityReport> confirmReport(String id) => _vote(id, true);

  @override
  Future<CommunityReport> rejectReport(String id) => _vote(id, false);

  // ------------------------------------------------------------------ Trafic

  @override
  Future<IncidentsResult> incidents(GeoBounds bounds) async => (available: false, provider: null, incidents: <ExternalIncident>[]);
}