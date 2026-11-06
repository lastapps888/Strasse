# Guide simple : construire l'APK (Android) et l'IPA (iPhone)

Faites d'abord l'installation ([INSTALLATION.md](INSTALLATION.md)) et la configuration ([CONFIGURATION.md](CONFIGURATION.md)). Toutes les commandes se tapent dans un terminal, dans le dossier `strasse`.

## A. Android — fichier APK

1. Préparer : `tool/setup_platforms.sh` (une seule fois), puis `cp config/env.example.json config/env.json` et remplissez vos adresses.
2. Test rapide (APK signé avec la clé de test) :
   ```bash
   flutter build apk --release --dart-define-from-file=config/env.json
   ```
   Fichier obtenu : `build/app/outputs/flutter-apk/app-release.apk`. Copiez-le sur le téléphone et ouvrez-le (autorisez « sources inconnues »).
3. Version à publier (clé personnelle) :
   ```bash
   keytool -genkey -v -keystore android/strasse-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias strasse
   cp android/key.properties.example android/key.properties    # puis renseignez mots de passe et chemin (storeFile=../strasse-release.jks)
   flutter build appbundle --release --dart-define-from-file=config/env.json   # .aab pour le Play Store
   flutter build apk --release --split-per-abi --dart-define-from-file=config/env.json
   ```
   **Sauvegardez le fichier `.jks` et ses mots de passe** : sans eux, impossible de publier une mise à jour. Ne les partagez jamais.

## B. iPhone — fichier IPA (il faut un Mac)

1. Installer Xcode (App Store) et CocoaPods (`sudo gem install cocoapods`).
2. `tool/setup_platforms.sh`, puis `cd ios && pod install && cd ..`.
3. Ouvrir `ios/Runner.xcworkspace` dans Xcode → cible **Runner** → *Signing & Capabilities* : choisir votre **Team** (un compte Apple gratuit suffit pour tester sur votre iPhone ; le compte développeur payant est nécessaire pour l'App Store/TestFlight). Changer le *Bundle Identifier* s'il est déjà pris.
4. Construire :
   ```bash
   flutter build ipa --release --dart-define-from-file=config/env.json
   ```
   Fichier obtenu : `build/ios/ipa/*.ipa`. Envoi vers l'App Store/TestFlight : application « Transporter » d'Apple, ou `xcrun altool`.
   Pour un simple test : `flutter run --release --dart-define-from-file=config/env.json` avec l'iPhone branché.

## En cas de problème
- « flutter.sdk non défini » : lancez `flutter pub get`.
- Erreurs de compilation : ce code n'a pas pu être compilé par son auteur ; copiez le message d'erreur complet, il indique le fichier et la ligne à corriger.
- Carte vide : `STRASSE_TILES_URL` / `STRASSE_GLYPHS_URL` non renseignés ou injoignables.
