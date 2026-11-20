#!/usr/bin/env bash
# Prépare un dépôt fraîchement cloné pour la compilation (Codemagic ou poste local).
#
#   bash tool/ci_prepare.sh android     # APK
#   bash tool/ci_prepare.sh ios         # iOS / IPA
#   bash tool/ci_prepare.sh all
#
# 1. complète android/ et/ou ios/ avec `flutter create` UNIQUEMENT pour les fichiers manquants (gradlew, Runner.xcodeproj…) ;
#    les fichiers déjà versionnés ne sont jamais écrasés ;
# 2. applique la configuration Strasse (tool/patch_platforms.py : Gradle, icônes, manifestes, Info.plist, icônes alternatives iOS) ;
# 3. flutter pub get.
set -euo pipefail
cd "$(dirname "$0")/.."
target="${1:-all}"

flutter config --no-analytics >/dev/null 2>&1 || true
dart --disable-telemetry >/dev/null 2>&1 || true

platforms=""
case "$target" in
  android) platforms="android" ;;
  ios) platforms="ios" ;;
  all) platforms="android,ios" ;;
  *) echo "Usage : $0 android|ios|all" >&2; exit 2 ;;
esac

# `flutter create` est lancé dès qu'il manque le projet Xcode (cause de « Missing ios/Runner.xcodeproj ») ou le script Gradle.
need_create=0
case "$platforms" in *android*) [ -f android/gradlew ] || need_create=1 ;; esac
case "$platforms" in *ios*) [ -f ios/Runner.xcodeproj/project.pbxproj ] || need_create=1 ;; esac
if [ "$need_create" = 1 ]; then
  flutter create --org fr.strasse --project-name strasse --platforms "$platforms" .
fi

python3 tool/patch_platforms.py
flutter pub get

case "$platforms" in
  *ios*)
    [ -f ios/Runner.xcodeproj/project.pbxproj ] || { echo "ERREUR : ios/Runner.xcodeproj/project.pbxproj est toujours absent après flutter create." >&2; exit 1; }
    ;;
esac
echo "Plateformes prêtes ($platforms)."
