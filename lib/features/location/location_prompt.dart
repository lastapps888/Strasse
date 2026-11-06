import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/location/location_service.dart';

/// Vérifie la permission de localisation ; l'explique avant de la demander.
/// Renvoie vrai si la position est utilisable. Le système peut refuser définitivement : on renvoie alors vers les réglages.
Future<bool> ensureLocation(BuildContext context, WidgetRef ref) async {
  final ctrl = ref.read(locationControllerProvider.notifier);
  var status = await ctrl.refreshStatus();
  if (status == LocationStatus.granted) {
    await ctrl.start();
    return true;
  }
  if (!context.mounted) return false;

  switch (status) {
    case LocationStatus.serviceOff:
      final go = await _dialog(
        context,
        title: 'Localisation désactivée',
        message: 'Activez la localisation de votre appareil pour afficher votre position et calculer des trajets depuis l\'endroit où vous êtes.',
        action: 'Ouvrir les réglages',
      );
      if (go) await ctrl.openLocationSettings();
      return false;
    case LocationStatus.deniedForever:
      final go = await _dialog(
        context,
        title: 'Autorisation refusée',
        message: 'Strasse n\'a pas accès à votre position. Vous pouvez l\'autoriser dans les réglages de l\'appareil (uniquement pendant l\'utilisation de l\'application).',
        action: 'Ouvrir les réglages',
      );
      if (go) await ctrl.openAppSettings();
      return false;
    default:
      final ok = await _dialog(
        context,
        title: 'Utiliser votre position ?',
        message: 'Strasse utilise votre position pour vous situer sur la carte et vous guider. Elle reste sur votre appareil : '
            'elle n\'est jamais envoyée à un serveur sans votre action (la recherche d\'itinéraire envoie seulement les points de départ et d\'arrivée au serveur d\'itinéraires que vous avez configuré). '
            'Seule l\'autorisation « pendant l\'utilisation » est demandée.',
        action: 'Continuer',
      );
      if (!ok) return false;
      status = await ctrl.request();
      if (status == LocationStatus.granted) return true;
      if (context.mounted) showMessage(context, 'Sans autorisation, vous pouvez toujours rechercher des lieux et saisir un départ.');
      return false;
  }
}

Future<bool> _dialog(BuildContext context, {required String title, required String message, required String action}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Plus tard')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return r ?? false;
}
