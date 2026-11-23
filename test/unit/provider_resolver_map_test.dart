import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/core/config/app_config.dart';
import 'package:strasse/features/services/provider_models.dart';
import 'package:strasse/features/services/provider_resolver.dart';
import 'package:strasse/features/settings/settings_model.dart';

void main() {
  group('Map provider fallback candidates', () {
    ProviderResolver makeResolver({bool autoFallback = true, Map<String, String> selections = const {}}) => ProviderResolver(
          AppSettings(autoFallback: autoFallback, providerSelections: selections),
          const AppConfig(
            env: 'test',
            apiUrl: '',
            tilesUrl: '',
            tilesAttribution: '',
            glyphsUrl: '',
            mapFont: 'Noto Sans Regular',
            valhallaUrl: '',
            geocoderUrl: '',
            otpUrl: '',
          ),
        );

    test('returns an independent backup after the default OpenFreeMap source', () {
      expect(makeResolver().mapCandidates().map((p) => p.id), ['openfreemap', 'versatiles-demo']);
    });

    test('keeps the explicitly selected style first', () {
      expect(
        makeResolver(selections: const {'tiles': 'openfreemap-liberty'}).mapCandidates().map((p) => p.id),
        ['openfreemap-liberty', 'openfreemap', 'versatiles-demo'],
      );
    });

    test('does not fail over when the user disabled automatic switching', () {
      expect(
        makeResolver(autoFallback: false, selections: const {'tiles': 'openfreemap-liberty'}).mapCandidates().map((p) => p.id),
        ['openfreemap-liberty'],
      );
    });

    test('builds a direct MapLibre style source for VersaTiles', () {
      final r = makeResolver();
      final fallback = r.mapCandidates().last;
      final source = r.mapSource(provider: fallback);
      expect(source.styleUrl, fallback.baseUrl);
      expect(source.tilesUrl, isEmpty);
      expect(source.glyphsUrl, isEmpty);
      expect(source.available, isTrue);
    });
  });
}
