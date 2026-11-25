import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/i18n/translator.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/services/provider_catalog.dart';
import 'package:strasse/features/services/provider_models.dart';
import 'package:strasse/features/services/provider_resolver.dart';
import 'package:strasse/features/services/provider_tester.dart';
import 'package:strasse/features/settings/settings_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Gestionnaire de fournisseurs de données : un sélecteur par catégorie, « + » pour une adresse personnalisée,
/// informations détaillées et test réel du fournisseur.
class ServicesPage extends ConsumerStatefulWidget {
  const ServicesPage({super.key});

  @override
  ConsumerState<ServicesPage> createState() => _ServicesPageState();
}

/// Formats d'API acceptés pour une adresse personnalisée, par catégorie. Absent : pas d'adresse personnalisable.
const Map<ServiceCategory, List<(String, String)>> _customAdapters = {
  ServiceCategory.tiles: [('tilejson', 'TileJSON ou modèle {z}/{x}/{y} (tuiles vectorielles)'), ('styleurl', 'Style MapLibre complet (style.json)')],
  ServiceCategory.glyphs: [('glyphs', 'Modèle …/{fontstack}/{range}.pbf')],
  ServiceCategory.geocoding: [('nominatim', 'Compatible Nominatim'), ('photon', 'Compatible Photon')],
  ServiceCategory.reverse: [('nominatim', 'Compatible Nominatim'), ('photon', 'Compatible Photon')],
  ServiceCategory.routing: [('valhalla', 'Compatible Valhalla (POST /route)')],
  ServiceCategory.roadData: [('overpass', 'Overpass API (…/api/interpreter)')],
  ServiceCategory.transit: [('motis', 'Compatible MOTIS 2 (/api/v1)'), ('otp', 'OpenTripPlanner')],
  ServiceCategory.account: [('strasse-api', 'Serveur Strasse (Fastify)')],
  ServiceCategory.reports: [('strasse-api', 'Serveur Strasse (Fastify)')],
};

const List<(String, IconData, List<ServiceCategory>)> _sections = [
  ('Carte', Icons.map_outlined, [ServiceCategory.tiles, ServiceCategory.glyphs]),
  ('Recherche', Icons.search_rounded, [ServiceCategory.geocoding, ServiceCategory.reverse]),
  ('Itinéraires', Icons.alt_route_rounded, [ServiceCategory.routing, ServiceCategory.transit, ServiceCategory.roadData]),
  ('Lieux et réservations', Icons.hotel_outlined, [ServiceCategory.tourism, ServiceCategory.hotels, ServiceCategory.restaurants, ServiceCategory.booking]),
  ('Trafic, compte et synchronisation', Icons.cloud_sync_outlined, [ServiceCategory.traffic, ServiceCategory.reports, ServiceCategory.account]),
  ('Retours', Icons.feedback_outlined, [ServiceCategory.feedback]),
  ('Musique', Icons.library_music_outlined, [ServiceCategory.spotify, ServiceCategory.appleMusic, ServiceCategory.deezer, ServiceCategory.localMusic]),
];

class _ServicesPageState extends ConsumerState<ServicesPage> {
  final Map<ServiceCategory, ProviderTestResult?> _results = {};
  final Set<ServiceCategory> _testing = {};

  Future<void> _select(ServiceCategory c, String id) async {
    await ref.read(settingsProvider.notifier).update((s) => s.copyWith(providerSelections: {...s.providerSelections, c.id: id}));
    if (mounted) setState(() => _results.remove(c));
  }

  Future<void> _test(ServiceCategory c) async {
    final resolver = ref.read(providerResolverProvider);
    final p = resolver.selected(c);
    setState(() {
      _testing.add(c);
      _results.remove(c);
    });
    final res = await ProviderTester(resolver).test(p);
    if (!mounted) return;
    setState(() {
      _testing.remove(c);
      _results[c] = res;
    });
  }

  Future<void> _delete(ServiceCategory c, ServiceProvider p) async {
    final ok = await confirm(context, title: 'Supprimer ce fournisseur ?', message: '« ${p.name} » sera retiré. Le fournisseur recommandé sera rétabli.');
    if (!ok) return;
    await ref.read(settingsProvider.notifier).update((s) {
      final sel = {...s.providerSelections}..remove(c.id);
      return s.copyWith(providerSelections: sel, customProviders: [for (final x in s.customProviders) if (x.id != p.id) x]);
    });
    if (mounted) setState(() => _results.remove(c));
  }

  Future<void> _add(ServiceCategory c) async {
    final adapters = _customAdapters[c];
    if (adapters == null) return;
    final created = await showDialog<ServiceProvider>(context: context, builder: (_) => _AddProviderDialog(category: c, adapters: adapters));
    if (created == null) return;
    await ref.read(settingsProvider.notifier).update((s) => s.copyWith(
          customProviders: [...s.customProviders, created],
          providerSelections: {...s.providerSelections, c.id: created.id},
        ));
    if (mounted) {
      setState(() => _results.remove(c));
      showMessage(context, 'Fournisseur ajouté et sélectionné.');
    }
  }

