import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/core/storage/secure_store.dart';
import 'package:strasse/features/services/provider_models.dart';

/// Identifiants des fournisseurs (clés, identifiants clients), conservés dans le coffre sécurisé de l'appareil
/// (Keychain iOS, EncryptedSharedPreferences Android) et jamais synchronisés ni journalisés.
class CredentialsNotifier extends StateNotifier<Map<String, String>> {
  CredentialsNotifier(this._secure) : super(const {});

  final SecureStore _secure;
  static const _key = 'providerCredentials';

  Future<void> load() async {
    final raw = await _secure.readRaw(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        state = {
          for (final e in j.entries)
            if (e.key is String && e.value is String) e.key as String: e.value as String,
        };
      }
    } catch (_) {
      // contenu illisible : on repart de zéro
    }
  }

  Future<void> set(ServiceProvider p, String field, String value) async {
    final next = {...state};
    final k = '${p.id}.$field';
    if (value.trim().isEmpty) {
      next.remove(k);
    } else {
      next[k] = value.trim();
    }
    state = next;
    await _secure.writeRaw(_key, jsonEncode(next));
  }

  Future<void> clear() async {
    state = const {};
    await _secure.writeRaw(_key, null);
  }
}
