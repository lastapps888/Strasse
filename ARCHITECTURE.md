# Architecture

## Layers (Flutter)

```
lib/
main.dart            startup, database, Riverpod overrides, loading screen
app/                 theme (Material You), common widgets, navigation, text styles
core/                configuration, error handling (Failure), geo/formatting utilities, storage (SQLite, preferences, secure storage)
domain/              entities (locations, routes, favorites, trips, offline data, etc.)
data/                clients (Valhalla, Nominatim, OTP, Strasse API), SQLite repositories, Riverpod providers
features/            one folder per module: map, location, routing, navigation, search, offline_maps,
offline_routing, traffic, places, favorites, trips, home, settings, privacy, sync,
notifications, assistant, profile
```

- **State**: Riverpod 2 (`StateNotifier`). All providers are located in `data/providers/providers.dart`.
- **Screen Navigation**: Navigator 1.0; tabs (Home, Map, Trips, Favorites, Settings) are defined in `app/shell.dart`.
- **Error Handling**: All network/storage errors are converted into a `Failure` object, containing a pre-formatted message in French ready for display.
- **Configuration**: Managed via `--dart-define-from-file` with user-defined overrides available under Settings > Services (HTTPS required).

## Routing

The `RoutingService` selects the appropriate provider: Valhalla (online), OpenTripPlanner (for public transit), or a **local engine** if Valhalla is unreachable (due to lack of connectivity, timeout, or missing configuration).

### Offline Routing Engine (`features/offline_routing`)
- `graph_builder.dart`: Converts Overpass JSON responses into a compact graph (typed arrays, edges between intersections, geometry, and access flags).
- `routing_graph.dart`: Contains the graph structure, CSR (Compressed Sparse Row) adjacency, a spatial grid, and the custom "STG1" binary format. - `local_router.dart`: snapping to the nearest edge, A* algorithm, mode-specific costs, and navigation maneuvers (using Valhalla-style types to ensure `NavigationEngine` functions consistently).
- `routing_graph_store.dart`: handles Overpass API downloads, conversion into an isolated format, storage in `<support>/routing/`, and loading upon application startup.

## Navigation
`NavigationEngine` (pure Dart, testable) projects the current position onto the route, announces maneuvers, and detects route deviations. `NavigationController` adds functionality for route recalculation, GPS signal loss monitoring, incident reporting, history tracking, and keeping the screen awake.

## Privacy
No telemetry or trackers. History and statistics can be disabled or deleted. An anonymous installation identifier is used (exclusively for incident reporting). Server addresses are never synchronized.
