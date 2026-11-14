# Functional Limitations
- **Offline Routes**: Downloads are limited to an area roughly 1,000 km by 1,000 km. **WARNING**: Downloading maps with excessive detail may fill up your storage and cause the application to run slowly.
- **Offline Maps**: The mapping plugin only supports canceling or updating a download; pausing or resuming is not possible.
- **Location Photos**: No data source is configured, so no photos are displayed (no data is fabricated). Favorite collections use gradients.
- **Public Transit**: Requires an OpenTripPlanner server with GTFS data; otherwise, this mode is marked as unavailable.
- **Traffic**: Available only via a backend-configured provider; if none is configured, no traffic data is displayed.
- **Native Android/iOS files** are manually authored based on Flutter 3.27 templates. The Xcode project (`Runner.xcodeproj`) is generated via `flutter create` (via `tool/setup_platforms.sh`), as a manually written `project.pbxproj` would be too risky. The `gradle-wrapper.jar` (binary) is recreated by Flutter.
- **OpenTripPlanner Integration (Transit):** Not fully functional.
- **Material You**: Relies on `dynamic_color`; the effect is only visible on Android 12+.
