import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/app/widgets/nav_helpers.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/routing/route_preview_page.dart';
import 'package:strasse/features/trips/planner_page.dart';
import 'package:strasse/features/trips/statistics_page.dart';

/// Onglet Trajets : historique, voyages planifiés, accès aux statistiques.
class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  bool get _reduce => ref.read(settingsProvider).reduceAnimations;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final statsOn = ref.watch(settingsProvider.select((s) => s.statsEnabled && s.historyEnabled));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trajets'),
        actions: [
          if (statsOn) IconButton(tooltip: 'Statistiques', icon: const Icon(Icons.insights_rounded), onPressed: () => pushPage(context, const StatisticsPage(), reduce: _reduce)),
        ],
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Historique'), Tab(text: 'Planifiés')]),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) => _tabs.index == 1
            ? Padding(
                padding: EdgeInsets.only(bottom: 80 + padding.bottom),
                child: FloatingActionButton.extended(
                  onPressed: () => pushPage(context, const PlannerPage(), reduce: _reduce),
                  icon: const Icon(Icons.add_road_rounded),
                  label: const Text('Planifier un voyage'),
                ),
              )
            : const SizedBox.shrink(),
      ),
      body: TabBarView(controller: _tabs, children: [_history(context, padding), _planned(context, padding)]),
    );
  }

  Widget _history(BuildContext context, EdgeInsets padding) {
    final historyOn = ref.watch(settingsProvider.select((s) => s.historyEnabled));
    final units = ref.watch(settingsProvider.select((s) => s.units));
    final async = ref.watch(historyProvider(_query));
    return Column(
      children: [
        if (!historyOn)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: InfoBanner(icon: Icons.history_toggle_off_rounded, message: 'L\'historique est désactivé : les nouveaux trajets ne sont pas enregistrés. Vous pouvez le réactiver dans Réglages > Confidentialité.'),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              hintText: 'Rechercher dans l\'historique',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() {
                    _search.clear();
                    _query = '';
                  })),
            ),
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(historyProvider(_query))),
            data: (trips) {
              if (trips.isEmpty) {
                return EmptyView(
                  icon: Icons.history_rounded,
                  title: _query.isEmpty ? 'Aucun trajet enregistré' : 'Aucun résultat',
                  message: _query.isEmpty ? 'Vos trajets terminés apparaîtront ici. Ils restent sur votre appareil.' : 'Aucun trajet ne correspond à « $_query ».',
                );
              }
              return ListView.builder(
                padding: EdgeInsets.only(bottom: 120 + padding.bottom),
                itemCount: trips.length + 1,
                itemBuilder: (context, i) {
                  if (i == trips.length) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextButton.icon(
                        onPressed: () async {
                          final ok = await confirm(context, title: 'Effacer tout l\'historique ?', message: 'Tous les trajets enregistrés seront supprimés de cet appareil. Cette action est définitive.', confirmLabel: 'Tout effacer');
                          if (ok) await ref.read(dataActionsProvider).clearHistory();
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Effacer l\'historique'),
                      ),
                    );
                  }
                  final t = trips[i];
                  return Dismissible(
                    key: ValueKey(t.id),
                    direction: DismissDirection.endToStart,
                    background: Container(color: context.cs.error, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24), child: Icon(Icons.delete_rounded, color: context.cs.onError)),
                    onDismissed: (_) => ref.read(dataActionsProvider).deleteTrip(t.id),
                    child: ListTile(
                      leading: IconBadge(icon: t.mode.icon),
                      title: Text(t.toName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${formatDate(t.startedAt)} · ${formatDistance(t.distanceM, units)} · ${formatDuration(t.durationS)}${t.completed ? '' : ' · interrompu'}'),
                      trailing: IconButton(
                        tooltip: 'Refaire ce trajet',
                        icon: const Icon(Icons.replay_rounded),
                        onPressed: () => pushPage(context, RoutePreviewPage(destination: Place(id: 'history:${t.id}', name: t.toName, point: t.to, source: 'history'), mode: t.mode), reduce: _reduce),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _planned(BuildContext context, EdgeInsets padding) {
    final async = ref.watch(plannedTripsProvider);
    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(plannedTripsProvider)),
      data: (trips) {
        if (trips.isEmpty) {
          return const EmptyView(
            icon: Icons.alt_route_rounded,
            title: 'Aucun voyage planifié',
            message: 'Créez un voyage avec plusieurs étapes, comparez les variantes (plus rapide, sans péages…) puis lancez le guidage quand vous êtes prêt.',
          );
        }
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(0, 8, 0, 160 + padding.bottom),
          itemCount: trips.length,
          itemBuilder: (context, i) {
            final t = trips[i];
            return Dismissible(
              key: ValueKey(t.id),
              direction: DismissDirection.endToStart,
              background: Container(color: context.cs.error, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24), child: Icon(Icons.delete_rounded, color: context.cs.onError)),
              confirmDismiss: (_) => confirm(context, title: 'Supprimer « ${t.name} » ?', message: 'Ce voyage planifié sera supprimé.'),
              onDismissed: (_) => ref.read(dataActionsProvider).deletePlannedTrip(t.id),
              child: ListTile(
                leading: IconBadge(icon: t.mode.icon),
                title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${t.waypoints.length} points · ${t.waypoints.first.name} → ${t.waypoints.last.name}', maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => pushPage(context, PlannerPage(trip: t), reduce: _reduce),
              ),
            );
          },
        );
      },
    );
  }
}
