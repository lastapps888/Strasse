import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/settings/settings_widgets.dart';

/// Confidentialité et données : ce qui est enregistré, ce qui est envoyé, et les outils pour tout effacer.
class PrivacyPage extends ConsumerWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final c = ref.read(settingsProvider.notifier);
    final api = ref.watch(strasseApiProvider);
    final signedIn = ref.watch(authProvider).signedIn;

    return SettingsPageScaffold(
      title: 'Confidentialité et données',
      children: [
        const SectionTitle('Enregistrement local'),
        SwitchRow(
          title: 'Historique des trajets',
          subtitle: 'Enregistre les trajets terminés sur cet appareil uniquement',
          value: s.historyEnabled,
          onChanged: (v) => c.update((x) => x.copyWith(historyEnabled: v)),
        ),
        SwitchRow(
          title: 'Statistiques',
          subtitle: 'Calculées localement à partir de l\'historique',
          value: s.statsEnabled && s.historyEnabled,
          onChanged: s.historyEnabled ? (v) => c.update((x) => x.copyWith(statsEnabled: v)) : null,
        ),
        SwitchRow(title: 'Assistant local', subtitle: 'Fonctionne sur l\'appareil', value: s.assistantEnabled, onChanged: (v) => c.update((x) => x.copyWith(assistantEnabled: v))),
        const SectionTitle('Ce qui est envoyé, et à qui'),
        const _Doc(
          icon: Icons.map_outlined,
          title: 'Serveur de cartes',
          text: 'Les tuiles de la zone affichée sont demandées au serveur de cartes configuré. Il peut voir votre adresse IP et la zone consultée.',
        ),
        const _Doc(
          icon: Icons.shield_outlined,
          title: 'Aucun traqueur',
          text: 'Strasse n\'embarque ni Firebase, ni Google Analytics, ni publicité, ni rapport de plantage automatique, ni police ou carte Google. La position est lue par le système Android seul (sans services Google Play). Aucune statistique d\'usage n\'est envoyée.',
        ),
        const _Doc(
          icon: Icons.feedback_outlined,
          title: 'Retours (feedback)',
          text: 'Rien n\'est envoyé tant que vous n\'appuyez pas sur « Envoyer » dans Réglages > Envoyer un retour. Seul le texte que vous écrivez part, par le serveur d’envoi du projet, vers l’adresse de destination configurée.',
        ),
        const _Doc(
          icon: Icons.music_note_rounded,
          title: 'YouTube Music',
          text: 'La connexion Google utilise une autorisation YouTube en lecture seule pour afficher les playlists et les résultats de recherche. La lecture est ouverte dans l’application YouTube Music ; Strasse ne récupère ni ne télécharge le flux audio.',
        ),
        const _Doc(
          icon: Icons.star_outline_rounded,
          title: 'Notes et avis Google Maps',
          text: 'Si Google Places est configuré dans Réglages > Services, le nom du lieu et ses coordonnées approximatives sont envoyés à Google pour rechercher la fiche correspondante et afficher sa note et ses avis. Ce service nécessite une clé API et peut entraîner des frais selon l’usage.',
        ),
        const _Doc(
          icon: Icons.search_rounded,
          title: 'Recherche d\'adresses',
          text: 'Le texte recherché et, si disponible, une zone autour de votre position approximative sont envoyés au géocodeur configuré.',
        ),
        const _Doc(
          icon: Icons.route_rounded,
          title: 'Calcul d\'itinéraire',
          text: 'Les points de départ, d\'étapes et d\'arrivée (et vos options) sont envoyés au serveur d\'itinéraires configuré. Pendant le guidage, rien n\'est envoyé sauf en cas de recalcul.',
        ),
        _Doc(
          icon: Icons.campaign_outlined,
          title: 'Signalements et incidents',
          text: api.configured
              ? 'Pour afficher les signalements, la zone visible est envoyée au serveur Strasse. Un signalement envoie son type et sa position, avec un identifiant anonyme d\'installation (aléatoire, sans lien avec votre compte).'
              : 'Aucun serveur Strasse configuré : rien n\'est envoyé pour les signalements.',
        ),
        _Doc(
          icon: Icons.sync_rounded,
          title: 'Compte et synchronisation',
          text: signedIn
              ? 'Votre e-mail, vos favoris, collections, voyages planifiés et préférences sont synchronisés avec le serveur Strasse. L\'historique des trajets et votre position ne le sont jamais.'
              : 'Pas de compte : aucune donnée personnelle n\'est envoyée.',
        ),
        const _Doc(icon: Icons.location_on_outlined, title: 'Position GPS', text: 'Elle reste sur l\'appareil. Elle n\'est utilisée que pendant l\'utilisation de l\'application (aucune autorisation « toujours »).'),
        const _Doc(icon: Icons.block_rounded, title: 'Ce que Strasse ne fait pas', text: 'Aucune publicité, aucun traceur, aucune télémétrie, aucun partage de données avec des tiers.'),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Doc extends StatelessWidget {
  const _Doc({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: context.cs.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 2), child: Text(text)),
        isThreeLine: true,
      );
}
