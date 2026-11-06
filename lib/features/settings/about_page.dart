import 'package:flutter/material.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/app/widgets/strasse_logo.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/features/settings/settings_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// À propos : version, crédits obligatoires (OpenStreetMap…), licences des composants.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _open(BuildContext context, String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) showMessage(context, 'Impossible d\'ouvrir le lien.');
    } catch (_) {
      if (context.mounted) showMessage(context, 'Impossible d\'ouvrir le lien.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'À propos',
      children: [
        const SizedBox(height: 16),
        const Center(child: StrasseLogo(size: 96)),
        const SizedBox(height: 12),
        Center(child: Text(AppConfig.appName, style: context.tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800))),
        Center(child: Text('Version ${AppConfig.version}', style: context.tt.bodyMedium)),
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Strasse est une application de navigation GPS gratuite, sans publicité et respectueuse de votre vie privée. '
            'Elle s\'appuie sur des données et des logiciels ouverts.',
            textAlign: TextAlign.center,
          ),
        ),
        const SectionTitle('Données et logiciels'),
        ListTile(
          leading: const Icon(Icons.public_rounded),
          title: const Text('© Contributeurs OpenStreetMap'),
          subtitle: const Text('Données cartographiques sous licence ODbL (Open Database License).'),
          onTap: () => _open(context, AppConfig.osmCopyrightUrl),
        ),
        const ListTile(leading: Icon(Icons.layers_outlined), title: Text('MapLibre'), subtitle: Text('Moteur d\'affichage cartographique libre.')),
        const ListTile(leading: Icon(Icons.route_outlined), title: Text('Valhalla'), subtitle: Text('Moteur de calcul d\'itinéraires libre (licence MIT), utilisé via le serveur configuré.')),
        const ListTile(leading: Icon(Icons.search_rounded), title: Text('Nominatim'), subtitle: Text('Géocodage à partir des données OpenStreetMap, via le serveur configuré.')),
        const ListTile(leading: Icon(Icons.directions_transit_outlined), title: Text('OpenTripPlanner / GTFS'), subtitle: Text('Transports en commun, si un serveur et des données GTFS sont configurés.')),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Licences des composants'),
          onTap: () => showLicensePage(context: context, applicationName: AppConfig.appName, applicationVersion: AppConfig.version, applicationIcon: const Padding(padding: EdgeInsets.all(8), child: StrasseLogo(size: 48))),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Text(
            'Limites : les horaires d\'ouverture, adresses et signalements proviennent de sources externes et peuvent être inexacts. '
            'Respectez toujours le code de la route et la signalisation sur place.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}
