import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum NotificationChannel {
  downloads('downloads', 'Téléchargements de cartes'),
  sync('sync', 'Synchronisation'),
  trips('trips', 'Trajets enregistrés'),
  navigation('navigation_info', 'Informations de navigation');

  const NotificationChannel(this.id, this.label);
  final String id;
  final String label;
}

/// Notifications locales, toutes facultatives. Aucune notification publicitaire.
/// L'autorisation n'est jamais demandée au premier lancement : seulement quand l'utilisateur active une catégorie.
class NotificationsService {
  NotificationsService([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  int _nextId = 100;

  Future<void> init() async {
    if (_ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Demande l'autorisation système. Retourne vrai si les notifications peuvent être affichées.
  Future<bool> requestPermission() async {
    await init();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
        return granted ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: false, sound: false);
        return granted ?? false;
      }
    } catch (_) {}
    return false;
  }

  Future<void> show(NotificationChannel channel, String title, String body) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        _nextId++,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.label,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: false, presentSound: false),
        ),
      );
    } catch (_) {
      // Une notification manquée ne doit jamais perturber l'application.
    }
  }

  Future<void> notifyDownloadComplete(String region) =>
      show(NotificationChannel.downloads, 'Carte téléchargée', 'La région « $region » est disponible hors connexion.');

  Future<void> notifyDownloadFailed(String region) =>
      show(NotificationChannel.downloads, 'Téléchargement interrompu', 'La région « $region » n\'a pas pu être téléchargée. Réessayez depuis Cartes hors connexion.');

  Future<void> notifyMapUpdateAvailable(String region) =>
      show(NotificationChannel.downloads, 'Mise à jour de carte', 'Une mise à jour est conseillée pour la région « $region ».');

  Future<void> notifySyncDone() => show(NotificationChannel.sync, 'Synchronisation terminée', 'Vos favoris, collections et voyages sont à jour.');

  Future<void> notifyTripEvent(String tripName, String message) => show(NotificationChannel.trips, tripName, message);
}
