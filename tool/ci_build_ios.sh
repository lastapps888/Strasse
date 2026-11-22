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
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
if [ "$mode" = "signed" ]; then
  if command -v xcode-project >/dev/null 2>&1; then xcode-project use-profiles; fi
  flutter build ipa --release --dart-define-from-file=config/env.example.json ${EXPORT_OPTIONS_PLIST:+--export-options-plist="$EXPORT_OPTIONS_PLIST"}
  ls -l build/ios/ipa/
else
  flutter build ios --release --no-codesign --dart-define-from-file=config/env.example.json
  rm -rf build/ios/ipa-unsigned && mkdir -p build/ios/ipa-unsigned/Payload
  cp -R build/ios/iphoneos/Runner.app build/ios/ipa-unsigned/Payload/
  ( cd build/ios/ipa-unsigned && zip -qry Strasse-unsigned.ipa Payload && rm -rf Payload )
  ls -l build/ios/ipa-unsigned/
fi
