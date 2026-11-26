#!/usr/bin/env bash
# Prépare un dépôt fraîchement cloné pour la compilation (Codemagic ou poste local).
#
#   bash tool/ci_prepare.sh android     # APK
#   bash tool/ci_prepare.sh ios         # iOS / IPA
#   bash tool/ci_prepare.sh all
#
# 1. complète android/ et ios/ avec `flutter create` UNIQUEMENT si un projet natif manque ;
# 2. résout les dépendances Flutter (dont le générateur de widgets) ;
# 3. applique la configuration Strasse et génère les widgets natifs WidgetKit / Android Glance.
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

# La génération des widgets requiert les deux projets natifs, même lors d'une préparation ciblée Android ou iOS.
need_create=0
[ -f android/gradlew ] || need_create=1
[ -f ios/Runner.xcodeproj/project.pbxproj ] || need_create=1
if [ "$need_create" = 1 ]; then
  flutter create --org fr.strasse --project-name strasse --platforms android,ios .
fi

flutter pub get
python3 tool/patch_platforms.py

case "$platforms" in
  *ios*)
    [ -f ios/Runner.xcodeproj/project.pbxproj ] || { echo "ERREUR : ios/Runner.xcodeproj/project.pbxproj est toujours absent après flutter create." >&2; exit 1; }
    ;;
esac
echo "Plateformes prêtes ($platforms)."
