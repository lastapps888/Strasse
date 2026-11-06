import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/app/widgets/nav_helpers.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/assistant/assistant_engine.dart';
import 'package:strasse/features/routing/route_preview_page.dart';
import 'package:strasse/features/search/search_page.dart';
import 'package:strasse/features/trips/planner_page.dart';

/// Assistant local : comprend des phrases simples, les reformule, puis prépare une recherche ou un itinéraire.
/// Il fonctionne sans réseau pour l'interprétation et ne transmet rien ; la recherche de lieux utilise ensuite le géocodeur configuré.
class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key});

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  final _controller = TextEditingController();
  AssistantIntent? _intent;
  bool _busy = false;
  String? _error;

  static const _examples = [
    'Je veux rejoindre Lyon sans péages',
    'Trouve-moi une station-service',
    'Je veux faire une pause',
    'Itinéraire à vélo vers la gare',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _interpret(String text) {
    setState(() {
      _intent = ref.read(assistantProvider).interpret(text);
      _error = null;
    });
  }

  Future<Place?> _resolve(String query) async {
    final geocoder = ref.read(geocoderProvider);
    final here = ref.read(locationControllerProvider).fix?.point;
    final res = await geocoder.search(query, near: here, limit: 5);
    if (res.isEmpty) throw Failure(FailureKind.client, 'Aucun lieu trouvé pour « $query ».');
    return res.first;
  }

  Future<void> _run() async {
    final i = _intent;
    if (i == null) return;
    final settings = ref.read(settingsProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (i.action) {
        case AssistantAction.navigate:
          final dest = await _resolve(i.query!);
          if (!mounted || dest == null) return;
          await pushPage(context, RoutePreviewPage(destination: dest, mode: i.mode ?? settings.defaultMode, prefs: i.applyTo(settings.routePrefs)));
        case AssistantAction.searchPlace:
          final out = await Navigator.of(context).push<SearchOutcome>(MaterialPageRoute(builder: (_) => const SearchPage()));
          if (out?.place != null && mounted) {
            ref.read(mapFocusProvider.notifier).state = MapFocus(place: out!.place!);
            ref.read(shellIndexProvider.notifier).state = 1;
            Navigator.of(context).pop();
          }
        case AssistantAction.searchCategory:
          final here = ref.read(locationControllerProvider).fix?.point ?? ref.read(mapViewportProvider)?.center;
          if (here == null) throw const Failure(FailureKind.permission, 'Position inconnue : activez la localisation pour chercher autour de vous.');
          final res = await ref.read(geocoderProvider).search(i.category!.query, bounds: GeoBounds.around(here, 5000), bounded: true, limit: 20);
          if (res.isEmpty) throw Failure(FailureKind.client, 'Aucun résultat « ${i.category!.label} » à proximité.');
          ref.read(mapResultsProvider.notifier).state = res;
          ref.read(shellIndexProvider.notifier).state = 1;
          if (mounted) Navigator.of(context).pop();
        case AssistantAction.planTrip:
          if (i.waypointQueries.length >= 2) {
            final places = <Place>[];
            for (final q in i.waypointQueries) {
              final p = await _resolve(q);
              if (p != null) places.add(p);
            }
            if (!mounted) return;
            await pushPage(
              context,
              RoutePreviewPage(origin: places.first, destination: places.last, via: places.sublist(1, places.length - 1), mode: i.mode ?? settings.defaultMode, prefs: i.applyTo(settings.routePrefs)),
            );
          } else {
            await pushPage(context, const PlannerPage());
          }
        case AssistantAction.unknown:
          break;
      }
    } catch (e) {
      if (mounted) setState(() => _error = toFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = _intent;
    return Scaffold(
      appBar: AppBar(title: const Text('Assistant')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const InfoBanner(
            icon: Icons.shield_outlined,
            message: 'Cet assistant fonctionne sur votre appareil, avec des règles simples : il ne comprend que des demandes de déplacement ou de recherche de lieux, et n\'envoie votre phrase nulle part.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.go,
            onSubmitted: _interpret,
            decoration: InputDecoration(hintText: 'Que voulez-vous faire ?', suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: () => _interpret(_controller.text))),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final e in _examples)
                ActionChip(
                  label: Text(e),
                  onPressed: () {
                    _controller.text = e;
                    _interpret(e);
                  },
                ),
            ],
          ),
          if (i != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.summary, style: context.tt.titleMedium),
                    if (i.action != AssistantAction.unknown) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(onPressed: _busy ? null : _run, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded), label: const Text('Lancer')),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: InfoBanner(icon: Icons.error_outline_rounded, tone: BannerTone.error, message: _error!)),
        ],
      ),
    );
  }
}
