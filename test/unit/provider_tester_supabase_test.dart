import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/core/config/app_config.dart';
import 'package:strasse/features/services/provider_catalog.dart';
import 'package:strasse/features/services/provider_models.dart';
import 'package:strasse/features/services/provider_resolver.dart';
import 'package:strasse/features/services/provider_tester.dart';
import 'package:strasse/features/settings/settings_model.dart';

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this.responses);

  final List<ResponseBody> responses;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (responses.isEmpty) {
      throw StateError('No fake HTTP response remains.');
    }
    return responses.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(String body, int status) => ResponseBody.fromString(
      body,
      status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );

ProviderResolver _resolver() => const ProviderResolver(
      AppSettings(),
      AppConfig(
        env: 'test',
        apiUrl: '',
        tilesUrl: '',
        tilesAttribution: '',
        glyphsUrl: '',
        mapFont: 'Noto Sans Regular',
        valhallaUrl: '',
        geocoderUrl: '',
        otpUrl: '',
        supabaseUrl: 'https://project.supabase.co',
        supabaseAnonKey: 'sb_publishable_test',
      ),
    );

void main() {
  group('ProviderTester Supabase diagnostics', () {
    test('checks Auth and the Strasse REST schema with the publishable key', () async {
      final adapter = _QueueAdapter([
        _jsonResponse('{"status":"ok"}', 200),
        _jsonResponse('"2026-11-23T10:15:30.000Z"', 200),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;

      final result = await ProviderTester(_resolver(), dio: dio)
          .test(ProviderCatalog.recommendedFor(ServiceCategory.account));

      expect(result.ok, isTrue);
      expect(result.message, contains('API REST'));
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.first.uri.path, '/auth/v1/health');
      expect(adapter.requests.last.uri.path, '/rest/v1/rpc/server_time');
      expect(adapter.requests.every((request) => request.headers['apikey'] == 'sb_publishable_test'), isTrue);
      expect(adapter.requests.every((request) => request.headers['Authorization'] == null), isTrue);

      dio.close(force: true);
    });

    test('reports a missing Strasse migration instead of calling the project ready', () async {
      final adapter = _QueueAdapter([
        _jsonResponse('{"status":"ok"}', 200),
        _jsonResponse(
          '{"code":"PGRST202","message":"Could not find the function public.server_time"}',
          404,
        ),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;

      final result = await ProviderTester(_resolver(), dio: dio)
          .test(ProviderCatalog.recommendedFor(ServiceCategory.account));

      expect(result.ok, isFalse);
      expect(result.message, contains('schéma Strasse'));
      expect(result.message, contains('0001_strasse.sql'));

      dio.close(force: true);
    });

    test('identifies a rejected publishable key at the Auth endpoint', () async {
      final adapter = _QueueAdapter([
        _jsonResponse('{"message":"Invalid API key"}', 401),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;

      final result = await ProviderTester(_resolver(), dio: dio)
          .test(ProviderCatalog.recommendedFor(ServiceCategory.account));

      expect(result.ok, isFalse);
      expect(result.message, contains('clé publique'));
      expect(adapter.requests, hasLength(1));

      dio.close(force: true);
    });
  });
}
