import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/routing/route_options_sheet.dart';
import 'package:strasse/features/settings/settings_model.dart';
import 'package:strasse/features/settings/settings_widgets.dart';

// ------------------------------------------------------------------------------------ Apparence

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final c = ref.read(settingsProvider.notifier);
    return SettingsPageScaffold(
      title: 'Apparence',
      children: [
        const SectionTitle('Thème'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('Système'), icon: Icon(Icons.brightness_auto_rounded)),
              ButtonSegment(value: ThemeMode.light, label: Text('Clair'), icon: Icon(Icons.light_mode_rounded)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Sombre'), icon: Icon(Icons.dark_mode_rounded)),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => c.update((x) => x.copyWith(themeMode: v.first)),
          ),
        ),
        const SectionTitle('Couleurs'),
        ColorTile(title: 'Couleur principale', value: s.primaryColor, onChanged: (v) => c.update((x) => x.copyWith(primaryColor: v))),
        ColorTile(title: 'Couleur secondaire', value: s.secondaryColor, onChanged: (v) => c.update((x) => x.copyWith(secondaryColor: v))),
        ColorTile(title: 'Couleur de l\'itinéraire', value: s.routeColor, onChanged: (v) => c.update((x) => x.copyWith(routeColor: v))),
        ColorTile(title: 'Couleur des marqueurs', value: s.markerColor, onChanged: (v) => c.update((x) => x.copyWith(markerColor: v))),
        const SectionTitle('Interface'),
        SliderTile(title: 'Taille de l\'interface', value: s.uiScale, min: 0.85, max: 1.4, divisions: 11, display: '${(s.uiScale * 100).round()} %', onChanged: (v) => c.update((x) => x.copyWith(uiScale: v))),
        SwitchRow(title: 'Réduire les animations', subtitle: 'Supprime les transitions entre écrans', value: s.reduceAnimations, onChanged: (v) => c.update((x) => x.copyWith(reduceAnimations: v))),
        SwitchRow(title: 'Couleurs dynamiques (Material You)', subtitle: 'Reprend les couleurs de votre fond d\'écran sur Android 12 et plus. Sur iOS et les anciens Android, le vert Strasse est conservé.', value: s.useDynamicColor, onChanged: (v) => c.update((x) => x.copyWith(useDynamicColor: v))),
        SwitchRow(title: 'Interface compacte', value: s.compactUi, onChanged: (v) => c.update((x) => x.copyWith(compactUi: v))),
        SwitchRow(title: 'Libellés de la barre d\'onglets', value: s.showNavLabels, onChanged: (v) => c.update((x) => x.copyWith(showNavLabels: v))),
        const SectionTitle('Écran d\'accueil'),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Activez, désactivez et réordonnez les sections.', style: TextStyle(fontSize: 13))),
        const _HomeSectionsEditor(),
      ],
    );
  }
}

