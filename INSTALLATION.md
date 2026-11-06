# Installation

## Prérequis
- Flutter ≥ 3.27 (Dart ≥ 3.6), Android Studio (SDK Android, Java 17) pour Android, **macOS + Xcode + CocoaPods** pour iOS.
- Python 3 (script de configuration des plateformes).
- Backend facultatif : Node ≥ 20, Docker.

## Mise en place
```bash
cd strasse
tool/setup_platforms.sh          # option : tool/setup_platforms.sh com.votresociete  (identifiant d'organisation)
cp config/env.example.json config/env.json   # puis éditer
flutter run --dart-define-from-file=config/env.json
```
Le script lance `flutter create` (qui complète les fichiers manquants, dont le projet Xcode `Runner.xcodeproj`, sans écraser les fichiers fournis), applique les réglages Strasse (idempotent) et lance `flutter pub get`.

> L'identifiant d'application fourni est `fr.strasse.strasse`. Pour le changer : `applicationId`/`namespace` dans `android/app/build.gradle.kts` (et le dossier Kotlin) et « Bundle Identifier » dans Xcode.

## Android
Android Gradle Plugin 8.7.3, Gradle 8.10.2, Kotlin 2.0.21, minSdk 24. Le fichier `gradle-wrapper.jar` n'est pas fourni (binaire) : Flutter le recrée au premier `flutter build`.

## iOS
Cible iOS 13+. Après `setup_platforms.sh` : `cd ios && pod install`, puis ouvrir `ios/Runner.xcworkspace` dans Xcode, choisir votre équipe de signature (Signing & Capabilities).

## Backend
Voir `backend/README.md` : `docker compose up` lance PostgreSQL/PostGIS, Redis et l'API ; les migrations sont dans `backend/migrations`.
