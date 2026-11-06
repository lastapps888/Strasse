import 'package:flutter/material.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/core/core.dart';

/// État de chargement centré.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (label != null) ...[const SizedBox(height: 16), Text(label!, style: context.tt.bodyMedium)],
          ],
        ),
      );
}

/// État vide avec explication et action facultative. Jamais de données inventées pour « remplir ».
class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: context.cs.outline),
              const SizedBox(height: 16),
              Text(title, style: context.tt.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message!, style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant), textAlign: TextAlign.center),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      );
}

/// Erreur avec bouton « Réessayer ».
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final f = toFailure(error);
    final icon = switch (f.kind) {
      FailureKind.offline => Icons.wifi_off_rounded,
      FailureKind.notConfigured => Icons.settings_suggest_outlined,
      FailureKind.permission => Icons.lock_outline_rounded,
      _ => Icons.error_outline_rounded,
    };
    return EmptyView(
      icon: icon,
      title: f.kind == FailureKind.notConfigured ? 'Service non configuré' : 'Un problème est survenu',
      message: f.message,
      action: (onRetry != null && f.retryable) ? FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Réessayer')) : null,
    );
  }
}

/// Bandeau d'information (hors connexion, GPS imprécis, serveur absent…).
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.icon, required this.message, this.tone = BannerTone.info, this.action, this.onAction, this.compact = false});
  final IconData icon;
  final String message;
  final BannerTone tone;
  final String? action;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final (bg, fg) = switch (tone) {
      BannerTone.info => (cs.secondaryContainer, cs.onSecondaryContainer),
      BannerTone.warning => (cs.tertiaryContainer, cs.onTertiaryContainer),
      BannerTone.error => (cs.errorContainer, cs.onErrorContainer),
    };
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 8 : 12),
        child: Row(
          children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: TextStyle(color: fg, fontSize: 13.5, height: 1.25))),
            if (action != null && onAction != null) TextButton(onPressed: onAction, child: Text(action!, style: TextStyle(color: fg, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }
}

enum BannerTone { info, warning, error }

/// Titre de section.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 8)});
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(child: Text(text, style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: context.cs.onSurfaceVariant, letterSpacing: 0.2))),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// Pastille ronde avec icône.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.color, this.size = 40, this.iconSize = 22});
  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.cs.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withOpacity(0.14), shape: BoxShape.circle),
      child: Icon(icon, color: c, size: iconSize),
    );
  }
}

/// Affiche un message court (confirmation, erreur) sans empiler les anciens.
void showMessage(BuildContext context, String text, {SnackBarAction? action}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: action));
}

/// Confirmation avant une action destructrice.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Supprimer',
  bool destructive = true,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: ctx.cs.error, foregroundColor: ctx.cs.onError) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Saisie d'une ligne de texte dans une boîte de dialogue.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String? initial,
  String? hint,
  String confirmLabel = 'Enregistrer',
  int maxLength = 60,
  int maxLines = 1,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: maxLength,
        maxLines: maxLines,
        decoration: InputDecoration(hintText: hint),
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(confirmLabel)),
      ],
    ),
  ).whenComplete(controller.dispose);
}

/// Ligne de réglage avec interrupteur.
class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.title, required this.value, required this.onChanged, this.subtitle, this.icon});
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        secondary: icon == null ? null : Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        value: value,
        onChanged: onChanged,
      );
}
