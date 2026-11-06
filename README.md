# Strasse

Application de navigation GPS **gratuite, sans publicité, respectueuse de la vie privée**, en français, pour Android et iOS (Flutter / Dart).
Logo : un carré, un « S » de route grise, la campagne verte à gauche, la mer bleue à droite.

> **État du livrable — à lire.** Ce code a été écrit **sans être compilé ni exécuté** : l'environnement de rédaction n'avait accès ni au SDK Flutter/Dart ni à npm. Aucune erreur n'est connue et rien n'a été laissé volontairement incomplet, mais des erreurs de compilation ou d'exécution sont possibles. Voir [docs/LIMITES.md](docs/LIMITES.md) pour la liste honnête de ce qui n'a pas été vérifié et des limites fonctionnelles.

## Fonctions

| Domaine | Contenu |
|---|---|
| Carte | MapLibre, tuiles vectorielles OpenStreetMap (schéma OpenMapTiles), style généré, suivi de position, orientation, couches |
| Itinéraires | Voiture, marche, vélo (Valhalla), transports en commun (OpenTripPlanner), étapes, comparaison de trajets, éviter péages/autoroutes |
| Navigation | Guidage vocal français, recalcul automatique, gestion de la perte de GPS, écran maintenu allumé, navigation en arrière-plan |
| Hors connexion | Cartes téléchargeables **et** calcul d'itinéraires sur l'appareil (réseau routier OSM) — voir limites |
| Recherche | Géocodage compatible Nominatim, historique, catégories à proximité |
| Lieux | Favoris, collections, domicile/travail, fiches de lieux |
| Trajets | Historique, planificateur, statistiques (désactivables) |
| Trafic | Incidents (fournisseur configurable) et signalements anonymes |
| Compte | Facultatif ; synchronisation chiffrée au repos (favoris, collections, trajets, préférences) |
| Réglages | Apparence (Material You, couleurs, taille), carte, navigation, notifications, services, confidentialité |
| Assistant | Assistant local (règles), sans envoi de données |

## Apparence

Inspirée de la maquette `docs/design/reference_rendu.jpg` : vert Strasse, boutons en pilule, barre d'onglets plate, navigation sombre.
**Material You** : sur Android 12+, les couleurs du fond d'écran sont reprises (`dynamic_color`) ; sur iOS et les Android plus anciens, la palette est calculée à partir du vert Strasse. Réglable dans Réglages > Apparence. Les transitions de pages sont natives (Cupertino sur iOS).

## Démarrage rapide

1. Installer Flutter (≥ 3.27). Voir [INSTALLATION.md](INSTALLATION.md).
2. `tool/setup_platforms.sh` (génère le projet Xcode et complète Android/iOS).
3. `cp config/env.example.json config/env.json` puis renseigner vos services ([CONFIGURATION.md](CONFIGURATION.md)).
4. `flutter run --dart-define-from-file=config/env.json`
5. Construire l'APK / l'IPA : [GUIDE_APK_IPA.md](GUIDE_APK_IPA.md).

Strasse n'embarque **aucun serveur** : cartes, itinéraires et recherche viennent de vos propres services (ou de fournisseurs de votre choix). Sans configuration, l'application démarre et indique clairement ce qui manque.

## Dossiers

- `lib/` code Dart (voir [ARCHITECTURE.md](ARCHITECTURE.md))
- `android/`, `ios/` projets natifs
- `backend/` serveur facultatif (Fastify, PostgreSQL/PostGIS, Redis) — [API.md](API.md)
- `config/` modèles de configuration · `tool/` scripts · `assets/` logo · `test/` tests Dart
- `docs/PROGRESS.md` suivi de reprise
