import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/core/crypto/e2ee.dart';
import 'package:strasse/core/storage/secure_store.dart';
import 'package:strasse/data/providers/account_backend.dart';
import 'package:strasse/domain/domain.dart';

/// Serveur Strasse hébergé (Cloudflare Worker + D1, voir server/cloudflare) avec chiffrement de bout en bout.
///
/// Ce que le serveur voit : un condensé de l'e-mail, une clé d'authentification dérivée (jamais le mot de passe),
/// des blocs chiffrés AES-256-GCM (favoris, collections, trajets, préférences) et leurs dates de modification.
/// Ce qu'il ne voit jamais : l'e-mail, le mot de passe, la clé maître, le contenu des données.
/// Les signalements de circulation sont publics par nature (type, position arrondie, durée de vie).
class StrasseCloudBackend implements AccountBackend {
  StrasseCloudBackend({required this.baseUrl, required this.secure, this.onRecoveryKey, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
              headers: {'Accept': 'application/json'},
              validateStatus: (s) => s != null && s >= 200 && s < 300,
            )) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      final t = secure.accessToken;
      if (t != null && !o.path.contains('/auth/')) o.headers['Authorization'] = 'Bearer $t';
      h.next(o);
    }));
  }

  final String baseUrl;
  final SecureStore secure;

  /// Appelé à l'inscription avec la clé de récupération, à montrer une seule fois à l'utilisateur.
  final void Function(String recoveryKey)? onRecoveryKey;
  final Dio _dio;

  static const _kMk = 'e2ee.masterKey';
  Uint8List? _mk;
  SecretKey? _dataKey;

  @override
  bool get configured => baseUrl.isNotEmpty;

  @override
  String get label => 'Serveur Strasse';

  @override
  bool get supportsPasswordReset => false;

  /// Pas d'e-mail de réinitialisation (le serveur ne connaît pas l'adresse) : on utilise la clé de récupération.
  @override
  Future<void> resetPassword(String email) async {
    throw const Failure(FailureKind.client, 'Le mot de passe se réinitialise avec votre clé de récupération (Compte > Mot de passe oublié).');
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    if (!configured) throw Failure.notConfigured('Le serveur Strasse');
    try {
      return await run();
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }

  Future<void> _setMasterKey(Uint8List mk) async {
    _mk = mk;
    _dataKey = await E2ee.dataKey(mk);
    await secure.writeRaw(_kMk, E2ee.b64(mk));
  }

  Future<SecretKey> _key() async {
    if (_dataKey != null) return _dataKey!;
    final raw = await secure.readRaw(_kMk);
    if (raw == null || raw.isEmpty) throw const Failure(FailureKind.unauthorized, 'Clé de chiffrement absente : reconnectez-vous.');
    _mk = E2ee.unb64(raw);
    return _dataKey = await E2ee.dataKey(_mk!);
  }

  // --------------------------------------------------------------- Comptes

  @override
  Future<String> register(String email, String password) => _guard(() async {
        final pw = await E2ee.derivePassword(email, password);
        final mk = E2ee.randomBytes(32);
        final recoveryKey = E2ee.newRecoveryKey();
        final rec = await E2ee.deriveRecovery(recoveryKey);
        final r = await _dio.post<Map<String, dynamic>>('/v1/auth/register', data: {
          'emailId': E2ee.emailId(email),
          'authKey': pw.authKey,
          'wrappedMk': await E2ee.seal(pw.wrapKey, mk, 'mk-pw'),
          'wrappedMkRec': await E2ee.seal(rec.wrapKey, mk, 'mk-rec'),
          'recoveryVerifier': rec.verifier,
        });
        await _setMasterKey(mk);
        await secure.saveSession(access: r.data!['token'] as String, refresh: r.data!['token'] as String, email: email.trim());
        onRecoveryKey?.call(recoveryKey);
        return email.trim();
      });

  @override
  Future<String> login(String email, String password) => _guard(() async {
        final pw = await E2ee.derivePassword(email, password);
        final r = await _dio.post<Map<String, dynamic>>('/v1/auth/login', data: {'emailId': E2ee.emailId(email), 'authKey': pw.authKey});
        final Uint8List mk;
        try {
          mk = await E2ee.open(pw.wrapKey, r.data!['wrappedMk'] as String, 'mk-pw');
        } catch (_) {
          throw const Failure(FailureKind.client, 'Impossible d\'ouvrir vos données chiffrées avec ce mot de passe.');
        }
        await _setMasterKey(mk);
        await secure.saveSession(access: r.data!['token'] as String, refresh: r.data!['token'] as String, email: email.trim());
        return email.trim();
      });

  /// Mot de passe oublié : la clé de récupération rouvre la clé maître, puis un nouveau mot de passe est défini.
  Future<String> recover(String email, String recoveryKey, String newPassword) => _guard(() async {
        if (!E2ee.isValidRecoveryKey(recoveryKey)) throw const Failure(FailureKind.client, 'Clé de récupération invalide : elle compte 32 caractères (lettres A–Z et chiffres 2–7).');
        final rec = await E2ee.deriveRecovery(recoveryKey);
        final id = E2ee.emailId(email);
        final start = await _dio.post<Map<String, dynamic>>('/v1/auth/recover/start', data: {'emailId': id, 'recoveryVerifier': rec.verifier});
        final Uint8List mk;
        try {
          mk = await E2ee.open(rec.wrapKey, start.data!['wrappedMkRec'] as String, 'mk-rec');
        } catch (_) {
          throw const Failure(FailureKind.client, 'Cette clé de récupération n\'ouvre pas vos données.');
        }
        final pw = await E2ee.derivePassword(email, newPassword);
        final fin = await _dio.post<Map<String, dynamic>>('/v1/auth/recover/finish', data: {
          'emailId': id,
          'recoveryVerifier': rec.verifier,
          'newAuthKey': pw.authKey,
          'wrappedMk': await E2ee.seal(pw.wrapKey, mk, 'mk-pw'),
        });
        await _setMasterKey(mk);
        await secure.saveSession(access: fin.data!['token'] as String, refresh: fin.data!['token'] as String, email: email.trim());
        return email.trim();
      });

  @override
  Future<void> logout() async {
    try {
      if (configured && secure.accessToken != null) await _dio.post<void>('/v1/auth/logout');
    } catch (_) {
      // La déconnexion locale doit toujours aboutir.
    } finally {
      _mk = null;
      _dataKey = null;
      await secure.writeRaw(_kMk, null);
      await secure.clearSession();
    }
  }

  @override
  Future<void> deleteAccount() => _guard(() async {
        await _dio.delete<void>('/v1/account');
        _mk = null;
        _dataKey = null;
        await secure.writeRaw(_kMk, null);
        await secure.clearSession();
      });

  // ---------------------------------------------------------- Synchronisation chiffrée

  Future<List<Map<String, dynamic>>> _sealAll(String kind, Iterable<Map<String, dynamic>> items) async {
    final key = await _key();
    return [
      for (final j in items)
        {'kind': kind, 'id': j['id'] as String, 'deleted': false, 'blob': await E2ee.seal(key, utf8.encode(jsonEncode(j)), '$kind/${j['id']}')},
    ];
  }

  @override
  Future<SyncPayload> pull({DateTime? since}) => _guard(() async {
        final key = await _key();
        final r = await _dio.get<Map<String, dynamic>>('/v1/sync/pull', queryParameters: {'since': since?.toUtc().millisecondsSinceEpoch ?? 0});
        final favs = <Favorite>[], cols = <PlaceCollection>[], trips = <PlannedTrip>[];
        Map<String, dynamic>? prefs;
        DateTime? prefsAt;
        for (final it in (r.data!['items'] as List).cast<Map>()) {
          final blob = it['blob'];
          if (blob is! String) continue;
          final kind = it['kind'] as String, id = it['id'] as String;
          Map<String, dynamic> json;
          try {
            json = Map<String, dynamic>.from(jsonDecode(utf8.decode(await E2ee.open(key, blob, '$kind/$id'))) as Map);
          } catch (_) {
            continue; // bloc altéré ou chiffré avec une autre clé : ignoré, jamais appliqué
          }
          switch (kind) {
            case 'fav':
              favs.add(Favorite.fromSyncJson(json));
            case 'col':
              cols.add(PlaceCollection.fromSyncJson(json));
            case 'trip':
              trips.add(PlannedTrip.fromSyncJson(json));
            case 'prefs':
              prefs = Map<String, dynamic>.from(json['data'] as Map);
              prefsAt = DateTime.tryParse('${json['updatedAt']}')?.toUtc();
          }
        }
        return SyncPayload(
          serverTime: DateTime.fromMillisecondsSinceEpoch((r.data!['serverTime'] as num).toInt(), isUtc: true),
          favorites: favs,
          collections: cols,
          trips: trips,
          preferences: prefs,
          preferencesUpdatedAt: prefsAt,
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
        final items = <Map<String, dynamic>>[
          ...await _sealAll('fav', favorites.map((f) => f.toSyncJson())),
          ...await _sealAll('col', collections.map((c) => c.toSyncJson())),
          ...await _sealAll('trip', trips.map((t) => t.toSyncJson())),
          if (preferences != null)
            ...await _sealAll('prefs', [
              {'id': 'main', 'data': preferences, 'updatedAt': (preferencesUpdatedAt ?? DateTime.now()).toUtc().toIso8601String()},
            ]),
        ];
        var serverTime = DateTime.now().toUtc();
        // Le serveur accepte 500 éléments par envoi.
        for (var i = 0; i < items.length || i == 0; i += 500) {
          final chunk = items.skip(i).take(500).toList();
          final r = await _dio.post<Map<String, dynamic>>('/v1/sync/push', data: {'items': chunk});
          serverTime = DateTime.fromMillisecondsSinceEpoch((r.data!['serverTime'] as num).toInt(), isUtc: true);
          if (items.isEmpty) break;
        }
        return serverTime;
      });

  // ------------------------------------------------------------- Signalements (publics)

  @override
  Future<List<CommunityReport>> reports(GeoBounds bounds) => _guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/v1/reports', queryParameters: {'bbox': bounds.toBboxParam()});
        return [for (final e in (r.data!['reports'] as List)) CommunityReport.fromJson(Map<String, dynamic>.from(e as Map))];
      });

  @override
  Future<ReportResult> createReport(ReportType type, GeoPoint p) => _guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/v1/reports', data: {'type': type.name, 'lat': p.lat, 'lon': p.lon});
        return ReportResult(CommunityReport.fromJson(Map<String, dynamic>.from(r.data!)), merged: r.statusCode == 200);
      });

  @override
  Future<CommunityReport> confirmReport(String id) => _guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/v1/reports/$id/confirm');
        return CommunityReport.fromJson(Map<String, dynamic>.from(r.data!));
      });

  @override
  Future<CommunityReport> rejectReport(String id) => _guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/v1/reports/$id/reject');
        return CommunityReport.fromJson(Map<String, dynamic>.from(r.data!));
      });

  @override
  Future<IncidentsResult> incidents(GeoBounds bounds) async => (available: false, provider: null, incidents: <ExternalIncident>[]);
}
