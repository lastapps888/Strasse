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
  static bool canTest(ServiceProvider p) => p.kind != ProviderKind.link;

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
        final r = await _dio.get<Object>('$url/auth/v1/health', options: Options(headers: {'apikey': key}));
        return _ok(r) ? (true, 'Projet Supabase joignable.') : (false, 'Réponse ${r.statusCode} : projet en pause, adresse ou clé incorrecte.');
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
