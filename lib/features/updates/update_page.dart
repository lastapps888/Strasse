import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:strasse/features/settings/settings_widgets.dart';
import 'package:strasse/features/updates/update_controller.dart';
import 'package:url_launcher/url_launcher.dart';

/// Réglages > Mise à jour : version installée, dernière version publiée sur GitHub, notes, téléchargement.
/// Android : téléchargement, vérification (SHA-256 et signataire) puis installation confirmée par le système.
/// iOS : Apple n'autorise pas l'installation automatique hors App Store ; l'IPA se télécharge puis s'installe à la main.
class UpdatePage extends ConsumerStatefulWidget {
  const UpdatePage({super.key});

  @override
  ConsumerState<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends ConsumerState<UpdatePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = ref.read(updateProvider.notifier);
      c.check(force: true);
      c.markSeen();
    });
  }

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(updateProvider);
    final c = ref.read(updateProvider.notifier);
    final r = st.release;
    final cs = context.cs;
    final busy = st.phase == UpdatePhase.checking || st.phase == UpdatePhase.downloading;
    return SettingsPageScaffold(
      title: 'Mise à jour',
      children: [
        ListTile(leading: const Icon(Icons.info_outline_rounded), title: const Text('Version installée'), subtitle: Text(st.installed.isEmpty ? AppConfig.version : st.installed)),
        if (st.phase == UpdatePhase.checking) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        if (r == null && st.phase != UpdatePhase.checking && st.phase != UpdatePhase.error)
          const ListTile(leading: Icon(Icons.check_circle_outline_rounded), title: Text('Aucune version publiée trouvée'), subtitle: Text('Aucune « Release » n\'est disponible sur GitHub pour le moment.')),
        if (r != null && !st.available && st.phase != UpdatePhase.checking)
          ListTile(leading: Icon(Icons.check_circle_rounded, color: context.sc.success), title: const Text('Strasse est à jour'), subtitle: Text('Dernière version publiée : ${r.version}')),
        if (st.available && r != null) ...[
          ListTile(
            leading: Icon(Icons.system_update_rounded, color: cs.primary),
            title: Text('Version ${r.version} disponible'),
            subtitle: Text(r.publishedAt == null ? 'Publiée sur GitHub' : 'Publiée le ${formatDate(r.publishedAt!.toLocal())}'),
          ),
          if (r.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest.withOpacity(0.5), borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Nouveautés', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(_plain(r.notes), style: const TextStyle(fontSize: 13.5)),
                ]),
              ),
            ),
          if (Platform.isAndroid) ..._android(context, st, c) else if (Platform.isIOS) ..._ios(context, st) else _other(r),
        ],
        if (st.phase == UpdatePhase.error && st.message != null)
          Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0), child: Text(st.message!, style: TextStyle(color: cs.error))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: OutlinedButton.icon(onPressed: busy ? null : () => c.check(force: true), icon: const Icon(Icons.refresh_rounded), label: const Text('Rechercher une mise à jour')),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Text(
            'La recherche interroge l\'API publique de GitHub (releases officielles de Strasse). Aucune donnée personnelle n\'est envoyée ; GitHub voit seulement votre adresse IP, comme pour toute requête web.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _other(AppRelease r) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: FilledButton.icon(onPressed: () => _open(r.pageUrl), icon: const Icon(Icons.open_in_new_rounded), label: const Text('Voir la version sur GitHub')),
      );

  List<Widget> _android(BuildContext context, UpdateState st, UpdateController c) {
    final r = st.release!;
    final cs = context.cs;
    return [
      if (r.apkUrl == null)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text('Cette version ne contient pas de fichier APK : ouvrez la page GitHub.', style: TextStyle(color: cs.error)))
      else ...[
        if (st.phase == UpdatePhase.downloading)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LinearProgressIndicator(value: st.progress == 0 ? null : st.progress),
              const SizedBox(height: 6),
              Text('Téléchargement ${(st.progress * 100).round()} %'),
              TextButton(onPressed: c.cancelDownload, child: const Text('Annuler')),
            ]),
          ),
        if (st.phase == UpdatePhase.readyToInstall && st.apkPath != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(onPressed: c.install, icon: const Icon(Icons.install_mobile_rounded), label: const Text('Installer')),
          )
        else if (st.phase != UpdatePhase.downloading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(onPressed: c.downloadAndInstall, icon: const Icon(Icons.download_rounded), label: Text('Télécharger et installer${r.apkSize == null ? '' : ' (${formatBytes(r.apkSize!)})'}')),
          ),
        if (st.message != null && st.phase != UpdatePhase.error) Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0), child: Text(st.message!)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Text(
            'Contrôles avant installation : ${r.apkSha256 == null ? 'taille du fichier' : 'empreinte SHA-256 publiée par GitHub'} puis signature (le fichier doit être signé par la même clé que votre Strasse, sinon il est refusé). Android demande toujours votre confirmation ; la première fois, il faut autoriser Strasse à installer des applications.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
      ],
      TextButton(onPressed: () => _open(r.pageUrl), child: const Text('Voir la version sur GitHub')),
    ];
  }

  List<Widget> _ios(BuildContext context, UpdateState st) {
    final r = st.release!;
    final cs = context.cs;
    return [
      if (r.ipaUrl != null)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: FilledButton.icon(onPressed: () => _open(r.ipaUrl!), icon: const Icon(Icons.download_rounded), label: const Text('Télécharger l\'IPA'))),
      if (r.ipaUrl == null) Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text('Cette version ne contient pas de fichier IPA : ouvrez la page GitHub.', style: TextStyle(color: cs.error))),
      TextButton(onPressed: () => _open(r.pageUrl), child: const Text('Voir la version sur GitHub')),
      const SectionTitle('Installer sur iPhone / iPad'),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          'Apple n\'autorise pas une application installée hors App Store à se mettre à jour toute seule : l\'installation reste manuelle.\n\n'
          '1. Téléchargez le fichier .ipa (bouton ci-dessus), sur l\'iPhone ou sur votre ordinateur.\n'
          '2. Ouvrez-le avec AltStore, SideStore (iPhone) ou Sideloadly (ordinateur), connecté à votre identifiant Apple.\n'
          '3. Lancez l\'installation : la nouvelle version remplace l\'ancienne en gardant vos données.\n'
          '4. Si iOS le demande : Réglages > Général > VPN et gestion de l\'appareil, puis faites confiance à votre profil développeur.\n\n'
          'Avec un identifiant Apple gratuit, l\'application doit être réinstallée tous les 7 jours (AltStore / SideStore le font automatiquement).',
          style: TextStyle(fontSize: 13.5),
        ),
      ),
    ];
  }

  /// Notes de version GitHub (Markdown) : on retire seulement la syntaxe pour une lecture simple.
  String _plain(String md) => md
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'\*\*|__|`'), '')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ')
      .trim();
}