class _HomeSectionsEditor extends ConsumerWidget {
  const _HomeSectionsEditor();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final c = ref.read(settingsProvider.notifier);
    final active = s.homeSections;
    final hidden = [for (final h in HomeSection.values) if (!active.contains(h)) h];
    return Column(
      children: [
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          onReorder: (o, n) {
            if (n > o) n--;
            final list = [...active];
            list.insert(n, list.removeAt(o));
            c.update((x) => x.copyWith(homeSections: list));
          },
          children: [
            for (final h in active)
              ListTile(
                key: ValueKey(h),
                leading: const Icon(Icons.drag_handle_rounded),
                title: Text(h.label),
                trailing: IconButton(tooltip: 'Masquer', icon: const Icon(Icons.visibility_off_outlined), onPressed: () => c.update((x) => x.copyWith(homeSections: [...active]..remove(h)))),
              ),
          ],
        ),
        for (final h in hidden)
          ListTile(
            leading: const Icon(Icons.visibility_off_rounded),
            title: Text(h.label),
            subtitle: const Text('Masquée'),
            trailing: IconButton(tooltip: 'Afficher', icon: const Icon(Icons.add_circle_outline_rounded), onPressed: () => c.update((x) => x.copyWith(homeSections: [...active, h]))),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------- Carte

class MapSettingsPage extends ConsumerWidget {
  const MapSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final c = ref.read(settingsProvider.notifier);
    return SettingsPageScaffold(
      title: 'Carte',
      children: [
        const SectionTitle('Style'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, children: [for (final m in MapStyleChoice.values) ChoiceChip(label: Text(m.label), selected: s.mapStyle == m, onSelected: (_) => c.update((x) => x.copyWith(mapStyle: m)))]),
        ),
        if (s.mapStyle == MapStyleChoice.custom) ...[
          ColorTile(title: 'Routes', value: s.customRoadColor, onChanged: (v) => c.update((x) => x.copyWith(customRoadColor: v))),
          ColorTile(title: 'Bâtiments', value: s.customBuildingColor, onChanged: (v) => c.update((x) => x.copyWith(customBuildingColor: v))),
          ColorTile(title: 'Eau', value: s.customWaterColor, onChanged: (v) => c.update((x) => x.copyWith(customWaterColor: v))),
          ColorTile(title: 'Espaces verts', value: s.customGreenColor, onChanged: (v) => c.update((x) => x.copyWith(customGreenColor: v))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Les textes et contours sont ajustés automatiquement pour rester lisibles.', style: TextStyle(fontSize: 12))),
        ],
        const SectionTitle('Niveau de détail'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<int>(
            segments: const [ButtonSegment(value: 0, label: Text('Épuré')), ButtonSegment(value: 1, label: Text('Normal')), ButtonSegment(value: 2, label: Text('Détaillé'))],
            selected: {s.mapDensity},
            onSelectionChanged: (v) => c.update((x) => x.copyWith(mapDensity: v.first)),
          ),
        ),
        const SectionTitle('Couches'),
        SwitchRow(title: 'Bâtiments', value: s.showBuildings, onChanged: (v) => c.update((x) => x.copyWith(showBuildings: v))),
        SwitchRow(title: 'Lieux d\'intérêt', value: s.showPoi, onChanged: (v) => c.update((x) => x.copyWith(showPoi: v))),
        SwitchRow(title: 'Transports en commun', value: s.showTransit, onChanged: (v) => c.update((x) => x.copyWith(showTransit: v))),
        SwitchRow(title: 'Pistes cyclables', value: s.showCycleways, onChanged: (v) => c.update((x) => x.copyWith(showCycleways: v))),
        SwitchRow(title: 'Signalements et incidents', subtitle: 'Nécessite un serveur Strasse', value: s.showTrafficEvents, onChanged: (v) => c.update((x) => x.copyWith(showTrafficEvents: v))),
      ],
    );
  }
}

// ------------------------------------------------------------------------------------ Navigation

class NavigationSettingsPage extends ConsumerStatefulWidget {
  const NavigationSettingsPage({super.key});

  @override
  ConsumerState<NavigationSettingsPage> createState() => _NavigationSettingsPageState();
}

class _NavigationSettingsPageState extends ConsumerState<NavigationSettingsPage> {
  List<String>? _voices;

  @override
  void initState() {
    super.initState();
    ref.read(voiceProvider).frenchVoices().then((v) {
      if (mounted) setState(() => _voices = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final c = ref.read(settingsProvider.notifier);
    return SettingsPageScaffold(
      title: 'Navigation',
      children: [
        const SectionTitle('Déplacement'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, children: [for (final m in TravelMode.values) ChoiceChip(avatar: Icon(m.icon, size: 18), label: Text(m.label), selected: s.defaultMode == m, onSelected: (_) => c.update((x) => x.copyWith(defaultMode: m)))]),
        ),
        ListTile(
          leading: const Icon(Icons.tune_rounded),
          title: const Text('Options d\'itinéraire par défaut'),
          subtitle: Text('Pour le mode « ${s.defaultMode.label} »'),
          onTap: () async {
            final r = await showRouteOptionsSheet(context, mode: s.defaultMode == TravelMode.transit ? TravelMode.car : s.defaultMode, prefs: s.routePrefs);
            if (r != null) await c.update((x) => x.copyWith(routePrefs: r));
          },
        ),
        const SectionTitle('Unités'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<Units>(
            segments: const [ButtonSegment(value: Units.metric, label: Text('Kilomètres')), ButtonSegment(value: Units.imperial, label: Text('Miles'))],
            selected: {s.units},
            onSelectionChanged: (v) => c.update((x) => x.copyWith(units: v.first)),
          ),
        ),
        const SectionTitle('Guidage vocal'),
        SwitchRow(title: 'Instructions vocales', value: s.voiceEnabled, onChanged: (v) => c.update((x) => x.copyWith(voiceEnabled: v))),
        if (s.voiceEnabled) ...[
          ListTile(
            title: const Text('Voix'),
            subtitle: Text(s.voiceName ?? 'Voix française par défaut de l\'appareil'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _pickVoice,
          ),
          SliderTile(title: 'Volume', value: s.voiceVolume, min: 0.2, max: 1, display: '${(s.voiceVolume * 100).round()} %', onChanged: (v) => c.update((x) => x.copyWith(voiceVolume: v))),
          SliderTile(title: 'Vitesse de parole', value: s.voiceRate, min: 0.3, max: 0.8, display: s.voiceRate.toStringAsFixed(2), onChanged: (v) => c.update((x) => x.copyWith(voiceRate: v))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final v = ref.read(voiceProvider);
                  await v.init();
                  await v.configure(enabled: true, voiceName: s.voiceName, volume: s.voiceVolume, rate: s.voiceRate);
                  await v.speak('Dans deux cents mètres, tournez à droite.', interrupt: true);
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Écouter un exemple'),
              ),
            ),
          ),
        ],
        const SectionTitle('Pendant le guidage'),
        SwitchRow(title: 'Afficher la vitesse', value: s.showSpeed, onChanged: (v) => c.update((x) => x.copyWith(showSpeed: v))),
        SwitchRow(title: 'Mode de conduite simplifié', subtitle: 'Texte plus grand, moins d\'informations', value: s.simpleDrivingMode, onChanged: (v) => c.update((x) => x.copyWith(simpleDrivingMode: v))),
        SwitchRow(title: 'Garder l\'écran allumé', value: s.keepScreenOn, onChanged: (v) => c.update((x) => x.copyWith(keepScreenOn: v))),
        SwitchRow(title: 'Annoncer les signalements', subtitle: 'Alerte vocale avant un événement signalé sur votre route', value: s.announceReports, onChanged: (v) => c.update((x) => x.copyWith(announceReports: v))),
        const SectionTitle('Mode nuit'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, children: [for (final m in NightMode.values) ChoiceChip(label: Text(m.label), selected: s.nightMode == m, onSelected: (_) => c.update((x) => x.copyWith(nightMode: m)))]),
        ),
        const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 0), child: Text('Le mode « Automatique » suit le thème clair/sombre du téléphone.', style: TextStyle(fontSize: 12))),
      ],
    );
  }

