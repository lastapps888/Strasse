#!/usr/bin/env bash
# Vérifie que le projet n'embarque aucun traqueur connu (Firebase, Analytics, publicité, polices Google, rapports
# de plantage) et n'appelle aucun domaine Google dans le code. Ne remplace pas une analyse du binaire final.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

bad_deps='firebase|google_mobile_ads|google_fonts|google_sign_in|google_maps|crashlytics|sentry|appsflyer|adjust_sdk|mixpanel|amplitude|facebook|onesignal|google_analytics'
for f in pubspec.yaml pubspec.lock; do
  [ -f "$f" ] || continue
  if grep -Eiq "^\s*($bad_deps)" "$f"; then
    echo "ÉCHEC : dépendance de suivi dans $f :"; grep -Ein "^\s*($bad_deps)" "$f"; fail=1
  fi
done

if [ -d lib ]; then
  if grep -rEn "googleapis\.com|gstatic\.com|google-analytics|firebase|app-measurement|googletagmanager|fonts\.google" lib --include=*.dart | grep -v "^lib/.*//.*privacy" ; then
    echo "ÉCHEC : appel à un domaine de suivi ou Google dans lib/."; fail=1
  fi
fi

for f in android/app/build.gradle android/app/build.gradle.kts android/build.gradle android/build.gradle.kts; do
  [ -f "$f" ] || continue
  if grep -Ein "firebase|crashlytics|google-services|play-services-ads|play-services-analytics" "$f"; then
    echo "ÉCHEC : SDK de suivi dans $f"; fail=1
  fi
done
[ -f android/app/google-services.json ] && { echo "ÉCHEC : google-services.json présent"; fail=1; }
[ -f ios/Runner/GoogleService-Info.plist ] && { echo "ÉCHEC : GoogleService-Info.plist présent"; fail=1; }

if [ -f android/app/src/main/AndroidManifest.xml ]; then
  grep -q 'android:allowBackup="false"' android/app/src/main/AndroidManifest.xml || { echo "ÉCHEC : allowBackup doit être false (pas de sauvegarde Google Drive des données)."; fail=1; }
fi

if [ "$fail" -eq 0 ]; then
  echo "Confidentialité : aucun traqueur connu trouvé (dépendances, code, Gradle, manifestes)."
  echo "Rappel : geolocator_android référence encore play-services-location, non utilisé (forceLocationManager: true). Voir docs/CONFIDENTIALITE.md."
fi
exit "$fail"
