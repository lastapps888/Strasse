import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/features/services/provider_models.dart';
import 'package:strasse/features/services/provider_resolver.dart';

/// Vérifie qu'un fournisseur répond réellement avec le format attendu (et pas seulement que l'adresse répond).
class ProviderTester {
  ProviderTester(this.resolver, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
              validateStatus: (_) => true,
              headers: {'Accept': 'application/json, */*', 'User-Agent': resolver.config.userAgent},
            ));

  final ProviderResolver resolver;
  final Dio _dio;

  /// Vrai si un test réseau a un sens pour ce fournisseur.
  static bool canTest(ServiceProvider p) => p.kind != ProviderKind.link && p.adapter != 'google-places';

  Future<ProviderTestResult> test(ServiceProvider p) async {
    final sw = Stopwatch()..start();
    try {
      final (ok, msg) = await _run(p);
      return ProviderTestResult(ok: ok, message: msg, latency: sw.elapsed);
    } on DioException catch (e) {
      return ProviderTestResult(ok: false, message: Failure.fromDio(e).message, latency: sw.elapsed);
    } catch (e) {
      return ProviderTestResult(ok: false, message: 'Test impossible : ${e.runtimeType}', latency: sw.elapsed);
    }
  }

  Future<(bool, String)> _run(ServiceProvider p) async {
    final base = ProviderResolver.normalize(resolver.urlOf(p));
    switch (p.adapter) {
      case 'auto-geocoder':
        return _auto(p);
      case 'valhalla':
        if (base.isEmpty) return (false, 'Adresse non renseignée.');
        final r = await _dio.get<Object>('$base/status');
        final d = _json(r.data);
        if (_ok(r) && d is Map) {
          final v = d['version'];
          return (true, 'Valhalla opérationnel${v == null ? '' : ' (version $v)'}.');
        }
        return (false, 'Réponse inattendue (${r.statusCode}) : pas de /status Valhalla valide.');
      case 'nominatim':
        if (base.isEmpty) return (false, 'Adresse non renseignée.');
        final r = await _dio.get<Object>('$base/status', queryParameters: {'format': 'json'});
        final d = _json(r.data);
        if (_ok(r) && (d is Map ? (d['status'] == 0 || d['message'] == 'OK') : '${r.data}'.trim() == 'OK')) return (true, 'Nominatim opérationnel.');
        return (false, 'Réponse inattendue (${r.statusCode}) : pas de /status Nominatim valide.');
      case 'photon':
        if (base.isEmpty) return (false, 'Adresse non renseignée.');
        final r = await _dio.get<Object>('$base/api', queryParameters: {'q': 'Paris', 'limit': 1});
        final d = _json(r.data);
        if (_ok(r) && d is Map && d['features'] is List && (d['features'] as List).isNotEmpty) return (true, 'Photon opérationnel (recherche « Paris » valide).');
        return (false, 'Réponse inattendue (${r.statusCode}) : pas de résultat GeoJSON Photon.');
      case 'overpass':
        if (base.isEmpty) return (false, 'Adresse non renseignée.');
        final statusUrl = base.endsWith('/interpreter') ? '${base.substring(0, base.length - 'interpreter'.length)}status' : '$base/status';
        final r = await _dio.get<Object>(statusUrl, options: Options(responseType: ResponseType.plain));
        final text = '${r.data}';
        if (_ok(r) && (text.contains('slots') || text.contains('Connected as') || text.contains('Rate limit'))) return (true, 'Overpass opérationnel.');
        return (false, 'Réponse inattendue (${r.statusCode}) : pas de /status Overpass valide.');
      case 'overpass-poi':
        final roadData = resolver.selected(ServiceCategory.roadData);
        final overpassUrl = ProviderResolver.normalize(resolver.urlOf(roadData));
        if (overpassUrl.isEmpty) return (false, 'Aucun serveur Overpass configuré dans « Données routières ».');
        const query = '[out:json][timeout:12];nwr(around:100,48.8566,2.3522);out count;';
        final poiResponse = await _dio.post<Object>(
          overpassUrl,
          data: 'data=${Uri.encodeQueryComponent(query)}',
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
        final payload = _json(poiResponse.data);
        if (_ok(poiResponse) && payload is Map && payload['elements'] is List) {
          return (true, 'Overpass opérationnel : le service de lieux reçoit une réponse valide.');
        }
        return (false, 'Réponse Overpass invalide (${poiResponse.statusCode}).');
      case 'formsubmit':
        // Pas d'envoi de test (il enverrait un vrai message) : on vérifie seulement que le service répond.
        final r = await _dio.get<Object>(base);
        return _ok(r) ? (true, 'Service joignable. Aucun message de test n\'est envoyé ; l\'activation par le destinataire ne peut être vérifiée qu\'avec un vrai envoi.') : (false, 'Réponse ${r.statusCode}.');
      case 'mailto':
        return (true, 'Fonction native : dépend d\'une application e-mail installée.');
      case 'motis':
        if (base.isEmpty) return (false, 'Adresse non renseignée.');
        // Arrêts du centre de Strasbourg : réponse attendue = liste JSON d'arrêts avec stopId.
        final r = await _dio.get<Object>('$base/api/v1/map/stops', queryParameters: {'min': '48.580,7.745', 'max': '48.586,7.755'});
        if (!_ok(r)) return (false, 'Réponse ${r.statusCode} de /api/v1/map/stops.');
        final d = _json(r.data);
        if (d is List && d.isNotEmpty && d.first is Map && (d.first as Map).containsKey('stopId')) {
          return (true, '${d.length} arrêts reçus : le serveur répond au format MOTIS attendu.');
        }
        if (d is List) return (true, 'Réponse valide mais aucun arrêt dans la zone de test (couverture à vérifier).');
        return (false, 'Format inattendu : ce serveur ne ressemble pas à MOTIS 2.');
      case 'otp':
        if (base.isEmpty) return (false, 'Aucune instance OpenTripPlanner renseignée : ajoutez-en une avec « + ».');
        final r = await _dio.get<Object>(base);
        return _ok(r) ? (true, 'Serveur joignable. Les itinéraires ne sont validés qu\'au premier calcul (version non vérifiée).') : (false, 'Réponse ${r.statusCode}.');
      case 'tilejson':
        if (base.isEmpty) return (false, 'Adresse non renseignée.');
        if (base.contains('{z}')) {
          final u = base.replaceAll('{z}', '0').replaceAll('{x}', '0').replaceAll('{y}', '0');
          final r = await _dio.get<List<int>>(u, options: Options(responseType: ResponseType.bytes));
          return _ok(r) ? (true, 'Tuile 0/0/0 récupérée.') : (false, 'Réponse ${r.statusCode} pour la tuile 0/0/0.');
        }
        final r = await _dio.get<Object>(base);
        final d = _json(r.data);
        if (_ok(r) && d is Map && d['tiles'] is List && (d['tiles'] as List).isNotEmpty) return (true, 'TileJSON valide (${(d['tiles'] as List).length} modèle(s) de tuiles).');
        return (false, 'Réponse inattendue (${r.statusCode}) : ce n\'est pas un TileJSON.');
      case 'styleurl':
        if (base.isEmpty) return (false, 'Adresse non renseignée.');
        final r = await _dio.get<Object>(base);
        final d = _json(r.data);
        if (_ok(r) && d is Map && d['layers'] is List && d['sources'] is Map) return (true, 'Style MapLibre valide (${(d['layers'] as List).length} couches).');
        return (false, 'Réponse inattendue (${r.statusCode}) : ce n\'est pas un style MapLibre.');
      case 'glyphs':
        if (base.isEmpty) return (false, 'Adresse non renseignée.');
        final u = base.replaceAll('{fontstack}', Uri.encodeComponent(resolver.config.mapFont)).replaceAll('{range}', '0-255');
        final r = await _dio.get<List<int>>(u, options: Options(responseType: ResponseType.bytes));
        final n = r.data?.length ?? 0;
        return _ok(r) && n > 100 ? (true, 'Polices « ${resolver.config.mapFont} » disponibles.') : (false, 'Police « ${resolver.config.mapFont} » introuvable (${r.statusCode}).');
      case 'strasse-api':
        if (base.isEmpty) return (false, 'Adresse non renseignée.');
        final r = await _dio.get<Object>('$base/v1/health');
        final d = _json(r.data);
        return _ok(r) && d is Map && d['status'] == 'ok' ? (true, 'Serveur Strasse opérationnel (version ${d['version']}).') : (false, 'Réponse inattendue (${r.statusCode}).');
      case 'supabase':
        final url = ProviderResolver.normalize(resolver.credential(p, 'url'));
        final key = resolver.credential(p, 'anonKey');
        if (url.isEmpty || key.isEmpty) return (false, 'Adresse du projet et clé publique à renseigner (bouton « Identifiants »).');

        // L'endpoint Auth seul prouve uniquement que le projet répond. Il ne vérifie pas que
        // l'API REST et le schéma SQL nécessaires à la synchronisation Strasse sont déployés.
        final health = await _dio.get<Object>(
          '$url/auth/v1/health',
          options: Options(headers: {'apikey': key}),
        );
        if (!_ok(health)) {
          final status = health.statusCode ?? 0;
          if (status == 401 || status == 403) {
            return (false, 'Supabase répond, mais refuse la clé publique. Vérifiez la clé publishable du projet dans Réglages > Services.');
          }
          if (status == 404) {
            return (false, 'Endpoint Auth Supabase introuvable (404). Vérifiez l’URL du projet et l’activation de l’API Auth.');
          }
          return (false, 'L’endpoint Auth Supabase répond avec HTTP $status. Vérifiez l’état du projet dans Supabase.');
        }

        // server_time est une fonction de la migration Strasse, explicitement exécutable par anon
        // et authenticated. On vérifie donc réellement que PostgREST a chargé le schéma attendu.
        final schema = await _dio.post<Object>(
          '$url/rest/v1/rpc/server_time',
          data: const <String, dynamic>{},
          options: Options(
            headers: {
              'apikey': key,
              Headers.contentTypeHeader: Headers.jsonContentType,
            },
          ),
        );
        if (!_ok(schema)) {
          final status = schema.statusCode ?? 0;
          final body = _json(schema.data);
          final code = body is Map ? '${body['code'] ?? body['error_code'] ?? ''}' : '';
          final detail = body is Map ? '${body['message'] ?? body['msg'] ?? ''}' : '';
          if (status == 404 || code.startsWith('PGRST') || detail.toLowerCase().contains('server_time')) {
            return (
              false,
              'Le projet Supabase répond, mais le schéma Strasse n’est pas publié dans l’API REST. Exécutez supabase/migrations/0001_strasse.sql dans le SQL Editor, puis rechargez le schéma PostgREST.',
            );
          }
          if (status == 401 || status == 403) {
            return (false, 'L’API Auth répond, mais l’API REST refuse l’accès à server_time (HTTP $status). Vérifiez les droits SQL et les grants de la migration Strasse.');
          }
          return (false, 'L’API REST Supabase répond avec HTTP $status pendant le contrôle du schéma. ${detail.isEmpty ? 'Vérifiez la migration Strasse.' : detail}');
        }

        final rawTime = schema.data;
        final serverTime = rawTime is String
            ? (DateTime.tryParse(rawTime) != null ? rawTime : _json(rawTime))
            : _json(rawTime);
        if (serverTime is! String || DateTime.tryParse(serverTime) == null) {
          return (false, 'L’API REST répond, mais server_time ne renvoie pas un horodatage valide. Vérifiez la migration Strasse.');
        }
        return (true, 'Supabase opérationnel : Auth, clé publique, API REST et schéma Strasse vérifiés.');
      case 'opentripmap':
        final key = resolver.credential(p, 'apiKey');
        if (key.isEmpty) return (false, 'Clé API à renseigner (bouton « Identifiants »).');
        final r = await _dio.get<Object>('$base/places/geoname', queryParameters: {'name': 'Paris', 'apikey': key});
        final d = _json(r.data);
        return _ok(r) && d is Map && d['lat'] != null ? (true, 'OpenTripMap répond, clé valide.') : (false, 'Réponse ${r.statusCode} : clé refusée ou quota dépassé.');
      case 'deezer':
        final r = await _dio.get<Object>('$base/search', queryParameters: {'q': 'daft punk', 'limit': 1});
        final d = _json(r.data);
        return _ok(r) && d is Map && d['data'] is List ? (true, 'API Deezer joignable (extraits uniquement).') : (false, 'Réponse inattendue (${r.statusCode}).');
      case 'spotify':
        final id = resolver.credential(p, 'clientId');
        return id.isEmpty
            ? (false, 'Identifiant client à renseigner (bouton « Identifiants »).')
            : (true, 'Identifiant renseigné. La connexion se teste dans l\'onglet Musique.');
      default:
        return (true, 'Fonction native : aucune adresse à tester.');
    }
  }

  Future<(bool, String)> _auto(ServiceProvider p) async {
    final results = <String>[];
    var ok = true;
    for (final id in ['photon', 'nominatim']) {
      final b = _builtinGeocoder(id);
      final (o, m) = await _run(b);
      ok = ok && o;
      results.add('${b.name} : $m');
    }
    return (ok, results.join('\n'));
  }

  ServiceProvider _builtinGeocoder(String id) {
    final list = resolver.all(ServiceCategory.geocoding);
    return list.firstWhere((e) => e.id == id);
  }

  static bool _ok(Response<dynamic> r) => (r.statusCode ?? 0) >= 200 && (r.statusCode ?? 0) < 300;

  static Object? _json(Object? data) {
    if (data is Map || data is List) return data;
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
