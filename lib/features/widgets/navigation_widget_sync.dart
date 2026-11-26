import 'dart:typed_data';

import 'package:flutter/painting.dart' show MemoryImage;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:strasse/src/home_widget/strasse_navigation.home_widget.dart';

/// Incrémenté lorsqu'un widget demande d'ouvrir la recherche rapide dans l'onglet Carte.
final homeWidgetSearchRequestProvider = StateProvider<int>((ref) => 0);

/// Synchronisation non bloquante de l'état de navigation et de l'aperçu cartographique.
abstract final class NavigationWidgetSync {
  static const appGroupId = 'group.fr.strasse.strasse';

  static Stream<Uri> get launches => StrasseNavigationHomeWidget.launchedFromWidget();

  static bool isQuickSearchUri(Uri uri) =>
      uri.scheme == 'strasse' && uri.host == 'widget' && uri.path == '/search' && uri.queryParameters.containsKey('homeWidget');

  static Future<void> initialize() async {
    try {
      await HomeWidget.setAppGroupId(appGroupId);
      await StrasseNavigationHomeWidget.saveData(
        status: 'Aucune navigation active',
        destination: 'Où souhaitez-vous aller ?',
        eta: '—',
        nextTurn: 'Votre prochaine manœuvre apparaîtra ici',
        distanceToTurn: '—',
        remainingDistance: '—',
        mapAttribution: '© OpenStreetMap contributors',
      );
      await StrasseNavigationHomeWidget.updateWidget();
    } catch (_) {
      // Le guidage ne doit pas dépendre de la disponibilité des widgets ou des App Groups.
    }
  }

  static Future<void> update({
    required String status,
    required String destination,
    required String eta,
    required String nextTurn,
    required String distanceToTurn,
    required String remainingDistance,
  }) async {
    try {
      await StrasseNavigationHomeWidget.saveData(
        status: status,
        destination: destination,
        eta: eta,
        nextTurn: nextTurn,
        distanceToTurn: distanceToTurn,
        remainingDistance: remainingDistance,
      );
      await StrasseNavigationHomeWidget.updateWidget();
    } catch (_) {
      // Les limites de rafraîchissement WidgetKit / Glance ne doivent pas perturber la navigation.
    }
  }

  /// L'image est transférée dans le groupe partagé iOS / stockage HomeWidget Android.
  /// Les widgets ne tentent jamais de charger une URL réseau pendant leur rendu natif.
  static Future<void> updateMapPreview(Uint8List png, {String attribution = '© OpenStreetMap contributors'}) async {
    if (png.isEmpty) return;
    try {
      await StrasseNavigationHomeWidget.saveData(
        mapPreview: MemoryImage(png),
        mapAttribution: attribution,
      );
      await StrasseNavigationHomeWidget.updateWidget();
    } catch (_) {
      // Un aperçu indisponible n'interrompt jamais le guidage GPS.
    }
  }
}
