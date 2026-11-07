# Limites et points non vérifiés (honnêteté)

## Limites fonctionnelles
- **Cartes hors connexion** : le plugin cartographique ne permet que d'annuler et de mettre à jour un téléchargement, pas de le mettre en pause/reprise.
- **Internationalisation** : interface en français ; le reste du système (dates, boutons système) suit les paquets de localisation Flutter.
- **Transports en commun** : nécessitent un serveur OpenTripPlanner avec données GTFS ; sans lui, le mode est indiqué comme indisponible.
- **Trafic** : seulement via le fournisseur configuré côté backend ; sans lui, aucun trafic n'est affiché.
