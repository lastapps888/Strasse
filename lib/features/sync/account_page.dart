import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/sync/auth_controller.dart';

/// Compte facultatif : connexion, création, synchronisation, déconnexion et suppression du compte serveur.
class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _register = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final c = ref.read(authProvider.notifier);
    final email = _email.text.trim();
    final pw = _password.text;
    FocusScope.of(context).unfocus();
    if (_register) {
      await c.register(email, pw);
    } else {
      await c.login(email, pw);
    }
    if (mounted && ref.read(authProvider).signedIn) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final api = ref.watch(strasseApiProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Compte et synchronisation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const InfoBanner(
            icon: Icons.info_outline_rounded,
            message: 'Le compte est facultatif. Sans compte, tout reste sur cet appareil. Avec un compte, vos favoris, collections, voyages planifiés et préférences sont synchronisés '
                'avec le serveur Strasse configuré. Votre historique de trajets n\'est jamais synchronisé.',
          ),
          const SizedBox(height: 16),
          if (!api.configured)
            const InfoBanner(icon: Icons.settings_suggest_outlined, tone: BannerTone.warning, message: 'Aucun serveur Strasse n\'est configuré : la synchronisation est indisponible (Réglages > Services).')
          else if (!auth.signedIn)
            _authForm(context, auth.busy)
          else
            ..._signedIn(context, auth, settings.autoSync),
          if (auth.error != null) Padding(padding: const EdgeInsets.only(top: 12), child: InfoBanner(icon: Icons.error_outline_rounded, tone: BannerTone.error, message: auth.error!)),
        ],
      ),
    );
  }

  Widget _authForm(BuildContext context, bool busy) => Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('Connexion')), ButtonSegment(value: true, label: Text('Créer un compte'))],
              selected: {_register},
              onSelectionChanged: (s) => setState(() => _register = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Adresse e-mail'),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Adresse e-mail invalide',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                helperText: _register ? '10 caractères minimum' : null,
                suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded), onPressed: () => setState(() => _obscure = !_obscure)),
              ),
              validator: (v) => (v ?? '').length < (_register ? 10 : 1) ? (_register ? 'Au moins 10 caractères' : 'Saisissez votre mot de passe') : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            SizedBox(height: 52, child: FilledButton(onPressed: busy ? null : _submit, child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_register ? 'Créer mon compte' : 'Me connecter'))),
          ],
        ),
      );

  List<Widget> _signedIn(BuildContext context, AuthState auth, bool autoSync) {
    final c = ref.read(authProvider.notifier);
    return [
      Card(
        child: ListTile(
          leading: const IconBadge(icon: Icons.account_circle_rounded),
          title: Text(auth.email ?? ''),
          subtitle: Text(auth.lastSync == null ? 'Jamais synchronisé' : 'Dernière synchronisation : ${formatDate(auth.lastSync!)} ${formatClock(auth.lastSync!)}'),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: auth.busy ? null : () => c.syncNow(),
        icon: auth.busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync_rounded),
        label: const Text('Synchroniser maintenant'),
      ),
      if (auth.syncMessage != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(auth.syncMessage!, textAlign: TextAlign.center)),
      SwitchRow(title: 'Synchronisation automatique', subtitle: 'Après chaque modification de vos favoris ou voyages', value: autoSync, onChanged: (v) => ref.read(settingsProvider.notifier).update((s) => s.copyWith(autoSync: v))),
      const Divider(height: 32),
      OutlinedButton.icon(
        onPressed: auth.busy ? null : () async {
          await c.logout();
          if (context.mounted) showMessage(context, 'Déconnecté. Vos données locales sont conservées.');
        },
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Se déconnecter'),
      ),
      const SizedBox(height: 12),
      TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: context.cs.error),
        onPressed: auth.busy
            ? null
            : () async {
                final ok = await confirm(context, title: 'Supprimer le compte ?', message: 'Le compte et toutes les données synchronisées sur le serveur seront supprimés définitivement. Les données de cet appareil sont conservées.', confirmLabel: 'Supprimer le compte');
                if (!ok) return;
                final done = await c.deleteAccount();
                if (context.mounted && done) showMessage(context, 'Compte supprimé.');
              },
        icon: const Icon(Icons.delete_forever_rounded),
        label: const Text('Supprimer mon compte'),
      ),
    ];
  }
}