  Future<void> _credentials(ServiceProvider p) async {
    await showDialog<void>(context: context, builder: (_) => _CredentialsDialog(provider: p));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final resolver = ref.watch(providerResolverProvider);
    return SettingsPageScaffold(
      title: 'Services',
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: InfoBanner(
            icon: Icons.verified_outlined,
            message: 'Les fournisseurs recommandés sont déjà sélectionnés : vous n\'avez rien à configurer pour la carte, la recherche et les itinéraires. '
                'Changez de fournisseur seulement si vous hébergez votre propre serveur ou si un service est indisponible. Les serveurs publics sont soumis à une politique d\'usage raisonnable, sans garantie de disponibilité.',
          ),
        ),
        SwitchRow(
          title: 'Basculement automatique',
          subtitle: 'Si un serveur ne répond pas, utiliser un fournisseur équivalent lorsqu\'il en existe un.',
          value: settings.autoFallback,
          onChanged: (v) => ref.read(settingsProvider.notifier).update((s) => s.copyWith(autoFallback: v)),
        ),
        for (final section in _sections) ...[
          SectionTitle(section.$1),
          for (final c in section.$3) _categoryCard(context, c, resolver),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _categoryCard(BuildContext context, ServiceCategory c, ProviderResolver resolver) {
    final cs = context.cs;
    final selected = resolver.selected(c);
    final options = resolver.all(c);
    final items = [...options, if (!options.any((o) => o.id == selected.id)) selected];
    final recommended = ProviderCatalog.recommendedFor(c);
    final result = _results[c];
    final needsInput = _missingConfig(resolver, selected);
    final canAdd = _customAdapters.containsKey(c);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.label, style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(c.description, style: context.tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selected.id,
                      isExpanded: true,
                      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                      items: [
                        for (final p in items)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(p.id == recommended.id ? '${p.name}  ★' : p.name, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (id) {
                        if (id != null) _select(c, id);
                      },
                    ),
                  ),
                  if (canAdd) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(tooltip: tr('Ajouter une adresse personnalisée'), icon: const Icon(Icons.add_rounded), onPressed: () => _add(c)),
                  ],
                ],
              ),
              if (selected.id == recommended.id)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text('★ Recommandé', style: context.tt.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700))),
              if (needsInput != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
                    const SizedBox(width: 6),
                    Expanded(child: Text(needsInput, style: context.tt.bodySmall?.copyWith(color: cs.error))),
                  ]),
                ),
              if (result != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(result.ok ? Icons.check_circle_rounded : Icons.error_rounded, size: 18, color: result.ok ? cs.primary : cs.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${result.message}${result.latency == null ? '' : '  (${result.latency!.inMilliseconds} ms)'}',
                        style: context.tt.bodySmall,
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(icon: const Icon(Icons.info_outline_rounded, size: 18), label: const Text('Informations'), onPressed: () => _showInfo(selected, resolver)),
                  if (ProviderTester.canTest(selected))
                    OutlinedButton.icon(
                      icon: _testing.contains(c)
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.network_check_rounded, size: 18),
                      label: const Text('Tester'),
                      onPressed: _testing.contains(c) ? null : () => _test(c),
                    ),
                  if (selected.kind == ProviderKind.credentials)
                    OutlinedButton.icon(icon: const Icon(Icons.key_rounded, size: 18), label: const Text('Identifiants'), onPressed: () => _credentials(selected)),
                  if (selected.id != recommended.id)
                    TextButton(onPressed: () => _select(c, recommended.id), child: const Text('Revenir au recommandé')),
                  if (selected.custom && !selected.id.startsWith('build-'))
                    TextButton(onPressed: () => _delete(c, selected), child: Text('Supprimer', style: TextStyle(color: cs.error))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Message si le fournisseur actif ne peut pas fonctionner tant que quelque chose n'est pas renseigné.
  String? _missingConfig(ProviderResolver r, ServiceProvider p) {
    switch (p.kind) {
      case ProviderKind.url:
        // Les services de lieux utilisent le serveur Overpass commun configuré dans « Données routières ».
        // Ils ne nécessitent pas d'adresse dédiée dans chaque catégorie.
        if (p.adapter == 'overpass-poi') {
          final shared = r.selected(ServiceCategory.roadData);
          return r.urlOf(shared).isEmpty
              ? 'Configurez un serveur Overpass dans « Données routières ».'
              : null;
        }
        return r.urlOf(p).isEmpty ? 'Aucune adresse renseignée : appuyez sur « + » pour ajouter votre serveur.' : null;
      case ProviderKind.credentials:
        for (final f in p.fields) {
          if (r.credential(p, f.key).isEmpty) return 'Identifiants à renseigner (bouton « Identifiants »).';
        }
        if (p.fields.isEmpty && r.urlOf(p).isEmpty) return 'Adresse non renseignée.';
        return null;
      case ProviderKind.native:
      case ProviderKind.link:
        return null;
    }
  }

  void _showInfo(ServiceProvider p, ProviderResolver r) {
    final url = r.urlOf(p);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Text(p.name, style: ctx.tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(p.description),
            if (url.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Adresse', style: ctx.tt.labelLarge),
              SelectableText(url, style: ctx.tt.bodySmall),
            ],
            if (p.features.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Fonctions', style: ctx.tt.labelLarge),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final f in p.features) Chip(label: Text(f))]),
            ],
            if (p.limits.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Limites et conditions d\'usage', style: ctx.tt.labelLarge),
              Text(p.limits),
            ],
            if (p.license.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Licence et données', style: ctx.tt.labelLarge),
              Text(p.license),
            ],
            const SizedBox(height: 14),
            Wrap(spacing: 8, children: [
              if (p.docUrl.isNotEmpty) OutlinedButton(onPressed: () => _open(p.docUrl), child: const Text('Documentation')),
              if (p.termsUrl.isNotEmpty) OutlinedButton(onPressed: () => _open(p.termsUrl), child: const Text('Conditions d\'utilisation')),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showMessage(context, 'Impossible d\'ouvrir le lien.');
  }
}

/// Fenêtre « + » : adresse HTTPS personnalisée, nom et description facultatifs, format d'API.
class _AddProviderDialog extends StatefulWidget {
  const _AddProviderDialog({required this.category, required this.adapters});
  final ServiceCategory category;
  final List<(String, String)> adapters;

  @override
  State<_AddProviderDialog> createState() => _AddProviderDialogState();
}

class _AddProviderDialogState extends State<_AddProviderDialog> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  late String _adapter = widget.adapters.first.$1;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _save() {
    final template = _adapter == 'glyphs' || (_adapter == 'tilejson' && _url.text.contains('{z}'));
    final err = validateProviderUrl(_url.text, template: template);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (_adapter == 'glyphs' && !(_url.text.contains('{fontstack}') && _url.text.contains('{range}'))) {
      setState(() => _error = 'Le modèle doit contenir {fontstack} et {range}.');
      return;
    }
    final host = Uri.parse(_url.text.trim().replaceAll(RegExp(r'\{[a-z]+\}'), 'x')).host;
    Navigator.of(context).pop(ServiceProvider(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      category: widget.category,
      name: _name.text.trim().isEmpty ? host : _name.text.trim(),
      description: _desc.text.trim().isEmpty ? 'Adresse personnalisée.' : _desc.text.trim(),
      baseUrl: _url.text.trim(),
      adapter: _adapter,
      custom: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Ajouter — ${widget.category.label}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(labelText: tr('Adresse (https://…)'), errorText: trn(_error)),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            if (widget.adapters.length > 1)
              DropdownButtonFormField<String>(
                value: _adapter,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Format de l\'API')),
                items: [for (final a in widget.adapters) DropdownMenuItem(value: a.$1, child: Text(a.$2, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _adapter = v ?? _adapter),
              )
            else
              Text('Format : ${widget.adapters.first.$2}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: InputDecoration(labelText: tr('Nom (facultatif)'))),
            const SizedBox(height: 12),
            TextField(controller: _desc, decoration: InputDecoration(labelText: tr('Description (facultatif)')), maxLines: 2),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}

/// Saisie des identifiants d'un fournisseur (stockés dans le coffre sécurisé de l'appareil).
class _CredentialsDialog extends ConsumerStatefulWidget {
  const _CredentialsDialog({required this.provider});
  final ServiceProvider provider;

  @override
  ConsumerState<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends ConsumerState<_CredentialsDialog> {
  final Map<String, TextEditingController> _c = {};
  final Map<String, String?> _errors = {};

  @override
  void initState() {
    super.initState();
    final creds = ref.read(credentialsProvider);
    for (final f in widget.provider.fields) {
      _c[f.key] = TextEditingController(text: creds['${widget.provider.id}.${f.key}'] ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    var ok = true;
    for (final f in widget.provider.fields) {
      final v = _c[f.key]!.text.trim();
      String? err;
      if (v.isNotEmpty && f.isUrl) err = validateProviderUrl(v);
      _errors[f.key] = err;
      if (err != null) ok = false;
    }
    if (!ok) {
      setState(() {});
      return;
    }
    final notifier = ref.read(credentialsProvider.notifier);
    for (final f in widget.provider.fields) {
      await notifier.set(widget.provider, f.key, _c[f.key]!.text);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final resolver = ref.read(providerResolverProvider);
    return AlertDialog(
      title: Text(widget.provider.name),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ces informations restent dans le coffre sécurisé de cet appareil. Ne saisissez jamais de clé privée ou « service_role » : seules les clés publiques sont attendues.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (final f in widget.provider.fields) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _c[f.key],
                obscureText: f.secret,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: f.isUrl ? TextInputType.url : TextInputType.text,
                decoration: InputDecoration(
                  labelText: trn(f.label),
                  hintText: trn(f.hint.isEmpty ? null : f.hint),
                  errorText: trn(_errors[f.key]),
                  helperText: trn(_c[f.key]!.text.isEmpty && resolver.credential(widget.provider, f.key).isNotEmpty ? 'Valeur fournie par l\'application.' : null),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}
