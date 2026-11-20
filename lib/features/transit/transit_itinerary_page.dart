import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/core/i18n/translator.dart';
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/location/location_service.dart';
import 'package:strasse/features/map/strasse_map.dart';
import 'package:strasse/features/settings/settings_model.dart';
import 'package:strasse/features/sharing/share_service.dart';
import 'package:strasse/features/transit/transit_style.dart' show transitModeIcon;

/// Couleur `#RRGGBB` publiée par le flux GTFS, ou null.
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// Pastille de ligne aux couleurs officielles du réseau (couleur du flux GTFS ; à défaut, couleur neutre du mode).
class LineBadge extends StatelessWidget {
  const LineBadge({super.key, required this.mode, required this.name, this.color, this.textColor});
  final String mode;
  final String name;
  final String? color;
  final String? textColor;

  @override
  Widget build(BuildContext context) {
    final bg = parseHexColor(color) ?? context.cs.primary;
    final fg = parseHexColor(textColor) ?? (bg.computeLuminance() > 0.5 ? Colors.black : Colors.white);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(transitModeIcon(mode), size: 15, color: fg),
        if (name.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(name, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ]),
    );
  }
}

/// Détail d'un trajet en transports en commun : lignes, arrêts, horaires, correspondances, marche, départ et arrivée.
/// En mode « suivi », la page indique l'étape en cours d'après l'heure et votre position réelle.
class TransitItineraryPage extends ConsumerStatefulWidget {
  const TransitItineraryPage({super.key, required this.itinerary, required this.origin, required this.destination, this.follow = false});
  final TransitItinerary itinerary;
  final Place? origin;
  final Place destination;
  final bool follow;

  @override
  ConsumerState<TransitItineraryPage> createState() => _TransitItineraryPageState();
}

class _TransitItineraryPageState extends ConsumerState<TransitItineraryPage> {
  StrasseMapController? _map;
  late bool _following = widget.follow;
  Timer? _tick;
  final Set<int> _expanded = {};

