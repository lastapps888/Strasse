import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Accès typé aux préférences locales (SharedPreferences). Les erreurs de lecture ne bloquent jamais l'application.
class PreferencesStore {
  PreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  static const _settingsKey = 'settings.v1';
  static const _lastSyncKey = 'sync.lastSync';
  static const _lastPushKey = 'sync.lastPush';
  static const _activeNavKey = 'navigation.activeSession';

  Map<String, dynamic>? readSettingsJson() {
    try {
      final raw = _prefs.getString(_settingsKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null; // données corrompues : retour aux valeurs par défaut
    }
  }

  Future<void> writeSettingsJson(Map<String, dynamic> json) => _prefs.setString(_settingsKey, jsonEncode(json));

  /// Date de la dernière modification locale des réglages (sert à la synchronisation des préférences).
  DateTime? get settingsUpdatedAt => _readDate('settings.updatedAt');
  Future<void> touchSettings([DateTime? t]) => _prefs.setString('settings.updatedAt', (t ?? DateTime.now()).toUtc().toIso8601String());

  DateTime? get lastPull => _readDate(_lastSyncKey);
  DateTime? get lastPush => _readDate(_lastPushKey);
  Future<void> setLastPull(DateTime t) => _prefs.setString(_lastSyncKey, t.toUtc().toIso8601String());
  Future<void> setLastPush(DateTime t) => _prefs.setString(_lastPushKey, t.toUtc().toIso8601String());
  Future<void> clearSyncState() async {
    await _prefs.remove(_lastSyncKey);
    await _prefs.remove(_lastPushKey);
  }

  DateTime? _readDate(String key) {
    final s = _prefs.getString(key);
    return s == null ? null : DateTime.tryParse(s);
  }

  Map<String, dynamic>? readActiveNavigation() {
    try {
      final raw = _prefs.getString(_activeNavKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeActiveNavigation(Map<String, dynamic> json) => _prefs.setString(_activeNavKey, jsonEncode(json));
  Future<void> clearActiveNavigation() => _prefs.remove(_activeNavKey);

  /// Efface toutes les préférences (réinitialisation complète).
  Future<void> clearAll() => _prefs.clear();
}
