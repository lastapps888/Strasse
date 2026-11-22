import 'package:home_widget/home_widget.dart';
import 'package:strasse/src/home_widget/strasse_navigation.home_widget.dart';

/// Synchronisation non bloquante de l'état de navigation vers les widgets natifs.
abstract final class NavigationWidgetSync {
  static const appGroupId = 'group.fr.strasse.strasse';

  static Future<void> initialize() async {
    try {
      await HomeWidget.setAppGroupId(appGroupId);
      await StrasseNavigationHomeWidget.saveData(
        status: 'Aucune navigation active',
        destination: 'Lancez un trajet',
        eta: '—',
        nextTurn: 'Votre prochaine manœuvre apparaîtra ici',
        distanceToTurn: '—',
        remainingDistance: '—',
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
}
