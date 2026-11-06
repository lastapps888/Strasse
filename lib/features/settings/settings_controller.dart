import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/core/storage/preferences_store.dart';
import 'package:strasse/features/settings/settings_model.dart';

/// Réglages persistants : chaque modification est enregistrée immédiatement sur l'appareil.
class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._prefs, AppSettings initial) : super(initial);

  final PreferencesStore _prefs;

  static AppSettings load(PreferencesStore prefs) {
    final json = prefs.readSettingsJson();
    return json == null ? const AppSettings() : AppSettings.fromJson(json);
  }

  Future<void> update(AppSettings Function(AppSettings s) change) async {
    state = change(state);
    await _prefs.writeSettingsJson(state.toJson());
    await _prefs.touchSettings();
  }

  /// Applique des préférences reçues de la synchronisation (sans toucher aux adresses de serveurs).
  Future<void> applyRemote(Map<String, dynamic> remote) async {
    state = state.mergedWithSync(remote);
    await _prefs.writeSettingsJson(state.toJson());
  }

  /// Retour aux réglages d'origine.
  Future<void> reset() async {
    state = const AppSettings(onboardingDone: true);
    await _prefs.writeSettingsJson(state.toJson());
    await _prefs.touchSettings();
  }
}
