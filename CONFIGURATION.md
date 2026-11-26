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
| `STRASSE_SPOTIFY_CLIENT_ID` | Public Spotify PKCE Client ID (build-time value; can also be entered in Settings) | no (Spotify remains unavailable until an ID is supplied) |
| `STRASSE_API_URL` | Strasse backend (accounts, synchronization, reports, traffic) | no |

What you need to host or select:
- **Tiles + fonts**: An OpenMapTiles-compatible service (e.g., a self-hosted tile server, or a provider whose terms of service permit your intended use). - **Valhalla**: To be built using OSM extracts for your specific regions (refer to the Valhalla documentation).
- **Nominatim**: Self-hosted, or a service with a usage policy that permits such application use. The public `nominatim.openstreetmap.org` server prohibits intensive application-based usage; do not use it in a production environment.
- **Overpass**: A public instance is suitable for small, occasional data retrievals; please adhere to its usage policy.
- **OpenStreetMap Data**: © OpenStreetMap contributors (ODbL). Attribution is displayed within the application.

## Spotify

The Spotify Client ID is public application configuration and must be supplied by the Strasse publisher at build time through `STRASSE_SPOTIFY_CLIENT_ID`; end users must not be asked to create a developer app or enter this value. Without it, Spotify stays disabled. Development-mode apps are limited to 5 allowlisted Spotify accounts and the app owner must have Premium. Public extended quota is subject to Spotify approval; for new applications Spotify only accepts organizations that meet its eligibility requirements. A Client ID alone does not grant public access.


## Integrated music and reviews

These optional services use public client identifiers or API keys. They are never private secrets, but should still be restricted in their provider dashboards.

| Variable | Used for | Required |
|---|---|---|
| `STRASSE_YOUTUBE_IOS_CLIENT_ID` | Google OAuth client ID for the iOS app | iOS YouTube Music |
| `STRASSE_YOUTUBE_SERVER_CLIENT_ID` | Google OAuth Web/server client ID | YouTube Music |
| `STRASSE_YOUTUBE_REVERSED_CLIENT_ID` | Reversed iOS OAuth client ID, used by `tool/patch_platforms.py` to register the callback URL scheme | iOS YouTube Music |
| `STRASSE_GOOGLE_PLACES_API_KEY` | Google Places API (New) details, ratings and reviews | Google reviews |
| `STRASSE_OPENTRIPMAP_KEY` | OpenTripMap tourism information | Optional tourism enrichment |

### Spotify

Register the exact redirect URI `strasse://spotify-callback` in the Spotify developer dashboard. Set `STRASSE_SPOTIFY_CLIENT_ID` in the build environment or enter the public Client ID in **Settings → Services → Spotify → Credentials**. Strasse uses OAuth PKCE; no client secret belongs in the mobile app. Playback commands are sent to Spotify's active app/device and require the account and plan capabilities Spotify applies.

### YouTube Music

Create Google OAuth clients for the Web/server application and the iOS bundle identifier. For iOS, also set `STRASSE_YOUTUBE_REVERSED_CLIENT_ID` in the build environment so the native URL scheme is added before compilation. Enable the YouTube Data API v3 and configure the OAuth consent screen. The integration reads account playlists and searches videos; playback opens YouTube Music externally rather than streaming audio inside Strasse.

### Google Places reviews

Enable **Places API (New)** and configure billing/restrictions for the Android application ID and iOS bundle identifier. Enter the key in **Settings → Services → Avis Google Places → Identifiants**, or supply `STRASSE_GOOGLE_PLACES_API_KEY` at build time. Without a valid key and billing, the map and navigation continue to work but Google ratings/reviews are not requested.

### Public transport

`STRASSE_OTP_URL` must point to an OpenTripPlanner server built with a valid GTFS feed and OpenStreetMap street data. Strasse does not include a universal free public OTP endpoint; a deployment URL must be supplied by the operator.

## Backend
Variables in `backend/.env.example` (secrets to be generated, `DATABASE_URL`, `REDIS_URL`, `ADMIN_TOKEN`, `TRAFFIC_PROVIDER`, `TOMTOM_API_KEY`, `SYNC_ENCRYPTION_KEY`, CORS). If no traffic provider is configured, no traffic data will be displayed (no data is fabricated).

## Android Signing
Copier `android/key.properties.example` en `android/key.properties` et renseigner votre keystore ([GUIDE_APK_IPA.md](GUIDE_APK_IPA.md)).
