# Architecture

## Couches (Flutter)

```
lib/
  main.dart            démarrage, base de données, surcharges Riverpod, écran d'attente
  app/                 thème (Material You), widgets communs, navigation, textes
  core/                configuration, erreurs (Failure), utilitaires géo/format, stockage (SQLite, préférences, coffre sécurisé)
  domain/              entités (lieux, itinéraires, favoris, trajets, hors-ligne…)
  data/                clients (Valhalla, Nominatim, OTP, API Strasse), dépôts SQLite, providers Riverpod
  features/            un dossier par module : map, location, routing, navigation, search, offline_maps,
                       offline_routing, traffic, places, favorites, trips, home, settings, privacy, sync,
                       notifications, assistant, profile
```

- **État** : Riverpod 2 (`StateNotifier`). Tous les providers sont dans `data/providers/providers.dart`.
- **Navigation d'écrans** : Navigator 1.0, onglets (Accueil, Carte, Trajets, Favoris, Réglages) dans `app/shell.dart`.
- **Erreurs** : toute erreur réseau/stockage est convertie en `Failure` avec un message français prêt à afficher.
- **Configuration** : `--dart-define-from-file` + surcharge utilisateur dans Réglages > Services (HTTPS exigé).

## Itinéraires

`RoutingService` choisit : Valhalla en ligne ; OpenTripPlanner pour les transports ; **moteur local** si Valhalla est injoignable (hors connexion, délai dépassé, non configuré).

### Moteur d'itinéraires hors connexion (`features/offline_routing`)
- `graph_builder.dart` : réponse Overpass JSON → graphe compact (tableaux typés, arêtes entre intersections, géométrie, drapeaux d'accès).
- `routing_graph.dart` : graphe, adjacence CSR, grille spatiale, format binaire « STG1 ».
- `local_router.dart` : accrochage à l'arête la plus proche, A*, coûts par mode, manœuvres en français (types Valhalla pour que `NavigationEngine` fonctionne à l'identique).
- `routing_graph_store.dart` : téléchargement Overpass, conversion en isolat, fichiers dans `<support>/routing/`, chargement au démarrage.

## Navigation
`NavigationEngine` (pur Dart, testable) projette la position sur l'itinéraire, annonce les manœuvres, détecte l'écart de trajet ; `NavigationController` ajoute recalcul, surveillance de perte de GPS, alertes de signalements, historique, écran allumé.

## Vie privée
Aucune télémétrie ni traceur. Historique et statistiques désactivables, effaçables. Identifiant d'installation anonyme (utilisé seulement pour les signalements). Les adresses de serveurs ne sont jamais synchronisées.

## Backend (facultatif)
Fastify + TypeScript ; PostgreSQL/PostGIS ; Redis (anti-abus/cache, repli mémoire) ; JWT + rotation de jetons ; synchronisation « dernière écriture gagne » ; signalements avec expiration et dédoublonnage ; fournisseur de trafic en option. Détails : `backend/README.md`.
