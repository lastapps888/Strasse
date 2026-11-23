import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:strasse/features/services/provider_models.dart';
import 'package:strasse/features/services/provider_resolver.dart';

/// Vérifie le format du document renvoyé avant qu'un fournisseur cartographique soit choisi.
class MapProviderHealthCheck {
  MapProviderHealthCheck({required String userAgent, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 5),
              sendTimeout: const Duration(seconds: 3),
              validateStatus: (_) => true,
              headers: {'Accept': 'application/json', 'User-Agent': userAgent},
            ));

  final Dio _dio;

  Future<bool> isHealthy(ServiceProvider provider, ProviderResolver resolver) async {
    final url = ProviderResolver.normalize(resolver.urlOf(provider));
    if (url.isEmpty) return false;
    try {
      final response = await _dio.get<Object>(url);
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) return false;
      final document = _decode(response.data);
      if (document is! Map) return false;
      switch (provider.adapter) {
        case 'styleurl':
          final version = document['version'];
          final sources = document['sources'];
          final layers = document['layers'];
          return (version == 8 || version == '8') &&
              sources is Map && sources.isNotEmpty &&
              layers is List && layers.isNotEmpty;
        case 'tilejson':
          final tiles = document['tiles'];
          return tiles is List &&
              tiles.any((tile) => tile is String && tile.trim().isNotEmpty);
        default:
          return false;
      }
    } on DioException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Object? _decode(Object? value) {
    if (value is Map || value is List) return value;
    if (value is String) {
      try {
        return jsonDecode(value);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  void close() => _dio.close(force: true);
}
