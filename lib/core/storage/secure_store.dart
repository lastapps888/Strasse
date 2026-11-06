import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Stockage sécurisé (Keychain iOS / Keystore Android) : jetons de session et identifiant anonyme d'installation.
/// Les valeurs sont chargées en mémoire au démarrage pour un accès synchrone.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  final FlutterSecureStorage _storage;

  static const _kInstallId = 'installId';
  static const _kAccess = 'accessToken';
  static const _kRefresh = 'refreshToken';
  static const _kEmail = 'accountEmail';

  String installId = '';
  String? accessToken;
  String? refreshToken;
  String? accountEmail;

  Future<void> load() async {
    try {
      installId = await _storage.read(key: _kInstallId) ?? '';
      if (installId.isEmpty) {
        installId = const Uuid().v4();
        await _storage.write(key: _kInstallId, value: installId);
      }
      accessToken = await _storage.read(key: _kAccess);
      refreshToken = await _storage.read(key: _kRefresh);
      accountEmail = await _storage.read(key: _kEmail);
    } catch (_) {
      // Stockage sécurisé indisponible (appareil sans verrouillage, données corrompues) : session éphémère.
      if (installId.isEmpty) installId = const Uuid().v4();
    }
  }

  bool get isSignedIn => refreshToken != null && refreshToken!.isNotEmpty;

  Future<void> saveSession({required String access, required String refresh, String? email}) async {
    accessToken = access;
    refreshToken = refresh;
    if (email != null) accountEmail = email;
    try {
      await _storage.write(key: _kAccess, value: access);
      await _storage.write(key: _kRefresh, value: refresh);
      if (email != null) await _storage.write(key: _kEmail, value: email);
    } catch (_) {}
  }

  Future<void> clearSession() async {
    accessToken = null;
    refreshToken = null;
    accountEmail = null;
    try {
      await _storage.delete(key: _kAccess);
      await _storage.delete(key: _kRefresh);
      await _storage.delete(key: _kEmail);
    } catch (_) {}
  }

  /// Nouvel identifiant d'installation anonyme (réinitialisation de la vie privée).
  Future<void> rotateInstallId() async {
    installId = const Uuid().v4();
    try {
      await _storage.write(key: _kInstallId, value: installId);
    } catch (_) {}
  }
}
