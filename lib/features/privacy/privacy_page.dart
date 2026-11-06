import 'package:flutter/material.dart';
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
    final actions = ref.read(dataActionsProvider);
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
        const SectionTitle('Effacer'),
        ListTile(
          leading: const Icon(Icons.history_rounded),
          title: const Text('Effacer l\'historique des trajets'),
          onTap: () async {
            if (await confirm(context, title: 'Effacer l\'historique ?', message: 'Tous les trajets et les statistiques seront supprimés de cet appareil.', confirmLabel: 'Effacer')) {
              await actions.clearHistory();
              if (context.mounted) showMessage(context, 'Historique effacé.');
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.search_off_rounded),
          title: const Text('Effacer les recherches et lieux récents'),
          onTap: () async {
            await actions.clearSearchData();
            if (context.mounted) showMessage(context, 'Recherches effacées.');
          },
        ),
        ListTile(
          leading: Icon(Icons.restart_alt_rounded, color: context.cs.error),
          title: const Text('Réinitialiser l\'identifiant anonyme'),
          subtitle: const Text('Génère un nouvel identifiant pour les signalements'),
          onTap: () async {
            await ref.read(secureStoreProvider).rotateInstallId();
            if (context.mounted) showMessage(context, 'Identifiant anonyme renouvelé.');
          },
        ),
        ListTile(
          leading: Icon(Icons.delete_forever_rounded, color: context.cs.error),
          title: Text('Effacer toutes les données locales', style: TextStyle(color: context.cs.error)),
          subtitle: const Text('Favoris, collections, historique, voyages, recherches et cartes téléchargées'),
          onTap: () async {
            final ok = await confirm(
              context,
              title: 'Tout effacer sur cet appareil ?',
              message: 'Favoris, collections, historique, voyages planifiés, recherches et cartes téléchargées seront supprimés définitivement. '
                  'Si vous avez un compte, les données du serveur ne sont pas touchées (supprimez le compte pour cela).',
              confirmLabel: 'Tout effacer',
            );
            if (!ok) return;
            await actions.wipeAllLocalData();
            if (context.mounted) showMessage(context, 'Données locales effacées.');
          },
        ),
        ListTile(
          leading: const Icon(Icons.settings_backup_restore_rounded),
          title: const Text('Réinitialiser les réglages'),
          onTap: () async {
            if (await confirm(context, title: 'Réinitialiser les réglages ?', message: 'Les réglages reviennent à leur valeur d\'origine (adresses de serveurs comprises). Vos données ne sont pas supprimées.', confirmLabel: 'Réinitialiser')) {
              await c.reset();
              if (context.mounted) showMessage(context, 'Réglages réinitialisés.');
            }
          },
        ),
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
