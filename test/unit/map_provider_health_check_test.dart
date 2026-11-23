import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/core/config/app_config.dart';
import 'package:strasse/features/map/map_provider_health_check.dart';
import 'package:strasse/features/services/provider_catalog.dart';
import 'package:strasse/features/services/provider_models.dart';
import 'package:strasse/features/services/provider_resolver.dart';
import 'package:strasse/features/settings/settings_model.dart';

class _MapResponseAdapter implements HttpClientAdapter {
  _MapResponseAdapter(this.body, {this.statusCode = 200});

  final String body;
  final int statusCode;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

ProviderResolver _resolver({Map<String, String> selections = const {}, bool autoFallback = true}) => ProviderResolver(
      AppSettings(providerSelections: selections, autoFallback: autoFallback),
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

void main() {
  group('Map provider health check', () {
    test('accepts a usable MapLibre style document', () async {
      final adapter = _MapResponseAdapter('{"version":8,"sources":{"osm":{"type":"vector","url":"https://tiles.example/data.json"}},"layers":[{"id":"background","type":"background"}]}');
      final dio = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = adapter;
      final resolver = _resolver();
      final provider = resolver.all(ServiceCategory.tiles).singleWhere((p) => p.id == 'versatiles-demo');
      final checker = MapProviderHealthCheck(userAgent: 'Strasse/test', dio: dio);

      expect(await checker.isHealthy(provider, resolver), isTrue);
      expect(adapter.requests.single.uri.toString(), provider.baseUrl);
      checker.close();
    });

    test('rejects a MapLibre document without sources or layers', () async {
      final adapter = _MapResponseAdapter('{"version":8,"sources":{},"layers":[]}');
      final dio = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = adapter;
      final resolver = _resolver();
      final provider = resolver.all(ServiceCategory.tiles).singleWhere((p) => p.id == 'versatiles-demo');
      final checker = MapProviderHealthCheck(userAgent: 'Strasse/test', dio: dio);

      expect(await checker.isHealthy(provider, resolver), isFalse);
      checker.close();
    });

    test('accepts a valid TileJSON document', () async {
      final adapter = _MapResponseAdapter('{"tilejson":"3.0.0","tiles":["https://tiles.example/{z}/{x}/{y}.pbf"]}');
      final dio = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = adapter;
      final resolver = _resolver();
      final provider = resolver.all(ServiceCategory.tiles).singleWhere((p) => p.id == 'openfreemap');
      final checker = MapProviderHealthCheck(userAgent: 'Strasse/test', dio: dio);

      expect(await checker.isHealthy(provider, resolver), isTrue);
      checker.close();
    });

    test('rejects unavailable servers', () async {
      final adapter = _MapResponseAdapter('{"error":"unavailable"}', statusCode: 503);
      final dio = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = adapter;
      final resolver = _resolver();
      final provider = resolver.all(ServiceCategory.tiles).singleWhere((p) => p.id == 'versatiles-demo');
      final checker = MapProviderHealthCheck(userAgent: 'Strasse/test', dio: dio);

      expect(await checker.isHealthy(provider, resolver), isFalse);
      checker.close();
    });
  });
}
