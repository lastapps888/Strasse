#!/usr/bin/env bash
# Génère les projets Android et iOS avec `flutter create`, puis applique la configuration Strasse
# (nom, icônes, permissions en français, arrière-plan, signature, desugaring…).
#
# Usage : tool/setup_platforms.sh [identifiant_organisation]    (défaut : fr.strasse)
# Le Bundle ID / applicationId devient <organisation>.strasse — modifiable ensuite dans Xcode / build.gradle.
set -euo pipefail
cd "$(dirname "$0")/.."

ORG="${1:-fr.strasse}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter est introuvable dans le PATH. Voir INSTALLATION.md." >&2
  exit 1
fi

flutter create --org "$ORG" --project-name strasse --platforms android,ios .
python3 tool/patch_platforms.py
flutter pub get

echo
echo "Plateformes configurées. Étapes suivantes :"
echo "  1. cp config/env.example.json config/env.json   (puis renseigner vos services)"
echo "  2. flutter run --dart-define-from-file=config/env.json"
echo "  3. Voir INSTALLATION.md pour la signature et les builds de production."
