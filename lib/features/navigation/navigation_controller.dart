import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/location/location_service.dart';
import 'package:strasse/features/navigation/navigation_engine.dart';
import 'package:strasse/features/voice/voice_service.dart';

/// Paramètres d'une session de guidage. Comparés par identité : une session = une instance.
class NavArgs {
  NavArgs({required this.route, required this.destination, required this.via, required this.prefs, required this.originName});
  final RouteOption route;
  final Place destination;
  final List<Place> via;
  final RoutePrefs prefs;
  final String originName;
}

enum NavPhase { running, rerouting, arrived, stopped }

class NavState {
  const NavState({
    required this.route,
    this.update,
    this.fix,
    this.phase = NavPhase.running,
    this.muted = false,
    this.gpsLost = false,
    this.imprecise = false,
    this.message,
    this.offRoute = false,
    this.rerouteCount = 0,
    this.upcomingEvent,
  });

  final RouteOption route;
  final NavUpdate? update;
  final UserFix? fix;
  final NavPhase phase;
  final bool muted;

  /// Plus de position récente : l'interface le dit et ne prétend pas connaître la position.
  final bool gpsLost;

  /// Précision GPS médiocre : le guidage reste actif mais peut être décalé.
  final bool imprecise;
  final String? message;
  final bool offRoute;
  final int rerouteCount;
  final String? upcomingEvent;

  Maneuver? get nextManeuver {
    final u = update;
    if (route.maneuvers.isEmpty) return null;
    return route.maneuvers[(u?.nextManeuverIndex ?? 0).clamp(0, route.maneuvers.length - 1)];
  }

  Maneuver? get thenManeuver {
    final u = update;
    final i = (u?.nextManeuverIndex ?? 0) + 1;
    return i < route.maneuvers.length ? route.maneuvers[i] : null;
  }

  NavState copyWith({
    RouteOption? route,
    NavUpdate? update,
    UserFix? fix,
    NavPhase? phase,
    bool? muted,
    bool? gpsLost,
    bool? imprecise,
    String? message,
    bool clearMessage = false,
    bool? offRoute,
    int? rerouteCount,
    String? upcomingEvent,
    bool clearEvent = false,
  }) =>
      NavState(
        route: route ?? this.route,
        update: update ?? this.update,
        fix: fix ?? this.fix,
        phase: phase ?? this.phase,
        muted: muted ?? this.muted,
        gpsLost: gpsLost ?? this.gpsLost,
        imprecise: imprecise ?? this.imprecise,
        message: clearMessage ? null : (message ?? this.message),
        offRoute: offRoute ?? this.offRoute,
        rerouteCount: rerouteCount ?? this.rerouteCount,
        upcomingEvent: clearEvent ? null : (upcomingEvent ?? this.upcomingEvent),
      );
}

/// Pilote une session de guidage : position → moteur de guidage → voix, recalcul, historique, mode économie d'écran.
class NavigationController extends StateNotifier<NavState> {
  NavigationController(this._ref, this.args) : super(NavState(route: args.route)) {
    _engine = NavigationEngine(args.route, units: _ref.read(settingsProvider).units);
  }

  final Ref _ref;
  final NavArgs args;
  late NavigationEngine _engine;

  final DateTime startedAt = DateTime.now();
  DateTime _lastFixAt = DateTime.now();
  DateTime _lastRerouteTry = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastTrafficRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _watchdog;
  bool _rerouting = false;
  bool _finished = false;
  bool _offRouteAnnounced = false;
  bool _gpsLostAnnounced = false;
  final Set<String> _eventsAnnounced = {};
  double _travelledM = 0;
  GeoPoint? _lastPoint;
  bool _disposed = false;

  VoiceService get _voice => _ref.read(voiceProvider);

