# Confidentialité et absence de suivi

Objectif : aucune donnée d'usage ne quitte l'appareil sans action de l'utilisateur, et rien n'est envoyé à Google par l'application.

## Ce que le projet fait

- Aucune dépendance Firebase, Analytics, publicité, rapport de plantage, polices ou cartes Google (`tool/check_privacy.sh` le vérifie dans `pubspec.*`, `lib/`, Gradle et manifestes).
- `allowBackup="false"` : les données de l'application ne partent pas dans la sauvegarde Google Drive.
- Position : `geolocator` est configuré avec `forceLocationManager: true` sur Android. La position vient du `LocationManager` du système, sans le fournisseur fusionné de Google Play Services.
- Outils de développement : `tool/setup_platforms.sh` exécute `flutter config --no-analytics` et `dart --disable-telemetry`.
- Les services réseau (cartes, recherche, itinéraires…) ne reçoivent que ce qu'exige la requête. Voir l'écran Réglages > Confidentialité.
- Le feedback n'est envoyé que sur action explicite, avec le texte écrit par l'utilisateur.

## Ce que le projet ne peut pas garantir

- `geolocator_android` référence encore la bibliothèque `play-services-location` dans le binaire. Elle n'est pas appelée avec `forceLocationManager`, mais elle est présente. L'enlever demande un autre plugin de localisation.
- Le moteur Flutter, Android et iOS eux-mêmes ont leurs propres communications avec Google ou Apple (mises à jour du système, services de l'appareil). Elles ne dépendent pas de Strasse.
- La synthèse vocale utilise le moteur du système. Sur Android, c'est souvent le moteur de Google : son comportement (hors ligne ou non, voix téléchargées) est celui des réglages de l'appareil.
- Le serveur de cartes, le géocodeur, Valhalla, Overpass et Transitous voient l'adresse IP de l'appareil et la zone ou les points demandés. Auto-hébergez-les pour l'éviter.
- Rien de ceci n'a été mesuré sur un appareil : aucune compilation n'a été possible dans l'environnement de développement.
