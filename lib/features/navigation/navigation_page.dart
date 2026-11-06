import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/map/strasse_map.dart';
import 'package:strasse/features/navigation/navigation_controller.dart';
import 'package:strasse/features/settings/settings_model.dart';
import 'package:strasse/features/traffic/report_sheet.dart';

/// Écran de guidage actif : bannière de manœuvre, carte qui suit la position, ETA, vitesse, voix, signalement.
const Color _kPanelDark = Color(0xFF1C2125);

class NavigationPage extends ConsumerStatefulWidget {
  const NavigationPage({super.key, required this.route, required this.destination, this.via = const [], required this.prefs, this.originName = 'Ma position'});

  final RouteOption route;
  final Place destination;
  final List<Place> via;
  final RoutePrefs prefs;
  final String originName;

  @override
  ConsumerState<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends ConsumerState<NavigationPage> with WidgetsBindingObserver {
  late final NavArgs _args = NavArgs(route: widget.route, destination: widget.destination, via: widget.via, prefs: widget.prefs, originName: widget.originName);
  StrasseMapController? _map;
  bool _free = false; // l'utilisateur a déplacé la carte : on ne la recentre plus automatiquement
  RouteOption? _drawnRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(navigationControllerProvider(_args).notifier).start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_free) _recenter();
  }

  bool? _forceDark(AppSettings s) => switch (s.nightMode) {
        NightMode.on => true,
        NightMode.off => false,
        NightMode.auto => null,
      };

  void _onReady(StrasseMapController c) {
    _map = c;
    c.trackUserGestures = true;
    c.onUserMoved = () {
      if (!_free && mounted) setState(() => _free = true);
    };
    _applyState(ref.read(navigationControllerProvider(_args)), force: true);
  }

  void _applyState(NavState st, {bool force = false}) {
    final c = _map;
    if (c == null) return;
    final s = ref.read(settingsProvider);
    if (force || !identical(_drawnRoute, st.route)) {
      _drawnRoute = st.route;
      c.setRoutes([st.route], 0, Color(s.routeColor));
      c.setPins([MapPin(id: 'dest', point: widget.destination.point, color: Color(s.markerColor), radius: 10)]);
    }
    final fix = st.fix;
    if (fix != null) {
      c.setUser(fix.point, accuracy: fix.accuracyM, stale: st.gpsLost, color: s.primary);
      if (!_free) {
        final speedKmh = fix.speedMps * 3.6;
        final zoom = st.route.mode == TravelMode.car ? (speedKmh > 90 ? 15.2 : (speedKmh > 50 ? 16.0 : 17.0)) : 17.5;
        final bearing = fix.hasHeading ? fix.headingDeg : (st.update?.bearing ?? 0);
        c.flyTo(fix.point, zoom: zoom, bearing: bearing, tilt: s.simpleDrivingMode ? 0 : 45, ms: 900);
      }
    }
  }

  void _recenter() {
    setState(() => _free = false);
    _applyState(ref.read(navigationControllerProvider(_args)));
  }

  Future<void> _overview() async {
    setState(() => _free = true);
    await _map?.fitPoints(widget.route.shape.isEmpty ? [widget.destination.point] : ref.read(navigationControllerProvider(_args)).route.shape, top: 200, bottom: 200);
  }

  Future<void> _confirmStop() async {
    final ok = await confirm(context, title: 'Arrêter le guidage ?', message: 'Le trajet en cours sera interrompu.', confirmLabel: 'Arrêter', destructive: true);
    if (!ok || !mounted) return;
    await ref.read(navigationControllerProvider(_args).notifier).stop();
    if (mounted) Navigator.of(context).pop();
  }

  void _showSteps(NavState st) {
    final units = ref.read(settingsProvider).units;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, scroll) => ListView.builder(
          controller: scroll,
          itemCount: st.route.maneuvers.length,
          itemBuilder: (_, i) {
            final m = st.route.maneuvers[i];
            final current = i == (st.update?.nextManeuverIndex ?? 0);
            return ListTile(
              selected: current,
              leading: Icon(maneuverIcon(m.type)),
              title: Text(m.instruction),
              subtitle: m.distanceM > 0 ? Text(formatDistance(m.distanceM, units)) : null,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final forceDark = _forceDark(settings);
    final brightness = forceDark == null ? MediaQuery.platformBrightnessOf(context) : (forceDark ? Brightness.dark : Brightness.light);
    final st = ref.watch(navigationControllerProvider(_args));
    ref.listen<NavState>(navigationControllerProvider(_args), (_, n) => _applyState(n));

    return DynamicColorBuilder(
      builder: (lightDyn, darkDyn) => Theme(
        data: AppTheme.build(settings, brightness, dynamicScheme: (brightness == Brightness.dark ? darkDyn : lightDyn)?.harmonized()),
        child: Builder(builder: (context) => _scaffold(context, settings, st, forceDark)),
      ),
    );
  }

  Widget _scaffold(BuildContext context, AppSettings settings, NavState st, bool? forceDark) {
    final cs = context.cs;
    final units = settings.units;
    final padding = MediaQuery.paddingOf(context);
    final u = st.update;
    final next = st.nextManeuver;
    final simple = settings.simpleDrivingMode;
    final now = DateTime.now();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmStop();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: StrasseMap(
                onReady: _onReady,
                forceDark: forceDark,
                initialTarget: st.fix?.point ?? widget.route.start,
                initialZoom: 16,
                attributionBottomPadding: 170 + padding.bottom,
              ),
            ),
            // Bannière de manœuvre.
            Positioned(
              left: 10,
              right: 10,
              top: padding.top + 8,
              child: Column(
                children: [
                  Material(
                    color: _kPanelDark,
                    elevation: 8,
                    borderRadius: BorderRadius.circular(22),
                    child: Padding(
                      padding: EdgeInsets.all(simple ? 20 : 14),
                      child: Row(
                        children: [
                          Icon(next == null ? Icons.navigation_rounded : maneuverIcon(next.type), color: Colors.white, size: simple ? 64 : 52),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  u == null ? '—' : 'Dans ${formatDistance(u.distanceToNextM, units)}',
                                  style: TextStyle(color: Colors.white, fontSize: simple ? 36 : 28, fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  next?.instruction ?? 'En attente de la position…',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: simple ? 20 : 17),
                                ),
                                if (!simple && st.thenManeuver != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        Text('Ensuite ', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                                        Icon(maneuverIcon(st.thenManeuver!.type), color: Colors.white.withOpacity(0.85), size: 16),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (st.phase == NavPhase.rerouting) const Padding(padding: EdgeInsets.only(top: 8), child: InfoBanner(icon: Icons.sync_rounded, message: 'Recalcul de l\'itinéraire…')),
                  if (st.gpsLost) const Padding(padding: EdgeInsets.only(top: 8), child: InfoBanner(icon: Icons.gps_off_rounded, tone: BannerTone.error, message: 'Signal GPS perdu : position non mise à jour.')),
                  if (!st.gpsLost && st.message != null && st.phase != NavPhase.rerouting)
                    Padding(padding: const EdgeInsets.only(top: 8), child: InfoBanner(icon: st.imprecise ? Icons.gps_not_fixed_rounded : Icons.info_outline_rounded, tone: BannerTone.warning, message: st.message!)),
                  if (st.upcomingEvent != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: InfoBanner(icon: Icons.warning_amber_rounded, tone: BannerTone.warning, message: st.upcomingEvent!, action: 'OK', onAction: () => ref.read(navigationControllerProvider(_args).notifier).clearUpcomingEvent()),
                    ),
                ],
              ),
            ),
            // Boutons latéraux.
            Positioned(
              right: 14,
              bottom: 170 + padding.bottom,
              child: Column(
                children: [
                  if (_free) _side(context, Icons.my_location_rounded, 'Recentrer', _recenter, highlighted: true),
                  if (_free) const SizedBox(height: 10),
                  _side(context, Icons.alt_route_rounded, 'Vue d\'ensemble de l\'itinéraire', _overview),
                  const SizedBox(height: 10),
                  _side(context, st.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, st.muted ? 'Réactiver la voix' : 'Couper la voix', () => ref.read(navigationControllerProvider(_args).notifier).setMuted(!st.muted)),
                  const SizedBox(height: 10),
                  _side(context, Icons.campaign_rounded, 'Signaler un événement', () async {
                    final p = st.fix?.point;
                    if (p == null) {
                      showMessage(context, 'Position inconnue : signalement impossible.');
                      return;
                    }
                    await showReportSheet(context, ref, p);
                  }),
                ],
              ),
            ),
            // Barre d'état en bas.
            Positioned(
              left: 10,
              right: 10,
              bottom: 10 + padding.bottom,
              child: Material(
                color: _kPanelDark,
                elevation: 10,
                borderRadius: BorderRadius.circular(26),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (settings.showSpeed && !simple) ...[
                            Text(st.fix == null ? '—' : formatSpeed(st.fix!.speedMps, units), style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 16),
                          ],
                          Text(
                            u == null ? 'Recherche du signal GPS…' : '${formatDuration(u.remainingS)} · ${formatDistance(u.remainingM, units)}',
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      if (u != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text('Arrivée ${formatEta(now, u.remainingS)}', style: const TextStyle(color: Colors.white60, fontSize: 13))),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Material(
                            color: Colors.white.withOpacity(0.10),
                            shape: const CircleBorder(),
                            child: IconButton(tooltip: 'Liste des étapes', icon: const Icon(Icons.list_rounded, color: Colors.white), onPressed: () => _showSteps(st)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary),
                                onPressed: _confirmStop,
                                child: const Text('Terminer'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (st.phase == NavPhase.arrived) _arrivedOverlay(context, st),
          ],
        ),
      ),
    );
  }

  Widget _side(BuildContext context, IconData icon, String tip, VoidCallback onTap, {bool highlighted = false}) => Tooltip(
        message: tip,
        child: Material(
          color: highlighted ? context.cs.primary : _kPanelDark,
          elevation: 6,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 52, height: 52, child: Icon(icon, color: Colors.white)),
          ),
        ),
      );

  Widget _arrivedOverlay(BuildContext context, NavState st) => Positioned.fill(
        child: ColoredBox(
          color: Colors.black54,
          child: Center(
            child: Card(
              margin: const EdgeInsets.all(28),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flag_circle_rounded, size: 64, color: context.sc.success),
                    const SizedBox(height: 12),
                    Text('Vous êtes arrivé', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(widget.destination.title, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Terminer')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
