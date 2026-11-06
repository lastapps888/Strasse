# Suivi d'avancement (fichier de reprise)

## Fait
- Logo + icônes, backend complet (non exécuté), configuration, scripts de plateformes.
- core, domain, data (dépôts, clients), moteurs (navigation, localisation, voix, notifications, routage, synchro, assistant, style de carte, cartes hors connexion).
- providers.dart, contrôleurs (réglages, compte, trafic), thème, logo vectoriel, widgets communs, main/app/shell.

## À faire (dans l'ordre)
1. features/search : search_page.dart, place_sheet.dart
2. features/map/map_screen.dart (+ report_sheet)
3. features/routing : route_preview_page.dart
4. features/navigation : navigation_controller.dart, navigation_page.dart
5. features/home/home_screen.dart
6. features/trips : trips_screen.dart, planner_page.dart, statistics_page.dart
7. features/favorites/favorites_screen.dart (+ collection page)
8. features/offline_maps/offline_page.dart
9. features/sync : account_page.dart ; features/assistant : assistant_page.dart
10. features/settings/settings_screen.dart + sous-pages ; features/profile/onboarding_page.dart
11. Hors connexion : routage local (voir décision) 
12. Tests Dart, documentation, android/ et ios/ complets, ZIP final.
- (progress) Fait: search, place_sheet, map_screen, report_sheet, route_preview, route_options, navigation (controller+page), home, trips (screen, planner, stats). Reste: favorites, offline page, account, assistant, settings, onboarding, hors-ligne routing, tests, docs, android/ios, zip
- (maj) Rendu de référence : docs/design/reference_rendu.jpg (vert #5B8F57, boutons pilule, barre d'onglets plate, navigation sombre). Appliqué : thème, shell, accueil, navigation, aperçu itinéraire, favoris, onboarding.
- Écrits : favorites, offline_page, account, assistant, settings (+pages, services, about), privacy, onboarding.
- RESTE : (a) revue de cohérence de tous les fichiers Dart (symboles/imports) ; (b) routage hors connexion ; (c) tests Dart ; (d) docs ; (e) android/ et ios/ complets ; (f) ZIP final.
- (maj 6 nov, apparence) Material You natif : dynamic_color (DynamicColorBuilder dans app.dart et navigation_page), réglage useDynamicColor, transitions Cupertino sur iOS ; logo/icônes régénérés aux couleurs de la maquette (tool/generate_logo.py + render_icons.js), painter Dart aligné sur le SVG. Hors-ligne : local_router.dart écrit ; RESTE : stockage des graphes + téléchargement (URL Overpass à ajouter à la config), branchement providers, puis consignes précédentes.
- (6 nov) TERMINÉ : routage hors connexion (router+store+UI+providers), tests, docs FR, android/ios natifs, thème Material You, icônes. ZIP final généré. Non vérifié: tout (voir docs/LIMITES.md).
