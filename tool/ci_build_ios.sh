#!/usr/bin/env bash
# Compile l'application iOS et produit une IPA. Usage : bash tool/ci_build_ios.sh [unsigned|signed]
#
# unsigned (défaut) : IPA NON signée, destinée au sideloading (AltStore, SideStore, Sideloadly…) qui la signent avec VOTRE
#   identifiant Apple gratuit au moment de l'installation. Aucun compte développeur payant requis. C'est le mode adapté à une
#   distribution par GitHub Releases.
# signed : IPA signée par un compte Apple Developer payant (Ad Hoc / App Store / Entreprise). Nécessite que Codemagic ait
#   chargé le certificat et le profil (section « iOS code signing » de Codemagic, ou `xcode-project use-profiles`) et que
#   le profil corresponde à l'identifiant fr.strasse.strasse. Sortie : build/ios/ipa/*.ipa
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-unsigned}"
bash tool/ci_prepare.sh ios
( cd ios && pod install --repo-update )

# Ne jamais compiler avec les URL d'exemple (exemple.org) : seules les variables réellement définies
# sont transmises. Sans surcharge, l'application utilise les fournisseurs recommandés du catalogue.
DEFINES=()
for NAME in STRASSE_ENV STRASSE_API_URL STRASSE_TILES_URL STRASSE_TILES_ATTRIBUTION STRASSE_GLYPHS_URL STRASSE_MAP_FONT STRASSE_VALHALLA_URL STRASSE_GEOCODER_URL STRASSE_OTP_URL STRASSE_OVERPASS_URL STRASSE_SUPABASE_URL STRASSE_SUPABASE_ANON_KEY STRASSE_OPENTRIPMAP_KEY STRASSE_SPOTIFY_CLIENT_ID STRASSE_YOUTUBE_IOS_CLIENT_ID STRASSE_YOUTUBE_SERVER_CLIENT_ID STRASSE_GOOGLE_PLACES_API_KEY STRASSE_CONTACT; do
  VALUE="${!NAME:-}"
  if [ -n "$VALUE" ]; then
    DEFINES+=("--dart-define=$NAME=$VALUE")
  fi
done

flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
if [ "$mode" = "signed" ]; then
  if command -v xcode-project >/dev/null 2>&1; then xcode-project use-profiles; fi
  BUILD_ARGS=(flutter build ipa --release "${DEFINES[@]}")
  if [ -n "${EXPORT_OPTIONS_PLIST:-}" ]; then
    BUILD_ARGS+=(--export-options-plist "$EXPORT_OPTIONS_PLIST")
  fi
  "${BUILD_ARGS[@]}"
  ls -l build/ios/ipa/
else
  flutter build ios --release --no-codesign "${DEFINES[@]}"
  rm -rf build/ios/ipa-unsigned && mkdir -p build/ios/ipa-unsigned/Payload
  cp -R build/ios/iphoneos/Runner.app build/ios/ipa-unsigned/Payload/
  ( cd build/ios/ipa-unsigned && zip -qry Strasse-unsigned.ipa Payload && rm -rf Payload )
  ls -l build/ios/ipa-unsigned/
fi
