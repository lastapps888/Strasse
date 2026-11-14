import 'dart:async';

import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/core/storage/secure_store.dart';
import 'package:strasse/data/providers/account_backend.dart';
import 'package:strasse/domain/domain.dart';

/// Client de l'API Strasse (backend facultatif) : comptes, synchronisation, signalements, trafic.
/// Aucune de ces fonctions n'est nécessaire pour utiliser l'application.
class StrasseApi implements AccountBackend {
  StrasseApi({required this.baseUrl, required this.secure, Dio? dio, Dio? plainDio}) {
    final options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json'},
      validateStatus: (s) => s != null && s >= 200 && s < 300,
    );
    _plain = plainDio ?? Dio(options);
    _dio = dio ?? Dio(options);
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, handler) {
        o.headers['X-Install-Id'] = secure.installId;
        final token = secure.accessToken;
        if (token != null && !o.path.contains('/auth/')) o.headers['Authorization'] = 'Bearer $token';
        handler.next(o);
      },
      onError: (e, handler) async {
        final req = e.requestOptions;
        final is401 = e.response?.statusCode == 401;
        if (is401 && secure.refreshToken != null && !req.path.contains('/auth/') && req.extra['retried'] != true) {
          final ok = await _refresh();
          if (ok) {
            req.extra['retried'] = true;
            req.headers['Authorization'] = 'Bearer ${secure.accessToken}';
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
  final SecureStore secure;
  late final Dio _dio;
  late final Dio _plain;
  Future<bool>? _refreshing;

  @override
  bool get configured => baseUrl.isNotEmpty;

  @override
  String get label => 'Serveur Strasse';

  @override
  bool get supportsPasswordReset => false;

  @override
  Future<void> resetPassword(String email) async {
    throw const Failure(FailureKind.client, 'La réinitialisation du mot de passe n\'est pas disponible sur ce serveur. Utilisez Supabase ou contactez l\'administrateur du serveur.');
  }

  Future<bool> _refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final rt = secure.refreshToken;
    if (rt == null) return false;
    try {
      final r = await _plain.post('/v1/auth/refresh', data: {'refreshToken': rt});
      final d = r.data as Map;
      await secure.saveSession(access: d['accessToken'] as String, refresh: d['refreshToken'] as String);
      return true;
    } on DioException {
      await secure.clearSession();
      return false;
    }
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    if (!configured) throw Failure.notConfigured('Le serveur Strasse', hint: 'Cette fonction est facultative : renseignez le serveur dans Réglages > Services pour l\'utiliser.');
    try {
      return await run();
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }

  // --------------------------------------------------------------- Comptes

  @override
  Future<String> register(String email, String password) => _guard(() async {
        final r = await _dio.post('/v1/auth/register', data: {'email': email, 'password': password});
        return _saveSession(r.data as Map, email);
      });

  @override
  Future<String> login(String email, String password) => _guard(() async {
        final r = await _dio.post('/v1/auth/login', data: {'email': email, 'password': password});
        return _saveSession(r.data as Map, email);
      });

  Future<String> _saveSession(Map d, String fallbackEmail) async {
    final email = ((d['user'] as Map?)?['email'] as String?) ?? fallbackEmail;
    await secure.saveSession(access: d['accessToken'] as String, refresh: d['refreshToken'] as String, email: email);
    return email;
  }

  @override
  Future<void> logout() async {
    final rt = secure.refreshToken;
    try {
      if (configured && rt != null) {
        await _dio.post('/v1/auth/logout', data: {'refreshToken': rt});
      }
    } catch (_) {
      // La déconnexion locale doit toujours aboutir, même hors connexion.
    } finally {
      await secure.clearSession();
    }
  }

  /// Supprime le compte et toutes les données associées côté serveur.
  @override
  Future<void> deleteAccount() => _guard(() async {
        await _dio.delete('/v1/account');
        await secure.clearSession();
      });

  // ---------------------------------------------------------- Synchronisation

  @override
  Future<SyncPayload> pull({DateTime? since}) => _guard(() async {
        final r = await _dio.get('/v1/sync/pull', queryParameters: {if (since != null) 'since': since.toUtc().toIso8601String()});
        final d = r.data as Map;
        List<T> list<T>(String k, T Function(Map<String, dynamic>) f) =>
            ((d[k] as List?) ?? const []).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();
        final prefs = d['preferences'] as Map?;
        return SyncPayload(
          serverTime: DateTime.parse(d['serverTime'] as String).toUtc(),
          favorites: list('favorites', Favorite.fromSyncJson),
          collections: list('collections', PlaceCollection.fromSyncJson),
          trips: list('trips', PlannedTrip.fromSyncJson),
          preferences: prefs == null ? null : Map<String, dynamic>.from(prefs['data'] as Map),
          preferencesUpdatedAt: prefs == null ? null : DateTime.parse(prefs['updatedAt'] as String).toUtc(),
        );
      });

  @override
  Future<DateTime> push({
    required List<Favorite> favorites,
    required List<PlaceCollection> collections,
    required List<PlannedTrip> trips,
    Map<String, dynamic>? preferences,
    DateTime? preferencesUpdatedAt,
  }) =>
      _guard(() async {
        final body = <String, dynamic>{
          'favorites': favorites.map((f) => f.toSyncJson()).toList(),
          'collections': collections.map((c) => c.toSyncJson()).toList(),
          'trips': trips.map((t) => t.toSyncJson()).toList(),
          if (preferences != null)
            'preferences': {'data': preferences, 'updatedAt': (preferencesUpdatedAt ?? DateTime.now()).toUtc().toIso8601String()},
        };
        final r = await _dio.post('/v1/sync/push', data: body);
        return DateTime.parse((r.data as Map)['serverTime'] as String).toUtc();
      });

  // ------------------------------------------------------------- Signalements

  @override
  Future<List<CommunityReport>> reports(GeoBounds bounds) => _guard(() async {
        final r = await _dio.get('/v1/reports', queryParameters: {'bbox': bounds.toBboxParam()});
        return ((r.data as Map)['reports'] as List)
            .map((e) => CommunityReport.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      });

  @override
  Future<ReportResult> createReport(ReportType type, GeoPoint p) => _guard(() async {
        final r = await _dio.post('/v1/reports', data: {'type': type.name, 'lat': p.lat, 'lon': p.lon});
        return ReportResult(CommunityReport.fromJson(Map<String, dynamic>.from(r.data as Map)), merged: r.statusCode == 200);
      });

  @override
  Future<CommunityReport> confirmReport(String id) => _guard(() async {
        final r = await _dio.post('/v1/reports/$id/confirm');
        return CommunityReport.fromJson(Map<String, dynamic>.from(r.data as Map));
      });

  @override
  Future<CommunityReport> rejectReport(String id) => _guard(() async {
        final r = await _dio.post('/v1/reports/$id/reject');
        return CommunityReport.fromJson(Map<String, dynamic>.from(r.data as Map));
      });

  // ------------------------------------------------------------------ Trafic

  @override
  Future<IncidentsResult> incidents(GeoBounds bounds) => _guard(() async {
        final r = await _dio.get('/v1/traffic/incidents', queryParameters: {'bbox': bounds.toBboxParam()});
        final d = r.data as Map;
        return (
          available: d['available'] == true,
          provider: d['provider'] as String?,
          incidents: ((d['incidents'] as List?) ?? const [])
              .map((e) => ExternalIncident.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList(),
        );
      });
}
