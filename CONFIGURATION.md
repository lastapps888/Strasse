# Configuration des services

Aucune clé privée dans l'application (une app mobile est publique). Les adresses se donnent à la compilation (`config/env.json`) **ou** dans l'application (Réglages > Services, qui prévaut). Toute adresse doit être en **HTTPS**.

| Variable | Rôle | Obligatoire |
|---|---|---|
| `STRASSE_ENV` | `dev`, `test`, `prod` | non |
| `STRASSE_TILES_URL` | TileJSON vectoriel (schéma OpenMapTiles) ou modèle `{z}/{x}/{y}` | **oui** pour afficher la carte |
| `STRASSE_TILES_ATTRIBUTION` | Crédit du fournisseur de tuiles (affiché) | recommandé |
| `STRASSE_GLYPHS_URL` | Polices de carte : `…/{fontstack}/{range}.pbf` | oui pour les libellés |
| `STRASSE_MAP_FONT` | Pile de polices disponible sur ce serveur | non |
| `STRASSE_VALHALLA_URL` | Serveur Valhalla (voiture, marche, vélo) | **oui** pour les itinéraires en ligne |
| `STRASSE_GEOCODER_URL` | Serveur compatible Nominatim | **oui** pour la recherche |
| `STRASSE_OTP_URL` | OpenTripPlanner alimenté en GTFS | non (sans lui : pas de transports) |
| `STRASSE_OVERPASS_URL` | Point d'accès Overpass (`…/api/interpreter`) | non (téléchargement des itinéraires hors connexion) |
| `STRASSE_API_URL` | Backend Strasse (compte, synchro, signalements, trafic) | non |

Ce que vous devez héberger ou choisir :
- **Tuiles + polices** : un service OpenMapTiles (ex. un serveur de tuiles auto-hébergé, ou un fournisseur dont les conditions autorisent votre usage).
- **Valhalla** : à construire à partir d'extraits OSM de vos régions (voir la documentation Valhalla).
- **Nominatim** : auto-hébergé, ou un service dont la politique d'usage permet une application. Le serveur public `nominatim.openstreetmap.org` interdit un usage intensif d'application : ne pas l'utiliser en production.
- **Overpass** : une instance publique convient pour de petits téléchargements ponctuels ; respectez sa politique d'usage.
- **Données OpenStreetMap** : © contributeurs OpenStreetMap (ODbL). L'attribution est affichée dans l'application.

## Backend
Variables dans `backend/.env.example` (secrets à générer, `DATABASE_URL`, `REDIS_URL`, `ADMIN_TOKEN`, `TRAFFIC_PROVIDER`, `TOMTOM_API_KEY`, `SYNC_ENCRYPTION_KEY`, CORS). Sans fournisseur de trafic, aucun trafic n'est affiché (rien n'est inventé).

## Signature Android
Copier `android/key.properties.example` en `android/key.properties` et renseigner votre keystore ([GUIDE_APK_IPA.md](GUIDE_APK_IPA.md)).
