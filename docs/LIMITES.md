# Limites et points non vérifiés (honnêteté)

## Non vérifié
- **Rien n'a été compilé ni exécuté** (ni l'application Flutter, ni les tests Dart, ni le backend Node). Le SDK Flutter/Dart et npm étaient inaccessibles. Les versions de paquets de `pubspec.yaml` et `backend/package.json` n'ont pas été résolues.
- Les fichiers natifs Android/iOS sont écrits à la main d'après les gabarits Flutter 3.27 ; le projet Xcode (`Runner.xcodeproj`) est généré par `flutter create` (`tool/setup_platforms.sh`) car un `project.pbxproj` écrit à la main serait trop risqué. `gradle-wrapper.jar` (binaire) est recréé par Flutter.
- Intégration OpenTripPlanner (transports) : écrite d'après la documentation de l'API, jamais testée face à un vrai serveur.
- Client Valhalla : conforme à la documentation, jamais testé face à un vrai serveur.
- Material You : repose sur `dynamic_color` ; effet visible seulement sur Android 12+.

## Limites fonctionnelles
- **Itinéraires hors connexion** : calcul local (A*) sur un réseau routier téléchargé via Overpass, zone limitée à environ 35 km de côté. Pas de restrictions de virage, pas d'altitude (« éviter les côtes » ignoré), pas de trafic, pas de transports en commun, un seul itinéraire (pas d'alternatives), vitesses estimées (limites de vitesse OSM sinon valeurs par défaut), instructions plus simples que celles de Valhalla. Départ, étapes et arrivée doivent tous être dans la même zone téléchargée.
- **Cartes hors connexion** : le plugin cartographique ne permet que d'annuler et de mettre à jour un téléchargement, pas de le mettre en pause/reprise.
- **Limitations de vitesse** et **photos de lieux** : aucune source de données configurée, donc non affichées (rien n'est inventé). Les collections de favoris utilisent des dégradés.
- **Internationalisation** : interface en français ; le reste du système (dates, boutons système) suit les paquets de localisation Flutter.
- **Transports en commun** : nécessitent un serveur OpenTripPlanner avec données GTFS ; sans lui, le mode est indiqué comme indisponible.
- **Trafic** : seulement via le fournisseur configuré côté backend ; sans lui, aucun trafic n'est affiché.
