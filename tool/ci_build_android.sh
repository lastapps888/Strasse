#!/usr/bin/env bash
# Compile l'APK release. Usage : bash tool/ci_build_android.sh
# Signature : si android/key.properties existe (ou si CM_KEYSTORE_PATH est défini, Codemagic), l'APK est signé avec votre clé ;
# sinon avec la clé de debug (installable, mais Android refusera de le mettre à jour par-dessus une version signée autrement).
set -euo pipefail
cd "$(dirname "$0")/.."
bash tool/ci_prepare.sh android
if [ -n "${CM_KEYSTORE_PATH:-}" ]; then
  printf 'storeFile=%s\nstorePassword=%s\nkeyAlias=%s\nkeyPassword=%s\n' "$CM_KEYSTORE_PATH" "$CM_KEYSTORE_PASSWORD" "$CM_KEY_ALIAS" "$CM_KEY_PASSWORD" > android/key.properties
fi
# Ne jamais compiler avec les URL factices du fichier env.example.json.
# Les variables sont injectées uniquement lorsqu'elles ont réellement été configurées.
DEFINES=()
for NAME in STRASSE_ENV STRASSE_API_URL STRASSE_TILES_URL STRASSE_TILES_ATTRIBUTION STRASSE_GLYPHS_URL STRASSE_MAP_FONT STRASSE_VALHALLA_URL STRASSE_GEOCODER_URL STRASSE_OTP_URL STRASSE_OVERPASS_URL STRASSE_SUPABASE_URL STRASSE_SUPABASE_ANON_KEY STRASSE_OPENTRIPMAP_KEY STRASSE_SPOTIFY_CLIENT_ID STRASSE_YOUTUBE_IOS_CLIENT_ID STRASSE_YOUTUBE_SERVER_CLIENT_ID STRASSE_GOOGLE_PLACES_API_KEY STRASSE_CONTACT; do
  VALUE="${!NAME:-}"
  if [ -n "$VALUE" ]; then
    DEFINES+=("--dart-define=$NAME=$VALUE")
  fi
done
flutter analyze
flutter test
flutter build apk --release "${DEFINES[@]}"
ls -l build/app/outputs/flutter-apk/
