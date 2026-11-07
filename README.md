# Strasse

Application de navigation GPS **gratuite, sans publicité, respectueuse de la vie privée**, en français (pour l'instant), pour Android et iOS (Flutter / Dart).

Nous avons créé une application de navigation open-source, 100% gratuite, sans publicité et hors ligne. Le projet est actuellement en Beta, elle peut comporter des bugs, même si dans l'ensemble elle devrait marcher.

## Mise en place
Pour le moment, nous avons intégré un système de multiple fournisseur de donnnées. Nous devons pour le moment renseigner les adresses nous-mêmes, ce qui n'est pas très pratique. Dans les prochaines betas, nous veilleront à améliorer cela.

STRASSE_TILES_URL : https://tiles.openfreemap.org/planet

STRASSE_GLYPHS_URL : https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf

STRASSE_VALHALLA_URL : https://valhalla1.openstreetmap.de

STRASSE_GEOCODER_URL : https://nominatim.openstreetmap.org

STRASSE_OTP_URL : à venir

STRASSE_OVERPASS_URL : https://overpass-api.de/api/interpreter

STRASSE_API_URL : pas d'URL disponible pour le moment (à venir).

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

## Installation
Vous pouvez compiler vous même l'IPA ou l'APK en suivant le guide [INSTALLATION.md](INSTALLATION.md) ou installer directement depuis les releases : https://github.com/lastapps888/Strasse/releases

ANDROID : Téléchargez le fichier APK, puis ouvrez-le. Autorisez l'installtion depuis les sources inconnues si besoin dans les paramètres. Une popup d'installation s'ouvrira. Cliquez sur "Installer" pour installer Strasse. Une publication sur le Play Store et le Galaxy Store est prévue dans le futur.
iOS (iPhone) : Téléchargez le fichier IPA. Pour l'installer vous aurez besoin d'un compte développeur Apple et installer un magasin tiers comme SideStore (https://github.com/SideStore/SideStore) ou AltStore (https://github.com/altstoreio/Altstore). Suivez les instructions de SideStore ou Altstore pour configurer le magasin. Une fois que c'est fait, ouvrez-le, activez le VPN Loopback (LocalDevVPN par exemple), et cliquez sur le + puis "installer à partir d'un fichier IPA". Sélectionnez le fichier Strasse.ipa et l'installation devrait marcher.

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