  Future<void> start() async {
    final s = _ref.read(settingsProvider);
    await _voice.init();
    await _voice.configure(enabled: s.voiceEnabled, voiceName: s.voiceName, volume: s.voiceVolume, rate: s.voiceRate);
    state = state.copyWith(muted: !s.voiceEnabled);
    if (s.keepScreenOn) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    }
    await _ref.read(locationControllerProvider.notifier).setNavigationMode(true);
    await _saveSession();
    _watchdog = Timer.periodic(const Duration(seconds: 3), (_) => _checkGps());
    final fix = _ref.read(locationControllerProvider).fix;
    if (fix != null) onFix(fix);
  }

  Future<void> _saveSession() async {
    await _ref.read(preferencesStoreProvider).writeActiveNavigation({
      'destination': args.destination.toJson(),
      'via': [for (final v in args.via) v.toJson()],
      'mode': args.route.mode.name,
      'prefs': args.prefs.toJson(),
      'originName': args.originName,
      'startedAt': startedAt.toUtc().toIso8601String(),
    });
  }

  void setMuted(bool muted) {
    state = state.copyWith(muted: muted);
    if (muted) _voice.stop();
  }

  void _say(String text, {bool interrupt = false}) {
    if (state.muted) return;
    _voice.speak(text, interrupt: interrupt);
  }

  void _checkGps() {
    if (_disposed || _finished) return;
    final lost = DateTime.now().difference(_lastFixAt).inSeconds > 10;
    if (lost && !state.gpsLost) {
      state = state.copyWith(gpsLost: true, message: 'Signal GPS perdu. Le guidage reprendra dès le retour du signal.');
      if (!_gpsLostAnnounced) {
        _gpsLostAnnounced = true;
        _say('Signal GPS perdu.');
      }
    } else if (!lost && state.gpsLost) {
      state = state.copyWith(gpsLost: false, clearMessage: true);
      _gpsLostAnnounced = false;
    }
  }

  void onFix(UserFix? fix) {
    if (fix == null || _disposed || _finished) return;
    _lastFixAt = DateTime.now();
    final last = _lastPoint;
    if (last != null) {
      final d = distanceM(last, fix.point);
      if (d > 3 && d < 500) _travelledM += d;
    }
    _lastPoint = fix.point;

    final u = _engine.update(fix.point, accuracyM: fix.accuracyM);
    final imprecise = fix.quality == FixQuality.poor;
    final msg = state.message;
    final transient = msg != null && (msg.startsWith('Précision') || msg.startsWith('Signal GPS') || msg.startsWith('Recalcul'));
    state = state.copyWith(
      update: u,
      fix: fix,
      imprecise: imprecise,
      gpsLost: false,
      offRoute: u.offRoute,
      message: imprecise ? 'Précision GPS faible (±${fix.accuracyM.round()} m) : le guidage peut être décalé.' : null,
      clearMessage: !imprecise && transient && !(u.offRoute && (msg?.startsWith('Recalcul') ?? false)),
    );

    for (final line in u.speech) {
      _say(line);
    }

    if (u.arrived) {
      _arrive();
      return;
    }
    if (u.offRoute) {
      if (!_offRouteAnnounced) {
        _offRouteAnnounced = true;
        _say('Vous êtes hors itinéraire.', interrupt: true);
      }
      _tryReroute(fix);
    } else {
      _offRouteAnnounced = false;
    }
    _checkEventsAhead(u);
    _refreshTraffic(fix);
  }

  Future<void> _tryReroute(UserFix fix) async {
    if (_rerouting || DateTime.now().difference(_lastRerouteTry).inSeconds < 10) return;
    _rerouting = true;
    _lastRerouteTry = DateTime.now();
    state = state.copyWith(phase: NavPhase.rerouting, message: 'Recalcul de l\'itinéraire…');
    try {
      // Étapes restantes : celles dont l'indice dans la polyligne est devant nous.
      final seg = state.update?.currentSegment ?? 0;
      final idx = state.route.waypointIndices;
      final remainingVia = <Place>[];
      for (var k = 0; k < args.via.length; k++) {
        final passed = k < idx.length && idx[k] <= seg;
        if (!passed) remainingVia.add(args.via[k]);
      }
      final points = [fix.point, ...remainingVia.map((p) => p.point), args.destination.point];
      final routes = await _ref.read(routingServiceProvider).plan(points, state.route.mode, args.prefs, alternates: 0);
      if (_disposed || _finished) return;
      final route = routes.first;
      _engine = NavigationEngine(route, units: _ref.read(settingsProvider).units);
      _offRouteAnnounced = false;
      state = NavState(route: route, muted: state.muted, rerouteCount: state.rerouteCount + 1, fix: fix);
      _say('Nouvel itinéraire calculé.');
      onFix(fix);
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(phase: NavPhase.running, message: 'Recalcul impossible : ${toFailure(e).message} Nouvelle tentative automatique.');
    } finally {
      _rerouting = false;
    }
  }

  void _checkEventsAhead(NavUpdate u) {
    if (!_ref.read(settingsProvider).announceReports) return;
    final events = _ref.read(trafficProvider).events;
    String? label;
    for (final e in events) {
      if (_eventsAnnounced.contains(e.id)) continue;
      final proj = projectOnPolyline(state.route.shape, e.point);
      if (proj.distanceM > 60) continue;
      final cum = state.route.cumulative;
      final segLen = cum[math.min(proj.segment + 1, cum.length - 1)] - cum[proj.segment];
      final at = cum[proj.segment] + proj.t * segLen;
      final ahead = at - u.alongM;
      if (ahead > 0 && ahead < 600) {
        _eventsAnnounced.add(e.id);
        label = '${e.type.label} signalé dans ${speakDistance(ahead, _ref.read(settingsProvider).units)}';
        _say('Attention, $label.');
        break;
      }
    }
    if (label != null) state = state.copyWith(upcomingEvent: label);
  }

  void _refreshTraffic(UserFix fix) {
    if (!_ref.read(settingsProvider).showTrafficEvents) return;
    if (DateTime.now().difference(_lastTrafficRefresh).inSeconds < 60) return;
    _lastTrafficRefresh = DateTime.now();
    _ref.read(trafficProvider.notifier).refresh(GeoBounds.around(fix.point, 4000), force: true);
  }

  void clearUpcomingEvent() => state = state.copyWith(clearEvent: true);

  Future<void> _arrive() async {
    if (_finished) return;
    state = state.copyWith(phase: NavPhase.arrived, clearMessage: true);
    await _finish(completed: true);
    if (_ref.read(settingsProvider).notifyTrips) {
      await _ref.read(notificationsProvider).notifyTripEvent('Trajet terminé', 'Vous êtes arrivé à ${args.destination.title}.');
    }
  }

  /// Arrêt demandé par l'utilisateur.
  Future<void> stop() async {
    if (_finished) return;
    state = state.copyWith(phase: NavPhase.stopped);
    await _finish(completed: false);
  }

  Future<void> _finish({required bool completed}) async {
    if (_finished) return;
    _finished = true;
    _watchdog?.cancel();
    await _voice.stop();
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    await _ref.read(locationControllerProvider.notifier).setNavigationMode(false);
    await _ref.read(preferencesStoreProvider).clearActiveNavigation();

    final s = _ref.read(settingsProvider);
    // Un trajet interrompu avant 100 m n'est pas enregistré.
    if (s.historyEnabled && (completed || _travelledM > 100)) {
      final r = args.route;
      try {
        await _ref.read(tripsRepositoryProvider).addTrip(TripRecord(
              id: '',
              startedAt: startedAt,
              fromName: args.originName,
              from: r.start,
              toName: args.destination.title,
              to: args.destination.point,
              mode: r.mode,
              distanceM: completed ? r.distanceM : _travelledM,
              durationS: DateTime.now().difference(startedAt).inSeconds.toDouble(),
              shape: encodePolyline(r.shape),
              completed: completed,
            ));
        _ref.invalidate(tripStatsProvider);
        _ref.invalidate(frequentDestinationsProvider);
        _ref.invalidate(historyProvider);
      } catch (_) {
        // L'échec d'écriture de l'historique ne doit jamais perturber la fin du guidage.
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _watchdog?.cancel();
    if (!_finished) {
      // Fermeture brutale de la page : on libère quand même les ressources ; la session reste mémorisée pour être reprise.
      WakelockPlus.disable().catchError((_) {});
      _ref.read(locationControllerProvider.notifier).setNavigationMode(false);
    }
    super.dispose();
  }
}

final navigationControllerProvider = StateNotifierProvider.autoDispose.family<NavigationController, NavState, NavArgs>((ref, args) {
  final c = NavigationController(ref, args);
  ref.listen<UserFix?>(locationControllerProvider.select((s) => s.fix), (_, fix) => c.onFix(fix));
  return c;
});