  TransitItinerary get _it => widget.itinerary;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && _following) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Color _legColor(TransitLeg leg) => leg.isWalk ? Colors.grey : (parseHexColor(leg.routeColor) ?? Color(ref.read(settingsProvider).routeColor));

  void _draw() {
    final c = _map;
    if (c == null) return;
    final s = ref.read(settingsProvider);
    c.setPins([
      MapPin(id: 'origin', point: _it.legs.first.from, color: context.sc.success, radius: 8),
      for (var i = 0; i < _it.legs.length; i++)
        if (!_it.legs[i].isWalk) ...[
          MapPin(id: 'board$i', point: _it.legs[i].from, color: _legColor(_it.legs[i]), radius: 6),
          MapPin(id: 'alight$i', point: _it.legs[i].to, color: _legColor(_it.legs[i]), radius: 6),
        ],
      MapPin(id: 'dest', point: _it.legs.last.to, color: Color(s.markerColor), radius: 10),
    ]);
    c.setExtraLines([
      for (final leg in _it.legs) MapPolyline(points: leg.shape.length >= 2 ? leg.shape : [leg.from, leg.to], color: _legColor(leg), width: leg.isWalk ? 4 : 7, dashed: leg.isWalk),
    ]);
    c.fitPoints(_it.shape, top: 120, bottom: MediaQuery.sizeOf(context).height * 0.45, left: 40, right: 40);
  }

  /// Index du tronçon en cours (ou à venir) selon l'heure.
  int _currentLeg(DateTime now) {
    for (var i = 0; i < _it.legs.length; i++) {
      if (now.isBefore(_it.legs[i].end)) return i;
    }
    return _it.legs.length - 1;
  }

  String _timeLabel(DateTime t, {DateTime? scheduled, bool real = false}) {
    final late = scheduled != null && t.difference(scheduled).inMinutes != 0;
    return late ? '${formatClock(t)} (${tr('prévu')} ${formatClock(scheduled)})' : formatClock(t);
  }

  String _nextAction(DateTime now) {
    final i = _currentLeg(now);
    final leg = _it.legs[i];
    if (now.isAfter(_it.end)) return tr('Vous êtes arrivé à destination.');
    if (leg.isWalk) {
      return '${tr('Marchez')} ${formatDuration(leg.duration.inSeconds.toDouble())} ${tr('jusqu’à')} ${leg.toName}';
    }
    final line = '${transitModeLabel(leg.mode)} ${leg.routeName ?? ''}'.trim();
    if (now.isBefore(leg.start)) {
      final mins = leg.start.difference(now).inMinutes;
      return '${tr('Prenez')} $line ${tr('à')} ${leg.fromName} · ${mins <= 0 ? tr('maintenant') : '${tr('dans')} $mins min'}';
    }
    return '${tr('Restez dans')} $line ${tr('jusqu’à')} ${leg.toName} (${formatClock(leg.end)})';
  }

  Future<void> _share() {
    final origin = widget.origin;
    final first = _it.legs.first.from;
    final summary = StringBuffer('${formatClock(_it.start)} → ${formatClock(_it.end)} · ${formatDuration(_it.duration.inSeconds.toDouble())}');
    for (final l in _it.legs.where((l) => !l.isWalk)) {
      summary.write('\n${transitModeLabel(l.mode)} ${l.routeName ?? ''} ${formatClock(l.start)} ${l.fromName} → ${formatClock(l.end)} ${l.toName}');
    }
    return ShareService.shareRoute(
      context,
      originLabel: origin?.title ?? tr('Ma position'),
      destinationLabel: widget.destination.title,
      from: origin?.point ?? first,
      to: widget.destination.point,
      mode: TravelMode.transit,
      summary: summary.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final now = DateTime.now();
    final cur = _currentLeg(now);
    // Position réelle (si elle est déjà connue) : sert à signaler que l'on s'éloigne du trajet prévu.
    final fix = ref.watch(locationControllerProvider).fix;
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: StrasseMap(
            onReady: (c) {
              _map = c;
              _draw();
              final f = ref.read(locationControllerProvider).fix;
              if (f != null) c.setUser(f.point, accuracy: f.accuracyM, color: ref.read(settingsProvider).primary);
            },
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                IconButton.filledTonal(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back_rounded), tooltip: tr('Retour')),
                const Spacer(),
                IconButton.filledTonal(onPressed: _share, icon: const Icon(Icons.ios_share_rounded), tooltip: tr('Partager l’itinéraire')),
              ]),
            ),
          ),
        ),
        if (_following)
          Positioned(
            top: 0,
            left: 64,
            right: 64,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Material(
                  elevation: 3,
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Icon(transitModeIcon(_it.legs[cur].mode), color: cs.onPrimaryContainer),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_nextAction(now), style: TextStyle(fontWeight: FontWeight.w700, color: cs.onPrimaryContainer))),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        DraggableScrollableSheet(
          initialChildSize: 0.42,
          minChildSize: 0.16,
          maxChildSize: 0.92,
          builder: (ctx, scroll) => Material(
            color: cs.surface,
            elevation: 8,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 12),
                Text('${formatClock(_it.start)} → ${formatClock(_it.end)}', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text('${formatDuration(_it.duration.inSeconds.toDouble())} · ${_it.transfers} ${tr('correspondance(s)')} · ${formatDistance(_it.walkDistanceM)} ${tr('à pied')}', style: context.tt.bodyMedium),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  for (final l in _it.legs)
                    if (l.isWalk) Icon(Icons.directions_walk_rounded, size: 18, color: cs.onSurfaceVariant) else LineBadge(mode: l.mode, name: l.routeName ?? '', color: l.routeColor, textColor: l.routeTextColor),
                ]),
                const SizedBox(height: 10),
                _realtimeNote(context),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    setState(() => _following = !_following);
                    if (_following) _map?.fitPoints(_it.legs[_currentLeg(DateTime.now())].shape, top: 160, bottom: MediaQuery.sizeOf(context).height * 0.45);
                  },
                  icon: Icon(_following ? Icons.stop_rounded : Icons.play_arrow_rounded),
                  label: Text(_following ? 'Arrêter le suivi' : 'Démarrer le trajet'),
                ),
                if (_following && fix != null && distanceM(fix.point, _it.legs[cur].isWalk ? _it.legs[cur].to : _it.legs[cur].from) > 3000 && now.isBefore(_it.legs[cur].start))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Vous êtes à plus de 3 km du prochain point de montée.', style: TextStyle(color: cs.error, fontSize: 12.5)),
                  ),
                const SizedBox(height: 12),
                for (var i = 0; i < _it.legs.length; i++) _legTile(context, i, i == cur && _following),
                _endpoint(context, Icons.flag_rounded, widget.destination.title, tr('Arrivée'), _it.end),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _realtimeNote(BuildContext context) {
    final real = _it.legs.any((l) => !l.isWalk && l.realTime);
    final allReal = _it.legs.where((l) => !l.isWalk).every((l) => l.realTime);
    final text = real ? (allReal ? 'Horaires en temps réel (flux de l’opérateur).' : 'Temps réel sur une partie du trajet ; les autres horaires sont théoriques.') : 'Horaires théoriques (plan de service) : aucun temps réel publié pour ce trajet.';
    return Row(children: [
      Icon(real ? Icons.sensors_rounded : Icons.schedule_rounded, size: 16, color: real ? context.sc.success : context.cs.onSurfaceVariant),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
    ]);
  }

  Widget _endpoint(BuildContext context, IconData icon, String name, String label, DateTime t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, color: context.cs.primary),
          const SizedBox(width: 12),
          Expanded(child: Text('$label · $name', style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(formatClock(t), style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _legTile(BuildContext context, int i, bool current) {
    final cs = context.cs;
    final leg = _it.legs[i];
    final color = _legColor(leg);
    final prev = i > 0 ? _it.legs[i - 1] : null;
    final transferWait = prev != null && !prev.isWalk && !leg.isWalk ? leg.start.difference(prev.end) : null;
    final expanded = _expanded.contains(i);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: current ? cs.primaryContainer.withOpacity(0.5) : cs.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 5)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (transferWait != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('${tr('Correspondance')} · ${tr('attente')} ${formatDuration(transferWait.inSeconds.abs().toDouble())}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
        if (leg.isWalk) ...[
          Row(children: [
            Icon(Icons.directions_walk_rounded, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(child: Text('${tr('Marche')} ${formatDuration(leg.duration.inSeconds.toDouble())} · ${formatDistance(leg.distanceM)}', style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(formatClock(leg.start)),
          ]),
          Padding(padding: const EdgeInsets.only(left: 34, top: 2), child: Text('${tr('vers')} ${leg.toName}', style: const TextStyle(fontSize: 13))),
        ] else ...[
          Row(children: [
            LineBadge(mode: leg.mode, name: leg.routeName ?? '', color: leg.routeColor, textColor: leg.routeTextColor),
            const SizedBox(width: 8),
            Expanded(child: Text(leg.headsign == null ? transitModeLabel(leg.mode) : '${tr('direction')} ${leg.headsign}', style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
          if (leg.cancelled) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Ce passage est supprimé par l’opérateur.', style: TextStyle(color: cs.error, fontWeight: FontWeight.w700))),
          const SizedBox(height: 8),
          _stopLine(context, leg.fromName, _timeLabel(leg.start, scheduled: leg.scheduledStart), track: leg.fromTrack, color: color),
          if (leg.intermediateStops.isNotEmpty)
            InkWell(
              onTap: () => setState(() => expanded ? _expanded.remove(i) : _expanded.add(i)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(children: [
                  Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
                  const SizedBox(width: 6),
                  Text('${leg.intermediateStops.length} ${tr('arrêt(s) intermédiaire(s)')} · ${formatDuration(leg.duration.inSeconds.toDouble())}', style: const TextStyle(fontSize: 13)),
                ]),
              ),
            ),
          if (expanded)
            for (final s in leg.intermediateStops)
              _stopLine(context, s.name, s.time == null ? '' : _timeLabel(s.time!, scheduled: s.scheduledTime), track: s.track, color: color, small: true),
          _stopLine(context, leg.toName, _timeLabel(leg.end, scheduled: leg.scheduledEnd), track: leg.toTrack, color: color),
          if (leg.agency != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(leg.agency!, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant))),
        ],
      ]),
    );
  }

  Widget _stopLine(BuildContext context, String name, String time, {String? track, required Color color, bool small = false}) => Padding(
        padding: EdgeInsets.symmetric(vertical: small ? 2 : 3),
        child: Row(children: [
          Container(width: small ? 7 : 11, height: small ? 7 : 11, margin: EdgeInsets.symmetric(horizontal: small ? 2 : 0), decoration: BoxDecoration(color: small ? color.withOpacity(0.6) : color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(track == null ? name : '$name · ${tr('quai/voie')} $track', style: TextStyle(fontSize: small ? 12.5 : 14, fontWeight: small ? FontWeight.w400 : FontWeight.w600))),
          if (time.isNotEmpty) Text(time, style: TextStyle(fontSize: small ? 12 : 13.5)),
        ]),
      );
}
