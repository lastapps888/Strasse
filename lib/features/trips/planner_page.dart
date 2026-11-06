import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/app/widgets/nav_helpers.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/routing/route_options_sheet.dart';
import 'package:strasse/features/routing/route_preview_page.dart';
import 'package:strasse/features/routing/routing_service.dart';
import 'package:strasse/features/search/search_page.dart';

/// Planificateur de voyage : plusieurs étapes réordonnables, mode, options, comparaison de variantes, enregistrement.
class PlannerPage extends ConsumerStatefulWidget {
  const PlannerPage({super.key, this.trip});
  final PlannedTrip? trip;

  @override
  ConsumerState<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends ConsumerState<PlannerPage> {
  late final TextEditingController _name = TextEditingController(text: widget.trip?.name ?? '');
  late List<Place> _stops = [
    for (final w in widget.trip?.waypoints ?? const <Waypoint>[]) Place(id: 'wp:${w.point.lat},${w.point.lon}', name: w.name, point: w.point, source: 'history'),
  ];
  late TravelMode _mode = widget.trip?.mode ?? ref.read(settingsProvider).defaultMode;
  late RoutePrefs _prefs = widget.trip?.prefs ?? ref.read(settingsProvider).routePrefs;

  List<RouteVariant>? _variants;
  bool _comparing = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add({int? at}) async {
    final out = await Navigator.of(context).push<SearchOutcome>(MaterialPageRoute(builder: (_) => const SearchPage(hint: 'Ajouter une étape', showCategories: false)));
    final p = out?.place;
    if (p == null || !mounted) return;
    if (_stops.length >= 10) {
      showMessage(context, 'Dix points au maximum.');
      return;
    }
    setState(() {
      at == null ? _stops.add(p) : _stops.insert(at, p);
      _variants = null;
    });
  }

  Future<void> _addHere() async {
    final fix = ref.read(locationControllerProvider).fix ?? await ref.read(locationControllerProvider.notifier).currentFix();
    if (fix == null || !mounted) {
      if (mounted) showMessage(context, 'Position introuvable : activez la localisation.');
      return;
    }
    setState(() {
      _stops.insert(0, Place.fromCoordinates(fix.point).copyWith(name: 'Ma position'));
      _variants = null;
    });
  }

  Future<void> _compare() async {
    if (_stops.length < 2) {
      showMessage(context, 'Ajoutez au moins un départ et une arrivée.');
      return;
    }
    setState(() {
      _comparing = true;
      _error = null;
      _variants = null;
    });
    try {
      final res = await ref.read(routingServiceProvider).variants([for (final s in _stops) s.point], _mode, _prefs);
      if (!mounted) return;
      setState(() {
        _variants = res;
        _comparing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = toFailure(e).message;
        _comparing = false;
      });
    }
  }

  Future<void> _save() async {
    if (_stops.length < 2) {
      showMessage(context, 'Ajoutez au moins un départ et une arrivée.');
      return;
    }
    final name = _name.text.trim().isEmpty ? '${_stops.first.title} → ${_stops.last.title}' : _name.text.trim();
    await ref.read(dataActionsProvider).savePlannedTrip(PlannedTrip(
          id: widget.trip?.id ?? '',
          name: name,
          mode: _mode,
          waypoints: [for (final s in _stops) Waypoint(name: s.title, point: s.point)],
          prefs: _prefs,
          updatedAt: DateTime.now().toUtc(),
        ));
    if (mounted) {
      showMessage(context, 'Voyage enregistré.');
      Navigator.of(context).pop();
    }
  }

  void _open() {
    if (_stops.length < 2) {
      showMessage(context, 'Ajoutez au moins un départ et une arrivée.');
      return;
    }
    pushPage(
      context,
      RoutePreviewPage(
        origin: _stops.first,
        destination: _stops.last,
        via: _stops.sublist(1, _stops.length - 1),
        mode: _mode,
        prefs: _prefs,
        plannedTripId: widget.trip?.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(settingsProvider.select((s) => s.units));
    final cs = context.cs;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.trip == null ? 'Nouveau voyage' : 'Voyage planifié'),
        actions: [TextButton(onPressed: _save, child: const Text('Enregistrer'))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(controller: _name, maxLength: 60, decoration: const InputDecoration(hintText: 'Nom du voyage (facultatif)')),
          ),
          const SectionTitle('Mode de déplacement'),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final m in TravelMode.values.where((m) => m != TravelMode.transit))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(avatar: Icon(m.icon, size: 18), label: Text(m.label), selected: _mode == m, onSelected: (_) => setState(() {
                          _mode = m;
                          _variants = null;
                        })),
                  ),
              ],
            ),
          ),
          SectionTitle('Étapes', trailing: TextButton.icon(onPressed: _addHere, icon: const Icon(Icons.my_location_rounded, size: 18), label: const Text('Ma position'))),
          if (_stops.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Ajoutez un départ, des étapes et une arrivée.')),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (o, n) => setState(() {
              if (n > o) n--;
              _stops.insert(n, _stops.removeAt(o));
              _variants = null;
            }),
            children: [
              for (var i = 0; i < _stops.length; i++)
                ListTile(
                  key: ValueKey('${_stops[i].id}#$i'),
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: i == 0 ? context.sc.success : (i == _stops.length - 1 ? context.sc.danger : cs.primary),
                    child: Text(i == 0 ? 'A' : (i == _stops.length - 1 ? 'B' : '$i'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  title: Text(_stops[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: _stops[i].subtitle == null ? null : Text(_stops[i].subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: 'Retirer', icon: const Icon(Icons.close_rounded), onPressed: () => setState(() {
                          _stops.removeAt(i);
                          _variants = null;
                        })),
                    ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle_rounded)),
                  ]),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(onPressed: () => _add(), icon: const Icon(Icons.add_location_alt_outlined), label: const Text('Ajouter un point')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final r = await showRouteOptionsSheet(context, mode: _mode, prefs: _prefs);
                      if (r != null && mounted) setState(() {
                        _prefs = r;
                        _variants = null;
                      });
                    },
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Options'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: FilledButton.tonalIcon(onPressed: _comparing ? null : _compare, icon: const Icon(Icons.compare_arrows_rounded), label: const Text('Comparer'))),
              ],
            ),
          ),
          if (_comparing) const Padding(padding: EdgeInsets.all(24), child: LoadingView(label: 'Calcul des variantes…')),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: InfoBanner(icon: Icons.error_outline_rounded, tone: BannerTone.error, message: _error!)),
          if (_variants != null) ...[
            const SectionTitle('Variantes'),
            for (final v in _variants!)
              ListTile(
                leading: IconBadge(icon: v.route == null ? Icons.block_rounded : Icons.route_rounded, color: v.route == null ? cs.error : null),
                title: Text(v.label),
                subtitle: Text(v.route == null ? (v.error?.message ?? 'Indisponible') : '${formatDuration(v.route!.durationS)} · ${formatDistance(v.route!.distanceM, units)}${v.route!.hasToll ? ' · péages' : ''}${v.route!.hasHighway ? ' · autoroute' : ''}'),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SizedBox(height: 52, child: FilledButton.icon(onPressed: _open, icon: const Icon(Icons.map_rounded), label: const Text('Voir l\'itinéraire et démarrer'))),
          ),
        ],
      ),
    );
  }
}
