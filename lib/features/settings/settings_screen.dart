import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/app/widgets/nav_helpers.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/feedback/feedback_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:strasse/features/assistant/assistant_page.dart';
import 'package:strasse/features/offline_maps/offline_page.dart';
import 'package:strasse/features/privacy/privacy_page.dart';
import 'package:strasse/features/settings/about_page.dart';
import 'package:strasse/features/settings/services_page.dart';
import 'package:strasse/features/settings/app_icon_page.dart';
import 'package:strasse/features/settings/language_page.dart';
import 'package:strasse/features/settings/settings_pages.dart';
import 'package:strasse/features/settings/vehicle_settings_page.dart';
import 'package:strasse/features/sync/account_page.dart';

/// Onglet Réglages : point d'entrée de toutes les sections.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final auth = ref.watch(authProvider);
    final regions = ref.watch(offlineManagerProvider);
    final padding = MediaQuery.paddingOf(context);

    void open(Widget page) => pushPage(context, page, reduce: s.reduceAnimations);

    Widget tile(IconData icon, String title, String? subtitle, Widget page) => ListTile(
          leading: IconBadge(icon: icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => open(page),
        );

    Widget link(IconData icon, String title, String subtitle, String url) => ListTile(
          leading: IconBadge(icon: icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.open_in_new_rounded),
          onTap: () async {
            final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            if (!ok && context.mounted) showMessage(context, 'Impossible d\'ouvrir le lien : $url');
          },
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: EdgeInsets.only(bottom: 120 + padding.bottom),
        children: [
          tile(Icons.account_circle_outlined, 'Compte et synchronisation', auth.signedIn ? auth.email : 'Facultatif · non connecté', const AccountPage()),
          tile(Icons.palette_outlined, 'Apparence', 'Thème, couleurs, accueil', const AppearancePage()),
          tile(Icons.map_outlined, 'Carte', 'Style, couches, détails', const MapSettingsPage()),
          tile(Icons.navigation_outlined, 'Navigation', 'Mode, voix, unités, mode nuit', const NavigationSettingsPage()),
          tile(Icons.translate_rounded, 'Langue', 'Français, English, Deutsch, Русский…', const LanguagePage()),
          tile(Icons.apps_rounded, 'Icône de l\'application', 'Choisir parmi 13 icônes', const AppIconPage()),
          tile(Icons.directions_car_outlined, 'Véhicule et vitesse', 'Type, icône sur la carte, alerte de vitesse', const VehicleSettingsPage()),
          tile(Icons.download_for_offline_outlined, 'Cartes hors connexion', regions.isEmpty ? 'Aucune zone téléchargée' : '${regions.where((r) => r.isComplete).length} zone(s) disponible(s)', const OfflinePage()),
          if (s.assistantEnabled) tile(Icons.auto_awesome_outlined, 'Assistant', 'Demandes en langage courant', const AssistantPage()),
          tile(Icons.notifications_outlined, 'Notifications', 'Toutes facultatives', const NotificationsSettingsPage()),
          tile(Icons.privacy_tip_outlined, 'Confidentialité et données', 'Historique, données envoyées, effacement', const PrivacyPage()),
          tile(Icons.dns_outlined, 'Services', 'Serveurs de cartes, itinéraires, recherche…', const ServicesPage()),
          tile(Icons.feedback_outlined, 'Envoyer un retour', 'Écrire à l\'équipe du projet', const FeedbackPage()),
          link(Icons.system_update_outlined, 'Mise à jour', 'Versions publiées sur GitHub', AppConfig.releasesUrl),
          link(Icons.favorite_border_rounded, 'Soutenir le projet', 'Le dépôt GitHub de Strasse', AppConfig.repoUrl),
          tile(Icons.info_outline_rounded, 'À propos', 'Version, crédits, licences', const AboutPage()),
        ],
      ),
    );
  }
}
