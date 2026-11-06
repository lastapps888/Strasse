import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/app/widgets/nav_helpers.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/assistant/assistant_page.dart';
import 'package:strasse/features/offline_maps/offline_page.dart';
import 'package:strasse/features/privacy/privacy_page.dart';
import 'package:strasse/features/settings/about_page.dart';
import 'package:strasse/features/settings/services_page.dart';
import 'package:strasse/features/settings/settings_pages.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: EdgeInsets.only(bottom: 120 + padding.bottom),
        children: [
          tile(Icons.account_circle_outlined, 'Compte et synchronisation', auth.signedIn ? auth.email : 'Facultatif · non connecté', const AccountPage()),
          tile(Icons.palette_outlined, 'Apparence', 'Thème, couleurs, accueil', const AppearancePage()),
          tile(Icons.map_outlined, 'Carte', 'Style, couches, détails', const MapSettingsPage()),
          tile(Icons.navigation_outlined, 'Navigation', 'Mode, voix, unités, mode nuit', const NavigationSettingsPage()),
          tile(Icons.download_for_offline_outlined, 'Cartes hors connexion', regions.isEmpty ? 'Aucune zone téléchargée' : '${regions.where((r) => r.isComplete).length} zone(s) disponible(s)', const OfflinePage()),
          if (s.assistantEnabled) tile(Icons.auto_awesome_outlined, 'Assistant', 'Demandes en langage courant', const AssistantPage()),
          tile(Icons.notifications_outlined, 'Notifications', 'Toutes facultatives', const NotificationsSettingsPage()),
          tile(Icons.privacy_tip_outlined, 'Confidentialité et données', 'Historique, données envoyées, effacement', const PrivacyPage()),
          tile(Icons.dns_outlined, 'Services', 'Serveurs de cartes, itinéraires, recherche…', const ServicesPage()),
          tile(Icons.info_outline_rounded, 'À propos', 'Version, crédits, licences', const AboutPage()),
        ],
      ),
    );
  }
}
