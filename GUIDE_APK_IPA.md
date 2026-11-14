# Simple Guide: Building the APK (Android) and IPA (iPhone)

First, complete the installation ([INSTALLATION.md](INSTALLATION.md)) and configuration ([CONFIGURATION.md](CONFIGURATION.md)). All commands should be entered in a terminal from within the `strasse` directory.

## A. Android — APK file

1. Prepare: Run `tool/setup_platforms.sh` (only once), then execute `cp config/env.example.json config/env.json` and fill in your addresses.
2. Quick test (APK signed with the test key):
```bash
flutter build apk --release --dart-define-from-file=config/env.json
```
Resulting file: `build/app/outputs/flutter-apk/app-release.apk`. Copy it to your phone and open it (ensure you allow "unknown sources").
3. Version for publication (using your own personal key):
```bash
keytool -genkey -v -keystore android/strasse-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias strasse
cp android/key.properties.example android/key.properties    # then enter your passwords and the path (storeFile=../strasse-release.jks)
flutter build appbundle --release --dart-define-from-file=config/env.json   # .aab for the Play Store
flutter build apk --release --split-per-abi --dart-define-from-file=config/env.json
```
**Back up the `.jks` file and its passwords**: without them, it will be impossible to publish updates. Never share them.

## B. iPhone — IPA file (requires a Mac)

1. Install Xcode (via the App Store) and CocoaPods (`sudo gem install cocoapods`). 2. Run `tool/setup_platforms.sh`, then `cd ios && pod install && cd ..`.
3. Open `ios/Runner.xcworkspace` in Xcode → select the **Runner** target → *Signing & Capabilities*: choose your **Team** (a free Apple account is sufficient for testing on your iPhone; a paid developer account is required for the App Store/TestFlight). Change the *Bundle Identifier* if it is already in use.
4. Build:
```bash
flutter build ipa --release --dart-define-from-file=config/env.json
```
Resulting file: `build/ios/ipa/*.ipa`. To upload to the App Store/TestFlight, use Apple’s "Transporter" app or `xcrun altool`. 
For a quick test: run `flutter run --release --dart-define-from-file=config/env.json` with your iPhone connected.

## Troubleshooting
- "flutter.sdk not defined": run `flutter pub get`.
- Compilation errors: this code could not be compiled by its author; copy the full error message, as it will indicate the specific file and line that need to be fixed.
- Empty map: `STRASSE_TILES_URL` / `STRASSE_GLYPHS_URL` are either not set or unreachable.
