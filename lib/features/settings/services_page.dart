import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/settings/settings_model.dart';
import 'package:strasse/features/settings/settings_widgets.dart';

/// Adresses des services externes. Vide = valeur de compilation (config/env.json). Le HTTPS est exigé.
class ServicesPage extends ConsumerStatefulWidget {
  const ServicesPage({super.key});

  @override
  ConsumerState<ServicesPage> createState() => _ServicesPageState();
}

class _Svc {
  _Svc(this.key, this.title, this.help, this.icon, this.read, this.write, this.fallback, this.testPath);
  final String key;
  final String title;
  final String help;
  final IconData icon;
  final String Function(AppSettings) read;
  final AppSettings Function(AppSettings, String) write;
  final String Function(AppConfig) fallback;
  final String? testPath;
}

class _ServicesPageState extends ConsumerState<ServicesPage> {
  final Map<String, TextEditingController> _c = {};
  final Map<String, String?> _errors = {};
  final Map<String, String?> _status = {};

  late final List<_Svc> _services = [
    _Svc('tiles', 'Serveur de cartes (tuiles vectorielles)', 'URL d\'un TileJSON ou modèle {z}/{x}/{y} au schéma OpenMapTiles.', Icons.map_outlined, (s) => s.tilesUrl, (s, v) => s.copyWith(tilesUrl: v), (c) => c.tilesUrl, null),
    _Svc('glyphs', 'Polices de la carte (glyphes)', 'Modèle d\'URL se terminant par /{fontstack}/{range}.pbf.', Icons.font_download_outlined, (s) => s.glyphsUrl, (s, v) => s.copyWith(glyphsUrl: v), (c) => c.glyphsUrl, null),
    _Svc('valhalla', 'Calcul d\'itinéraires (Valhalla)', 'Adresse de base d\'un serveur Valhalla (sans /route).', Icons.route_outlined, (s) => s.valhallaUrl, (s, v) => s.copyWith(valhallaUrl: v), (c) => c.valhallaUrl, '/status'),
    _Svc('geocoder', 'Recherche d\'adresses (Nominatim)', 'Adresse de base d\'un serveur compatible Nominatim.', Icons.search_rounded, (s) => s.geocoderUrl, (s, v) => s.copyWith(geocoderUrl: v), (c) => c.geocoderUrl, '/status'),
    _Svc('otp', 'Transports en commun (OpenTripPlanner)', 'Adresse de base d\'un serveur OpenTripPlanner alimenté en GTFS. Facultatif.', Icons.directions_transit_outlined, (s) => s.otpUrl, (s, v) => s.copyWith(otpUrl: v), (c) => c.otpUrl, null),
    _Svc('overpass', 'Données routières hors connexion (Overpass)', 'Adresse d\'un point d\'accès Overpass (…/api/interpreter), utilisée une seule fois pour télécharger le réseau routier d\'une zone. Facultatif.', Icons.alt_route_rounded, (s) => s.overpassUrl, (s, v) => s.copyWith(overpassUrl: v), (c) => c.overpassUrl, null),
    _Svc('api', 'Serveur Strasse (compte, synchronisation, signalements)', 'Adresse du backend Strasse. Facultatif.', Icons.cloud_outlined, (s) => s.apiUrl, (s, v) => s.copyWith(apiUrl: v), (c) => c.apiUrl, '/health'),
  ];

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    for (final svc in _services) {
      _c[svc.key] = TextEditingController(text: svc.read(s));
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate(String v) {
    final t = v.trim();
    if (t.isEmpty) return null;
    final u = Uri.tryParse(t);
    if (u == null || !u.hasScheme || u.host.isEmpty) return 'Adresse invalide';
    if (u.scheme != 'https') return 'Une adresse https:// est requise';
    return null;
  }

  Future<void> _save(_Svc svc) async {
    final err = _validate(_c[svc.key]!.text);
    setState(() => _errors[svc.key] = err);
    if (err != null) return;
    await ref.read(settingsProvider.notifier).update((s) => svc.write(s, _c[svc.key]!.text.trim()));
    if (mounted) showMessage(context, 'Adresse enregistrée.');
  }

  Future<void> _test(_Svc svc) async {
    final base = _c[svc.key]!.text.trim().isEmpty ? svc.fallback(ref.read(appConfigProvider)) : _c[svc.key]!.text.trim();
    if (base.isEmpty || svc.testPath == null) return;
    setState(() => _status[svc.key] = 'Test en cours…');
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 6), receiveTimeout: const Duration(seconds: 6), validateStatus: (_) => true));
      final r = await dio.get<dynamic>('${base.endsWith('/') ? base.substring(0, base.length - 1) : base}${svc.testPath}');
      final ok = (r.statusCode ?? 0) >= 200 && (r.statusCode ?? 0) < 300;
      if (mounted) setState(() => _status[svc.key] = ok ? 'Le serveur répond (${r.statusCode}).' : 'Réponse inattendue (${r.statusCode}). Ce serveur n\'expose peut-être pas cette route de test.');
    } catch (_) {
      if (mounted) setState(() => _status[svc.key] = 'Serveur injoignable.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    return SettingsPageScaffold(
      title: 'Services',
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: InfoBanner(
            icon: Icons.info_outline_rounded,
            message: 'Strasse n\'embarque aucun serveur. Renseignez ici vos propres services (voir CONFIGURATION.md) ou laissez vide pour utiliser les valeurs fournies à la compilation. Toutes les adresses doivent être en HTTPS.',
          ),
        ),
        for (final svc in _services)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [Icon(svc.icon, color: context.cs.primary), const SizedBox(width: 10), Expanded(child: Text(svc.title, style: const TextStyle(fontWeight: FontWeight.w700)))]),
                    const SizedBox(height: 4),
                    Text(svc.help, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _c[svc.key],
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        hintText: svc.fallback(config).isEmpty ? 'https://…' : 'Par défaut : ${svc.fallback(config)}',
                        errorText: _errors[svc.key],
                      ),
                    ),
                    if (_status[svc.key] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_status[svc.key]!, style: const TextStyle(fontSize: 12))),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilledButton.tonal(onPressed: () => _save(svc), child: const Text('Enregistrer')),
                        const SizedBox(width: 8),
                        if (svc.testPath != null) OutlinedButton(onPressed: () => _test(svc), child: const Text('Tester')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}
