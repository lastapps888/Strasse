import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/features/widgets/navigation_widget_sync.dart';

void main() {
  group('Navigation widget launch links', () {
    test('accepts the native search URL with the HomeWidget marker', () {
      expect(
        NavigationWidgetSync.isQuickSearchUri(Uri.parse('strasse://widget/search?homeWidget')),
        isTrue,
      );
    });

    test('rejects URLs without the marker', () {
      expect(
        NavigationWidgetSync.isQuickSearchUri(Uri.parse('strasse://widget/search')),
        isFalse,
      );
    });

    test('rejects unrelated widget paths and schemes', () {
      expect(
        NavigationWidgetSync.isQuickSearchUri(Uri.parse('strasse://widget/map?homeWidget')),
        isFalse,
      );
      expect(
        NavigationWidgetSync.isQuickSearchUri(Uri.parse('https://widget/search?homeWidget')),
        isFalse,
      );
    });
  });
}
