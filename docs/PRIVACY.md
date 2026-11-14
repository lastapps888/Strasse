# Privacy and No Tracking

Objective: No usage data leaves the device without user action, and nothing is sent to Google by the application.

## What the project does

- No dependencies on Firebase, Analytics, advertising, crash reporting, Google Fonts, or Google Maps (verified by `tool/check_privacy.sh` across `pubspec.*`, `lib/`, Gradle files, and manifests).
- `allowBackup="false"`: Application data is not included in Google Drive backups.
- Location: `geolocator` is configured with `forceLocationManager: true` on Android. Location data is retrieved via the system’s `LocationManager`, bypassing the Google Play Services fused location provider.
- Development tools: `tool/setup_platforms.sh` executes `flutter config --no-analytics` and `dart --disable-telemetry`.
- Network services (maps, search, routing, etc.) receive only the data strictly required for the specific request. See the Settings > Privacy screen.
- Feedback is sent only upon explicit user action and contains only the text written by the user.

## What the project cannot guarantee
- Text-to-speech (TTS) relies on the system’s native engine. On Android, this is often the Google TTS engine; its behavior—such as whether it operates offline or which voices are downloaded—is determined by the device's own settings.
- Map servers, geocoders, Valhalla, Overpass, and Transitous will receive the device's IP address along with the requested area or coordinates. To avoid this, you may host these services yourself.
