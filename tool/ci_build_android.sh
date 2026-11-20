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
flutter analyze
flutter test
flutter build apk --release --dart-define-from-file=config/env.example.json
ls -l build/app/outputs/flutter-apk/
