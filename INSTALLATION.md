# Installation

## Prerequisites
- Flutter ≥ 3.27 (Dart ≥ 3.6), Android Studio (Android SDK, Java 17) for Android, **macOS + Xcode + CocoaPods** for iOS.
- Python 3 (for the platform setup script).
- Optional backend: Node ≥ 20, Docker.

## Setup
```bash
cd strasse
tool/setup_platforms.sh          # optional: tool/setup_platforms.sh com.yourcompany (organization identifier)
cp config/env.example.json config/env.json   # then edit
flutter run --dart-define-from-file=config/env.json
```
The script runs `flutter create` (which fills in missing files—including the Xcode project `Runner.xcodeproj`—without overwriting existing files), applies Strasse-specific configurations (idempotent), and executes `flutter pub get`.

> The default application identifier is `fr.strasse.strasse`. To change it, update `applicationId`/`namespace` in `android/app/build.gradle.kts` (as well as the Kotlin directory structure) and the "Bundle Identifier" in Xcode.

## Android
Android Gradle Plugin 8.7.3, Gradle 8.10.2, Kotlin 2.0.21, minSdk 24. The `gradle-wrapper.jar` file is not included (as it is a binary); Flutter will regenerate it during the first `flutter build`.

## iOS
Targets iOS 13+. After running `setup_platforms.sh`, execute `cd ios && pod install`, then open `ios/Runner.xcworkspace` in Xcode and select your signing team under "Signing & Capabilities."

## Backend
Refer to `backend/README.md`: running `docker compose up` will launch PostgreSQL/PostGIS, Redis, and the API. Database migrations are located in `backend/migrations`.
