import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:strasse/core/core.dart';

enum LocationStatus { unknown, serviceOff, denied, deniedForever, granted }

/// Qualité de la position : une position imprécise n'est jamais présentée comme exacte.
enum FixQuality { good, fair, poor }

class UserFix {
  const UserFix({
    required this.point,
    required this.accuracyM,
    required this.speedMps,
    required this.headingDeg,
    required this.time,
  });

  final GeoPoint point;
  final double accuracyM;

  /// Vitesse en m/s (0 si inconnue).
  final double speedMps;

  /// Cap en degrés, ou NaN s'il est inconnu (appareil immobile).
  final double headingDeg;
  final DateTime time;

  bool get hasHeading => headingDeg.isFinite && headingDeg >= 0;

  FixQuality get quality => accuracyM <= 25 ? FixQuality.good : (accuracyM <= 60 ? FixQuality.fair : FixQuality.poor);

  factory UserFix.fromPosition(Position p) => UserFix(
        point: GeoPoint(p.latitude, p.longitude),
        accuracyM: p.accuracy.isFinite ? p.accuracy : 999,
        speedMps: (p.speed.isFinite && p.speed > 0) ? p.speed : 0,
        headingDeg: (p.heading.isFinite && p.heading >= 0 && p.speed > 1.0) ? p.heading : double.nan,
        time: p.timestamp,
      );
}

class LocationState {
  const LocationState({this.status = LocationStatus.unknown, this.fix, this.navigationMode = false});

  final LocationStatus status;
  final UserFix? fix;
  final bool navigationMode;

  bool get granted => status == LocationStatus.granted;

  LocationState copyWith({LocationStatus? status, UserFix? fix, bool? navigationMode, bool clearFix = false}) => LocationState(
        status: status ?? this.status,
        fix: clearFix ? null : (fix ?? this.fix),
        navigationMode: navigationMode ?? this.navigationMode,
      );
}

/// Gestion de la position : permissions, flux GPS, mode navigation (service d'avant-plan Android,
/// mises à jour en arrière-plan iOS).
class LocationController extends StateNotifier<LocationState> {
  LocationController() : super(const LocationState());

  StreamSubscription<Position>? _sub;
  StreamSubscription<ServiceStatus>? _serviceSub;

  /// Vérifie l'état de la permission sans rien demander.
  Future<LocationStatus> refreshStatus() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        state = state.copyWith(status: LocationStatus.serviceOff);
        return LocationStatus.serviceOff;
      }
      final perm = await Geolocator.checkPermission();
      final s = _map(perm);
      state = state.copyWith(status: s);
      return s;
    } catch (_) {
      return state.status;
    }
  }

  LocationStatus _map(LocationPermission p) {
    switch (p) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationStatus.granted;
      case LocationPermission.deniedForever:
        return LocationStatus.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationStatus.denied;
    }
  }

  /// Demande la permission (à appeler après avoir expliqué pourquoi à l'utilisateur).
  Future<LocationStatus> request() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        state = state.copyWith(status: LocationStatus.serviceOff);
        return LocationStatus.serviceOff;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      final s = _map(perm);
      state = state.copyWith(status: s);
      if (s == LocationStatus.granted) await start();
      return s;
    } catch (_) {
      return state.status;
    }
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  /// Démarre le flux de position si la permission est accordée.
  Future<void> start({bool navigation = false}) async {
    final status = state.status == LocationStatus.unknown ? await refreshStatus() : state.status;
    if (status != LocationStatus.granted) return;
    if (_sub != null && state.navigationMode == navigation) return;
    await _sub?.cancel();
    state = state.copyWith(navigationMode: navigation);

    _serviceSub ??= Geolocator.getServiceStatusStream().listen((s) {
      if (s == ServiceStatus.disabled) {
        state = state.copyWith(status: LocationStatus.serviceOff);
      } else if (state.status == LocationStatus.serviceOff) {
        refreshStatus().then((_) => start(navigation: state.navigationMode));
      }
    });

    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && state.fix == null) {
        // Dernière position connue : affichée seulement pour centrer la carte, jamais présentée comme exacte
        // car `accuracy` reflète la mesure d'origine et le fix est remplacé dès la première position fraîche.
        state = state.copyWith(fix: UserFix.fromPosition(last));
      }
    } catch (_) {}

    _sub = Geolocator.getPositionStream(locationSettings: _settings(navigation)).listen(
      (p) => state = state.copyWith(fix: UserFix.fromPosition(p)),
      onError: (Object e) {
        // Position indisponible : on garde la dernière, l'interface signale l'ancienneté.
        refreshStatus();
      },
      cancelOnError: false,
    );
  }

  LocationSettings _settings(bool navigation) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: navigation ? LocationAccuracy.bestForNavigation : LocationAccuracy.high,
        distanceFilter: navigation ? 0 : 5,
        intervalDuration: Duration(seconds: navigation ? 1 : 3),
        foregroundNotificationConfig: navigation
            ? const ForegroundNotificationConfig(
                notificationTitle: 'Strasse — navigation en cours',
                notificationText: 'Le guidage continue lorsque l\'écran est verrouillé.',
                enableWakeLock: true,
                notificationChannelName: 'Navigation',
              )
            : null,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: navigation ? LocationAccuracy.bestForNavigation : LocationAccuracy.high,
        activityType: navigation ? ActivityType.automotiveNavigation : ActivityType.other,
        distanceFilter: navigation ? 0 : 5,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: navigation,
        allowBackgroundLocationUpdates: navigation,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5);
  }

  /// Passe en mode navigation (précision maximale, service d'avant-plan) ou revient au mode carte.
  Future<void> setNavigationMode(bool on) async {
    if (state.navigationMode == on && _sub != null) return;
    await _sub?.cancel();
    _sub = null;
    await start(navigation: on);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Position fraîche ponctuelle (délai maximal), ou null.
  Future<UserFix?> currentFix({Duration timeout = const Duration(seconds: 8)}) async {
    final s = await refreshStatus();
    if (s != LocationStatus.granted) return null;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(timeout);
      final fix = UserFix.fromPosition(p);
      state = state.copyWith(fix: fix);
      return fix;
    } catch (_) {
      return state.fix;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _serviceSub?.cancel();
    super.dispose();
  }
}

final locationControllerProvider = StateNotifierProvider<LocationController, LocationState>((ref) {
  return LocationController();
});
