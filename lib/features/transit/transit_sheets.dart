import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/transit/transit_style.dart';

/// Fiche d'un arrêt : prochains passages par ligne, avec le temps réel quand l'opérateur le publie.
class StopSheet extends ConsumerStatefulWidget {
  const StopSheet({super.key, required this.stop});
  final TransitStop stop;

  @override
  ConsumerState<StopSheet> createState() => _StopSheetState();
}

class _StopSheetState extends ConsumerState<StopSheet> {
  List<StopDeparture>? _deps;
  Object? _error;
  final CancelToken _cancel = CancelToken();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final motis = ref.read(transitDataProvider).motis;
    setState(() {
      _deps = null;
      _error = null;
    });
    if (motis == null) {
      setState(() => _error = const Failure(FailureKind.notConfigured, 'Les horaires nécessitent Transitous (MOTIS). Choisissez-le dans Réglages > Services > Transports en commun.'));
      return;
    }
    try {
      final d = await motis.departures(widget.stop.id, cancel: _cancel);
      if (mounted) setState(() => _deps = d);
    } catch (e) {
      if (mounted && !(e is DioException && CancelToken.isCancel(e))) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final deps = _deps;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(transitModeIcon(widget.stop.modes.isEmpty ? 'bus' : widget.stop.modes.first), color: cs.primary),
              title: Text(widget.stop.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(widget.stop.modes.isEmpty ? 'Arrêt' : widget.stop.modes.map(transitModeLabel).toSet().join(' · ')),
              trailing: IconButton(tooltip: tr('Actualiser'), icon: const Icon(Icons.refresh_rounded), onPressed: _load),
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: InfoBanner(icon: Icons.error_outline_rounded, tone: BannerTone.error, message: toFailure(_error!).message))
            else if (deps == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (deps.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('Aucun passage prévu prochainement à cet arrêt. Certains opérateurs ne publient pas leurs horaires.'))
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: deps.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _DepartureTile(dep: deps[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DepartureTile extends StatelessWidget {
  const _DepartureTile({required this.dep});
  final StopDeparture dep;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final mins = dep.best.difference(DateTime.now()).inMinutes;
    final late = dep.delay.inMinutes;
    final when = dep.cancelled ? 'Supprimé' : (mins <= 0 ? 'À l\'instant' : (mins < 60 ? '$mins min' : formatClock(dep.best)));
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: transitModeColor(dep.mode),
        child: Text(dep.routeName.isEmpty ? '·' : dep.routeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
      ),
      title: Text(dep.headsign ?? transitModeLabel(dep.mode), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([
        transitModeLabel(dep.mode),
        if (dep.agency != null) dep.agency!,
        if (dep.realTime) (late > 0 ? 'retard $late min' : 'à l\'heure'),
      ].join(' · ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(when, style: TextStyle(fontWeight: FontWeight.w800, color: dep.cancelled ? cs.error : cs.onSurface, decoration: dep.cancelled ? TextDecoration.lineThrough : null)),
          Text(formatClock(dep.best), style: context.tt.bodySmall),
        ],
      ),
    );
  }
}

/// Fiche d'une ligne touchée sur la carte.
class LineSheet extends StatelessWidget {
  const LineSheet({super.key, required this.line});
  final TransitLine line;

  @override
  Widget build(BuildContext context) {
    final color = transitModeColor(line.mode);
    final route = [if (line.from != null) line.from!, if (line.to != null) line.to!].join(' → ');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(backgroundColor: color, child: Icon(transitModeIcon(line.mode), color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(child: Text('${transitModeLabel(line.mode)} ${line.ref}'.trim(), style: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            ]),
            if (line.name != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(line.name!)),
            if (route.isNotEmpty && route != line.name) Padding(padding: const EdgeInsets.only(top: 6), child: Text(route)),
            if (line.operator != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Exploitant : ${line.operator}', style: context.tt.bodySmall)),
            const SizedBox(height: 12),
            Text('Touchez un arrêt de la carte (en zoomant) pour voir ses prochains passages. Tracé d\'après OpenStreetMap.', style: context.tt.bodySmall),
          ],
        ),
      ),
    );
  }
}
