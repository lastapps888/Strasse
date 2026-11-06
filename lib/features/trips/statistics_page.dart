import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';

/// Statistiques personnelles, calculées localement à partir de l'historique. Rien n'est envoyé.
class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(settingsProvider.select((s) => s.units));
    final async = ref.watch(tripStatsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(tripStatsProvider)),
        data: (s) {
          if (s.tripCount == 0) {
            return const EmptyView(icon: Icons.insights_rounded, title: 'Pas encore de statistiques', message: 'Elles se construisent à partir des trajets enregistrés dans l\'historique, sur votre appareil uniquement.');
          }
          final maxWeek = s.weekly.fold<double>(0, (a, b) => b > a ? b : a);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(child: _kpi(context, 'Trajets', '${s.tripCount}', Icons.route_rounded)),
                  const SizedBox(width: 12),
                  Expanded(child: _kpi(context, 'Distance', formatDistance(s.totalDistanceM, units), Icons.straighten_rounded)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _kpi(context, 'Temps', formatDuration(s.totalDurationS), Icons.schedule_rounded)),
                  const SizedBox(width: 12),
                  Expanded(child: _kpi(context, 'Moyenne', formatDistance(s.averageDistanceM, units), Icons.timeline_rounded)),
                ],
              ),
              const SectionTitle('Distance par semaine (8 dernières)', padding: EdgeInsets.fromLTRB(4, 24, 4, 8)),
              SizedBox(
                height: 140,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < s.weekly.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Tooltip(
                                message: formatDistance(s.weekly[i], units),
                                child: Container(
                                  height: maxWeek == 0 ? 2 : (s.weekly[i] / maxWeek * 110).clamp(2.0, 110.0),
                                  decoration: BoxDecoration(color: context.cs.primary, borderRadius: BorderRadius.circular(6)),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(i == s.weekly.length - 1 ? 'Cette sem.' : '-${s.weekly.length - 1 - i}', style: const TextStyle(fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SectionTitle('Par mode', padding: EdgeInsets.fromLTRB(4, 24, 4, 8)),
              for (final e in s.byMode.entries)
                ListTile(contentPadding: EdgeInsets.zero, leading: IconBadge(icon: e.key.icon), title: Text(e.key.label), trailing: Text(formatDistance(e.value, units), style: const TextStyle(fontWeight: FontWeight.w700))),
              if (s.topDestinations.isNotEmpty) ...[
                const SectionTitle('Destinations les plus fréquentes', padding: EdgeInsets.fromLTRB(4, 24, 4, 8)),
                for (final d in s.topDestinations)
                  ListTile(contentPadding: EdgeInsets.zero, leading: const IconBadge(icon: Icons.place_rounded), title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: Text('${d.count}×')),
              ],
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () async {
                  final ok = await confirm(context, title: 'Effacer l\'historique ?', message: 'Les statistiques sont calculées à partir de l\'historique : elles seront remises à zéro.', confirmLabel: 'Effacer');
                  if (ok) await ref.read(dataActionsProvider).clearHistory();
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Effacer l\'historique et les statistiques'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _kpi(BuildContext context, String label, String value, IconData icon) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: context.cs.primary),
              const SizedBox(height: 10),
              Text(value, style: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text(label, style: context.tt.bodySmall),
            ],
          ),
        ),
      );
}
