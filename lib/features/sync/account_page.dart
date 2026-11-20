import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:flutter/services.dart';
import 'package:strasse/data/providers/strasse_cloud_backend.dart';
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

  Future<void> _showRecoveryKey(String key) async {
    var saved = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Votre clé de récupération'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Notez cette clé et gardez-la en lieu sûr (gestionnaire de mots de passe, papier). Elle ne sera plus jamais affichée et Strasse ne peut pas la retrouver.'),
              const SizedBox(height: 12),
              SelectableText(key, style: const TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 8),
              TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: key)), icon: const Icon(Icons.copy_rounded), label: const Text('Copier')),
              const SizedBox(height: 8),
              const Text('Si vous oubliez votre mot de passe ET perdez cette clé, vos données synchronisées seront perdues définitivement.', style: TextStyle(fontWeight: FontWeight.w700)),
              CheckboxListTile(contentPadding: EdgeInsets.zero, value: saved, onChanged: (v) => setS(() => saved = v ?? false), title: const Text('J\'ai noté ma clé de récupération')),
            ]),
          ),
          actions: [TextButton(onPressed: saved ? () => Navigator.of(ctx).pop() : null, child: const Text('Terminer'))],
        ),
      ),
    );
    if (mounted) ref.read(recoveryKeyProvider.notifier).state = null;
  }

  Future<void> _recoverDialog() async {
    final email = TextEditingController(text: _email.text.trim());
    final key = TextEditingController();
    final pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mot de passe oublié'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Saisissez votre e-mail, la clé de récupération notée à l\'inscription et un nouveau mot de passe.'),
            const SizedBox(height: 12),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('Adresse e-mail'))),
            TextField(controller: key, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr('Clé de récupération'))),
            TextField(controller: pw, obscureText: true, decoration: InputDecoration(labelText: tr('Nouveau mot de passe'), helperText: tr('10 caractères minimum'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Réinitialiser')),
        ],
      ),
    );
    final e = email.text.trim(), k = key.text, p = pw.text;
    email.dispose();
    key.dispose();
    pw.dispose();
    if (ok != true || !mounted) return;
    if (p.length < 10) {
      showMessage(context, 'Le nouveau mot de passe doit compter au moins 10 caractères.');
      return;
    }
    await ref.read(authProvider.notifier).recover(e, k, p);
  }

  Future<void> _resetPassword() async {
    final api = ref.read(strasseApiProvider);
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      showMessage(context, 'Saisissez d\'abord votre adresse e-mail.');
      return;
    }
    try {
      await api.resetPassword(email);
      if (mounted) showMessage(context, 'Si un compte existe pour cette adresse, un e-mail de réinitialisation vient d\'être envoyé.');
    } catch (e) {
      if (mounted) showMessage(context, toFailure(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final api = ref.watch(strasseApiProvider);
    final settings = ref.watch(settingsProvider);
    ref.listen<String?>(recoveryKeyProvider, (_, key) {
      if (key != null) _showRecoveryKey(key);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Compte et synchronisation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const InfoBanner(
            icon: Icons.info_outline_rounded,
            message: 'Le compte est facultatif. Sans compte, tout reste sur cet appareil. Avec un compte, vos favoris, collections, voyages planifiés et préférences sont synchronisés. '
                'Avec le serveur Strasse hébergé, ils sont chiffrés sur votre appareil avant l\'envoi : le serveur ne peut pas les lire. Votre historique de trajets n\'est jamais synchronisé.',
          ),
          const SizedBox(height: 16),
          if (!api.configured)
            const InfoBanner(icon: Icons.settings_suggest_outlined, tone: BannerTone.warning, message: 'Aucun backend n\'est configuré : la synchronisation est indisponible. Renseignez votre projet Supabase ou un serveur Strasse dans Réglages > Services.')
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
              decoration: InputDecoration(labelText: tr('Adresse e-mail')),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Adresse e-mail invalide',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
              decoration: InputDecoration(
                labelText: tr('Mot de passe'),
                helperText: trn(_register ? '10 caractères minimum' : null),
                suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded), onPressed: () => setState(() => _obscure = !_obscure)),
              ),
              validator: (v) => (v ?? '').length < (_register ? 10 : 1) ? (_register ? 'Au moins 10 caractères' : 'Saisissez votre mot de passe') : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (!_register && ref.read(strasseApiProvider) is StrasseCloudBackend)
              Align(alignment: Alignment.centerRight, child: TextButton(onPressed: busy ? null : _recoverDialog, child: const Text('Mot de passe oublié ?'))),
            if (_register && ref.read(strasseApiProvider) is StrasseCloudBackend)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: InfoBanner(
                  icon: Icons.key_rounded,
                  tone: BannerTone.warning,
                  message: 'Vos données seront chiffrées de bout en bout. Une clé de récupération vous sera montrée une seule fois : sans elle, un mot de passe oublié signifie des données perdues, car personne (pas même Strasse) ne peut les déchiffrer.',
                ),
              ),
            if (!_register && ref.read(strasseApiProvider).supportsPasswordReset)
              Align(alignment: Alignment.centerRight, child: TextButton(onPressed: busy ? null : _resetPassword, child: const Text('Mot de passe oublié ?'))),
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