  Future<void> _pickVoice() async {
    final voices = _voices ?? const <String>[];
    final c = ref.read(settingsProvider.notifier);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: const Text('Voix par défaut'), onTap: () => Navigator.pop(ctx, '')),
            if (voices.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucune voix française listée par l\'appareil. Installez-en une dans les réglages de synthèse vocale du téléphone.')),
            for (final v in voices) ListTile(title: Text(v), onTap: () => Navigator.pop(ctx, v)),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await c.update((x) => choice.isEmpty ? x.copyWith(clearVoiceName: true) : x.copyWith(voiceName: choice));
  }
}

// --------------------------------------------------------------------------------- Notifications

class NotificationsSettingsPage extends ConsumerWidget {
  const NotificationsSettingsPage({super.key});

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool on, AppSettings Function(AppSettings) apply) async {
    if (on) {
      final ok = await ref.read(notificationsProvider).requestPermission();
      if (!ok) {
        if (context.mounted) showMessage(context, 'Notifications non autorisées. Activez-les dans les réglages du téléphone.');
        return;
      }
    }
    await ref.read(settingsProvider.notifier).update(apply);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return SettingsPageScaffold(
      title: 'Notifications',
      children: [
        const Padding(padding: EdgeInsets.all(20), child: Text('Toutes les notifications sont facultatives, désactivées par défaut, et jamais publicitaires. L\'autorisation du système n\'est demandée qu\'à l\'activation.')),
        SwitchRow(title: 'Téléchargements de cartes', subtitle: 'Fin ou échec d\'un téléchargement', value: s.notifyDownloads, onChanged: (v) => _toggle(context, ref, v, (x) => x.copyWith(notifyDownloads: v))),
        SwitchRow(title: 'Synchronisation', subtitle: 'Quand vos données sont synchronisées', value: s.notifySync, onChanged: (v) => _toggle(context, ref, v, (x) => x.copyWith(notifySync: v))),
        SwitchRow(title: 'Trajets', subtitle: 'Arrivée à destination', value: s.notifyTrips, onChanged: (v) => _toggle(context, ref, v, (x) => x.copyWith(notifyTrips: v))),
      ],
    );
  }
}
