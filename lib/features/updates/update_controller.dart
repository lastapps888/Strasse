import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/notifications/notifications_service.dart';
import 'package:strasse/features/updates/update_service.dart';

enum UpdatePhase { idle, checking, downloading, readyToInstall, downloaded, error }

class UpdateState {
  const UpdateState({this.installed = '', this.release, this.phase = UpdatePhase.idle, this.progress = 0, this.message, this.checkedAt, this.seen = false, this.apkPath, this.ipaPath});
  final String installed;
  final AppRelease? release;
  final UpdatePhase phase;
  final double progress;
  final String? message;
  final DateTime? checkedAt;

  /// Vrai quand l'utilisateur a déjà ouvert l'écran de cette version (le badge disparaît).
  final bool seen;
  final String? apkPath;
  final String? ipaPath;

  bool get available => release != null && installed.isNotEmpty && compareVersions(release!.version, installed) > 0;
  bool get showBadge => available && !seen;

  UpdateState copyWith({String? installed, AppRelease? release, bool clearRelease = false, UpdatePhase? phase, double? progress, String? message, bool clearMessage = false, DateTime? checkedAt, bool? seen, String? apkPath, String? ipaPath}) => UpdateState(
        installed: installed ?? this.installed,
        release: clearRelease ? null : (release ?? this.release),
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
        message: clearMessage ? null : (message ?? this.message),
        checkedAt: checkedAt ?? this.checkedAt,
        seen: seen ?? this.seen,
        apkPath: apkPath ?? this.apkPath,
        ipaPath: ipaPath ?? this.ipaPath,
      );
}

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService(userAgent: ref.watch(appConfigProvider).userAgent));

final updateProvider = StateNotifierProvider<UpdateController, UpdateState>((ref) => UpdateController(ref));

class UpdateController extends StateNotifier<UpdateState> {
  UpdateController(this._ref) : super(const UpdateState()) {
    Future<void>.delayed(const Duration(seconds: 6), () => check());
  }

  final Ref _ref;
  CancelToken? _cancel;

  static const _every = Duration(hours: 12);

  /// Vérifie la dernière version publiée. Sans [force], au plus une fois toutes les 12 h.
  Future<void> check({bool force = false}) async {
    if (!mounted || state.phase == UpdatePhase.checking || state.phase == UpdatePhase.downloading) return;
    final prefs = _ref.read(preferencesStoreProvider);
    final last = prefs.updateCheckedAt;
    String installed = state.installed;
    if (installed.isEmpty) {
      try {
        installed = (await PackageInfo.fromPlatform()).version;
      } catch (_) {
        installed = AppConfig.version;
      }
    }
    if (!force && last != null && DateTime.now().difference(last) < _every && state.release != null) return;
    state = state.copyWith(installed: installed, phase: UpdatePhase.checking, clearMessage: true);
    try {
      final r = await _ref.read(updateServiceProvider).latest(installedVersion: installed);
      if (!mounted) return;
      await prefs.setUpdateChecked(DateTime.now());
      final seen = r != null && prefs.updateSeen == r.version;
      state = UpdateState(installed: installed, release: r, phase: UpdatePhase.idle, checkedAt: DateTime.now(), seen: seen);
      if (state.available && prefs.updateNotified != r!.version) {
        await prefs.setUpdateNotified(r.version);
        final n = _ref.read(notificationsProvider);
        if (await n.requestPermission()) {
          await n.show(NotificationChannel.updates, 'Mise à jour de Strasse disponible', 'La version ${r.version} est disponible. Ouvrez Réglages > Mise à jour.');
        }
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(installed: installed, phase: UpdatePhase.error, message: toFailure(e).message);
    }
  }

  void markSeen() {
    final r = state.release;
    if (r == null || state.seen) return;
    _ref.read(preferencesStoreProvider).setUpdateSeen(r.version);
    state = state.copyWith(seen: true);
  }

  /// Android : télécharge et vérifie l'APK, puis lance l'installateur du système (qui demande toujours confirmation).
  Future<void> downloadAndInstall() async {
    final r = state.release;
    if (r == null || !Platform.isAndroid) return;
    final svc = _ref.read(updateServiceProvider);
    _cancel = CancelToken();
    state = state.copyWith(phase: UpdatePhase.downloading, progress: 0, clearMessage: true);
    try {
      final path = await svc.downloadApk(r, onProgress: (p) {
        if (mounted) state = state.copyWith(progress: p);
      }, cancel: _cancel);
      if (!mounted) return;
      state = state.copyWith(phase: UpdatePhase.readyToInstall, apkPath: path, progress: 1);
      await install();
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(phase: UpdatePhase.error, message: e is UpdateException ? e.message : toFailure(e).message);
    }
  }

  /// Lance l'installation du fichier déjà vérifié. Si l'autorisation « sources inconnues » manque, ouvre son réglage.
  Future<void> install() async {
    final path = state.apkPath;
    if (path == null) return;
    final svc = _ref.read(updateServiceProvider);
    if (!await svc.canInstall()) {
      state = state.copyWith(phase: UpdatePhase.readyToInstall, message: 'Autorisez Strasse à installer des applications dans le réglage qui s\'ouvre, puis revenez ici et touchez « Installer ».');
      await svc.openInstallSettings();
      return;
    }
    try {
      await svc.install(path);
      state = state.copyWith(phase: UpdatePhase.readyToInstall, clearMessage: true);
    } catch (e) {
      state = state.copyWith(phase: UpdatePhase.error, message: e is UpdateException ? e.message : '$e');
    }
  }

  /// iOS : télécharge un IPA vérifié, sans tenter de l'installer automatiquement.
  Future<void> downloadIpa() async {
    final release = state.release;
    if (release == null || !Platform.isIOS || release.ipaUrl == null) return;
    _cancel = CancelToken();
    state = state.copyWith(phase: UpdatePhase.downloading, progress: 0, clearMessage: true);
    try {
      final path = await _ref.read(updateServiceProvider).downloadIpa(
        release,
        onProgress: (progress) {
          if (mounted) state = state.copyWith(progress: progress);
        },
        cancel: _cancel,
      );
      if (!mounted) return;
      state = state.copyWith(phase: UpdatePhase.downloaded, ipaPath: path, progress: 1, clearMessage: true);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        phase: UpdatePhase.error,
        message: e is UpdateException ? e.message : toFailure(e).message,
      );
    }
  }

  void cancelDownload() => _cancel?.cancel();
}
