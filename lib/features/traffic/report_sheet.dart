import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';

/// Choix du type de signalement puis envoi anonyme au serveur Strasse.
/// Seuls le type et la position sont envoyés (avec l'identifiant anonyme d'installation, jamais le compte).
Future<bool> showReportSheet(BuildContext context, WidgetRef ref, GeoPoint point) async {
  final api = ref.read(strasseApiProvider);
  if (!api.configured) {
    showMessage(context, 'Les signalements nécessitent un serveur Strasse (Réglages > Services). Cette fonction est facultative.');
    return false;
  }
  final type = await showModalBottomSheet<ReportType>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Signaler un événement', style: ctx.tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Anonyme : seuls le type et la position sont transmis.', style: ctx.tt.bodySmall?.copyWith(color: ctx.cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.05,
              children: [
                for (final t in ReportType.values)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.pop(ctx, t),
                    child: Ink(
                      decoration: BoxDecoration(color: t.color.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(t.icon, color: t.color, size: 30),
                          const SizedBox(height: 6),
                          Text(t.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (type == null || !context.mounted) return false;
  try {
    final res = await api.createReport(type, point);
    ref.read(trafficProvider.notifier).addReport(res.report);
    if (context.mounted) {
      showMessage(context, res.merged ? 'Merci : un signalement identique existait, il a été confirmé.' : 'Merci, votre signalement a été envoyé.');
    }
    return true;
  } catch (e) {
    if (context.mounted) showMessage(context, toFailure(e).message);
    return false;
  }
}

/// Détail d'un signalement ou incident, avec confirmation / « n'est plus là ».
class EventSheet extends ConsumerStatefulWidget {
  const EventSheet({super.key, required this.event});
  final MapEvent event;

  @override
  ConsumerState<EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends ConsumerState<EventSheet> {
  bool _busy = false;
  CommunityReport? _updated;

  Future<void> _vote(bool confirm) async {
    final r = widget.event.report!;
    setState(() => _busy = true);
    try {
      final api = ref.read(strasseApiProvider);
      final res = confirm ? await api.confirmReport(r.id) : await api.rejectReport(r.id);
      ref.read(trafficProvider.notifier).replaceReport(res);
      if (mounted) {
        setState(() {
          _updated = res;
          _busy = false;
        });
        showMessage(context, 'Merci pour votre retour.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, toFailure(e).message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final r = _updated ?? e.report;
    final i = e.incident;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: e.type.icon, color: e.type.color, size: 48, iconSize: 26),
              const SizedBox(width: 14),
              Expanded(child: Text(e.type.label, style: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 12),
          if (r != null) ...[
            Text('Signalement de la communauté · ${r.reliabilityLabel}', style: context.tt.bodyMedium),
            const SizedBox(height: 4),
            Text('Signalé ${formatRelative(DateTime.now(), r.createdAt)} · ${r.confirmations} confirmation(s) · ${r.rejections} « n\'est plus là »', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('Information non vérifiée : à confirmer sur place, en respectant le code de la route.', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: FilledButton.tonalIcon(onPressed: _busy ? null : () => _vote(true), icon: const Icon(Icons.check_rounded), label: const Text('Toujours là'))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _vote(false), icon: const Icon(Icons.close_rounded), label: const Text('Plus là'))),
              ],
            ),
          ],
          if (i != null) ...[
            Text('Incident fourni par ${i.source}', style: context.tt.bodyMedium),
            if (i.description != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(i.description!)),
            if (i.delayMinutes != null && i.delayMinutes! > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Retard estimé : ${i.delayMinutes} min')),
            if (i.endTime != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Fin prévue : ${formatDate(i.endTime!)} ${formatClock(i.endTime!)}')),
          ],
        ],
      ),
    );
  }
}
