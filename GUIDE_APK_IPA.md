# Simple Guide: Building the APK (Android) and IPA (iPhone)

First, complete the installation ([INSTALLATION.md](INSTALLATION.md)) and configuration ([CONFIGURATION.md](CONFIGURATION.md)). All commands should be entered in a terminal from within the `strasse` directory.

## A. Android — APK file

1. Prepare: Run `bash tool/ci_prepare.sh android`, then execute `cp config/env.example.json config/env.json` and fill in your service URLs. This also generates the native 2×2 and 4×2 home-screen widgets.
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

1. Install Xcode (via the App Store) and CocoaPods (`sudo gem install cocoapods`). 2. Run `bash tool/ci_prepare.sh ios`, then `cd ios && pod install && cd ..`.
3. Open `ios/Runner.xcworkspace` in Xcode → select the **Runner** and **StrasseNavigationWidget** targets → *Signing & Capabilities*: choose your **Team**. The widget shares data through the App Group `group.fr.strasse.strasse`, which must be registered and enabled for both targets in the Apple Developer account; this capability requires paid Apple Developer Program membership. A free Apple account can test the main app without the iOS widget, but cannot provision the App Group entitlement. Change the *Bundle Identifier* and App Group in `home_widget/strasse_navigation.dart` together if the identifier is already in use.
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
