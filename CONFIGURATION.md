#Service Configuration

No private keys should be included within the application (as a mobile app is considered public). Service addresses can be specified at compile time (`config/env.json`) **or** within the application itself (under Settings > Services, which takes precedence). All addresses must use **HTTPS**.

| Variable | Role | Required |
|---|---|---|
| `STRASSE_ENV` | `dev`, `test`, `prod` | no |
| `STRASSE_TILES_URL` | Vector TileJSON (OpenMapTiles schema) or `{z}/{x}/{y}` template | **yes** (to display the map) |
| `STRASSE_TILES_ATTRIBUTION` | Tile provider credit (displayed) | recommended |
| `STRASSE_GLYPHS_URL` | Map fonts: `…/{fontstack}/{range}.pbf` | yes (for labels) |
| `STRASSE_MAP_FONT` | Font stack available on this server | no |
| `STRASSE_VALHALLA_URL` | Valhalla server (car, walking, cycling) | **yes** (for online routing) |
| `STRASSE_GEOCODER_URL` | Nominatim-compatible server | **yes** (for search) |
| `STRASSE_OTP_URL` | OpenTripPlanner (powered by GTFS data) | no (if omitted: no public transit) |
| `STRASSE_OVERPASS_URL` | Overpass API endpoint (`…/api/interpreter`) | no (for downloading offline routes) |
| `STRASSE_API_URL` | Strasse backend (accounts, synchronization, reports, traffic) | no |

What you need to host or select:
- **Tiles + fonts**: An OpenMapTiles-compatible service (e.g., a self-hosted tile server, or a provider whose terms of service permit your intended use). - **Valhalla**: To be built using OSM extracts for your specific regions (refer to the Valhalla documentation).
- **Nominatim**: Self-hosted, or a service with a usage policy that permits such application use. The public `nominatim.openstreetmap.org` server prohibits intensive application-based usage; do not use it in a production environment.
- **Overpass**: A public instance is suitable for small, occasional data retrievals; please adhere to its usage policy.
- **OpenStreetMap Data**: © OpenStreetMap contributors (ODbL). Attribution is displayed within the application.

## Backend
Variables in `backend/.env.example` (secrets to be generated, `DATABASE_URL`, `REDIS_URL`, `ADMIN_TOKEN`, `TRAFFIC_PROVIDER`, `TOMTOM_API_KEY`, `SYNC_ENCRYPTION_KEY`, CORS). If no traffic provider is configured, no traffic data will be displayed (no data is fabricated).

## Android Signing
Copier `android/key.properties.example` en `android/key.properties` et renseigner votre keystore ([GUIDE_APK_IPA.md](GUIDE_APK_IPA.md)).
