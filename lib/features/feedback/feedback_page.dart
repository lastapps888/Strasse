import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/feedback/feedback_service.dart';
import 'package:strasse/features/services/provider_models.dart';
import 'package:url_launcher/url_launcher.dart';

/// Écran « Envoyer un retour » : texte libre, envoi automatique par e-mail (titre « Feedback » + date du jour).
class FeedbackPage extends ConsumerStatefulWidget {
  const FeedbackPage({super.key});

  @override
  ConsumerState<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends ConsumerState<FeedbackPage> {
  final _text = TextEditingController();
  final _reply = TextEditingController();
  bool _technical = false;
  bool _sending = false;
  bool _sent = false;
  Object? _error;
  DateTime? _lastSend;

  @override
  void dispose() {
    _text.dispose();
    _reply.dispose();
    super.dispose();
  }

  FeedbackService _service() => FeedbackService(userAgent: ref.read(appConfigProvider).userAgent);

  Future<void> _mailFallback() async {
    final svc = _service();
    final ok = await launchUrl(svc.mailto(_text.text, technical: _technical ? FeedbackService.technicalInfo() : null));
    if (!ok && mounted) showMessage(context, 'Aucune application e-mail n\'a pu être ouverte sur cet appareil.');
  }

  Future<void> _send() async {
    final problem = FeedbackService.validate(_text.text);
    if (problem != null) {
      setState(() => _error = Failure(FailureKind.client, problem));
      return;
    }
    final last = _lastSend;
    if (last != null && DateTime.now().difference(last).inSeconds < 30) {
      setState(() => _error = const Failure(FailureKind.client, 'Patientez quelques secondes avant un nouvel envoi.'));
      return;
    }
    final provider = ref.read(providerResolverProvider).selected(ServiceCategory.feedback);
    if (provider.adapter == 'mailto') {
      await _mailFallback();
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _sent = false;
    });
    try {
      await _service().send(_text.text, technical: _technical ? FeedbackService.technicalInfo() : null, replyTo: _reply.text);
      _lastSend = DateTime.now();
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sending = false;
        _text.clear();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(providerResolverProvider).selected(ServiceCategory.feedback);
    final viaMail = provider.adapter == 'mailto';
    return Scaffold(
      appBar: AppBar(title: const Text('Envoyer un retour')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Dites-nous ce qui ne va pas, ce qui manque ou ce qui vous plaît. Vous écrivez le message vous-même.', style: context.tt.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 6,
            maxLines: 12,
            maxLength: FeedbackService.maxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('Votre message'), alignLabelWithHint: true, border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          if (!viaMail)
            TextField(
              controller: _reply,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: tr('Votre e-mail pour une réponse (facultatif)'), border: OutlineInputBorder()),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Joindre la version et le système'),
            subtitle: Text(FeedbackService.technicalInfo()),
            value: _technical,
            onChanged: (v) => setState(() => _technical = v),
          ),
          InfoBanner(
            icon: Icons.privacy_tip_outlined,
            tone: BannerTone.info,
            message: viaMail
                ? 'Votre application e-mail s\'ouvrira avec le message prérempli. Rien n\'est envoyé tant que vous n\'appuyez pas sur « Envoyer » dans cette application.'
                : 'Seul le texte ci-dessus (et, si vous le cochez, la version) est envoyé, par le service FormSubmit, à ${AppConfig.feedbackEmail}, avec le titre « ${FeedbackService.subject(DateTime.now())} ». Aucune position ni identifiant n\'est joint.',
          ),
          if (_sent) const Padding(padding: EdgeInsets.only(top: 12), child: InfoBanner(icon: Icons.check_circle_outline_rounded, tone: BannerTone.info, message: 'Merci, votre retour a été transmis au service d\'envoi.')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: InfoBanner(icon: Icons.error_outline_rounded, tone: BannerTone.error, message: toFailure(_error!).message, action: viaMail ? null : 'Envoyer par e-mail', onAction: viaMail ? null : _mailFallback),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
            label: Text(viaMail ? 'Ouvrir l\'application e-mail' : 'Envoyer'),
          ),
        ],
      ),
    );
  }
}
