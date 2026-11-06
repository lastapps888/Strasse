import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/core/storage/preferences_store.dart';
import 'package:strasse/core/storage/secure_store.dart';
import 'package:strasse/data/providers/strasse_api.dart';
import 'package:strasse/features/notifications/notifications_service.dart';
import 'package:strasse/features/settings/settings_model.dart';
import 'package:strasse/features/sync/sync_service.dart';

class AuthState {
  const AuthState({this.email, this.busy = false, this.error, this.lastSync, this.syncMessage});

  final String? email;
  final bool busy;
  final String? error;
  final DateTime? lastSync;
  final String? syncMessage;

  bool get signedIn => email != null;

  AuthState copyWith({String? email, bool clearEmail = false, bool? busy, String? error, bool clearError = false, DateTime? lastSync, String? syncMessage, bool clearMessage = false}) =>
      AuthState(
        email: clearEmail ? null : (email ?? this.email),
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
        lastSync: lastSync ?? this.lastSync,
        syncMessage: clearMessage ? null : (syncMessage ?? this.syncMessage),
      );
}

/// Compte facultatif et synchronisation. Sans compte, rien n'est envoyé nulle part.
class AuthController extends StateNotifier<AuthState> {
  AuthController({
    required this.api,
    required this.sync,
    required this.secure,
    required this.prefs,
    required this.notifications,
    required this.settings,
  }) : super(AuthState(email: secure.isSignedIn ? (secure.accountEmail ?? 'Compte Strasse') : null, lastSync: prefs.lastPull));

  final StrasseApi api;
  final SyncService sync;
  final SecureStore secure;
  final PreferencesStore prefs;
  final NotificationsService notifications;
  final AppSettings Function() settings;

  Timer? _debounce;

  Future<void> register(String email, String password) => _auth(() => api.register(email, password));
  Future<void> login(String email, String password) => _auth(() => api.login(email, password));

  Future<void> _auth(Future<String> Function() action) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final email = await action();
      state = state.copyWith(email: email, busy: false);
      await syncNow();
    } catch (e) {
      state = state.copyWith(busy: false, error: toFailure(e).message);
    }
  }

  Future<void> logout() async {
    _debounce?.cancel();
    await api.logout();
    await prefs.clearSyncState();
    state = const AuthState();
  }

  /// Supprime le compte et les données du serveur. Les données locales de l'appareil sont conservées.
  Future<bool> deleteAccount() async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await api.deleteAccount();
      await prefs.clearSyncState();
      state = const AuthState();
      return true;
    } catch (e) {
      state = state.copyWith(busy: false, error: toFailure(e).message);
      return false;
    }
  }

  Future<void> syncNow({bool silent = false}) async {
    if (!state.signedIn) return;
    state = state.copyWith(busy: true, clearError: true, clearMessage: true);
    try {
      final report = await sync.syncNow();
      state = state.copyWith(busy: false, lastSync: report.at, syncMessage: 'Synchronisation terminée.');
      if (!silent && settings().notifySync) await notifications.notifySyncDone();
    } catch (e) {
      final f = toFailure(e);
      if (f.kind == FailureKind.unauthorized) {
        await secure.clearSession();
        state = const AuthState(error: 'Session expirée. Veuillez vous reconnecter.');
      } else {
        state = state.copyWith(busy: false, error: f.message);
      }
    }
  }

  /// Planifie une synchronisation après une modification locale (regroupe les changements rapprochés).
  void schedule() {
    if (!state.signedIn || !settings().autoSync) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 6), () => syncNow(silent: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
