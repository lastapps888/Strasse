import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/geo_backend.dart';
import 'package:strasse/data/providers/geocoder_client.dart';
import 'package:strasse/data/providers/photon_client.dart';
import 'package:strasse/data/providers/search_ranking.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/services/provider_catalog.dart';
import 'package:strasse/features/services/provider_models.dart';
import 'package:strasse/features/services/provider_resolver.dart';

/// Recherche d'adresses : choisit le fournisseur adapté à chaque type de requête et bascule en cas de panne.
///
/// - Suggestions pendant la saisie : Photon (ou toute instance autorisant l'autocomplétion). Jamais le Nominatim public.
/// - Recherche validée et recherche par catégorie : Nominatim, Photon en secours.
/// - Géocodage inverse : Nominatim (1 requête/s, mis en cache), Photon en secours.
class GeocodingService {
  GeocodingService._(this._suggest, this._search, this._reverse);

  /// Résultats en dessous de ce score de ressemblance déclenchent les recherches de secours (fautes de frappe).
  static const double _goodEnough = 0.82;

  static final RateGate _publicNominatimGate = RateGate(const Duration(milliseconds: 1100));
  final TtlCache<Place?> _reverseCache = TtlCache(ttl: const Duration(minutes: 30), maxEntries: 200);

  final List<(String, GeoBackend)> _suggest;
  final List<(String, GeoBackend)> _search;
  final List<(String, GeoBackend)> _reverse;

  /// Vrai si au moins un fournisseur permet l'autocomplétion.
  bool get supportsSuggestions => _suggest.isNotEmpty;
  bool get configured => _search.isNotEmpty || _suggest.isNotEmpty;

  factory GeocodingService.fromResolver(ProviderResolver r, {Dio? dio, String language = 'fr'}) {
    final ua = r.config.userAgent;

    GeoBackend? make(ServiceProvider p) {
      final url = ProviderResolver.normalize(r.urlOf(p));
      if (url.isEmpty) return null;
      final isPublicNominatim = Uri.tryParse(url)?.host.endsWith('nominatim.openstreetmap.org') ?? false;
      switch (p.adapter) {
        case 'photon':
          return PhotonClient(url, dio: dio, userAgent: ua, language: language);
        case 'nominatim':
          return GeocoderClient(url, dio: dio, userAgent: ua, gate: isPublicNominatim ? _publicNominatimGate : null);
        default:
          return null;
      }
    }

    ServiceProvider builtin(String id) => ProviderCatalog.byId(id)!;

    List<(String, GeoBackend)> chain(ServiceCategory cat, {required bool preferPhoton}) {
      final sel = r.selected(cat);
      final out = <(String, GeoBackend)>[];
      void add(ServiceProvider p) {
        final b = make(p);
        if (b != null && !out.any((e) => e.$1 == '${p.adapter}|${r.urlOf(p)}')) out.add(('${p.adapter}|${r.urlOf(p)}', b));
      }

      if (sel.adapter == 'auto-geocoder') {
        final photon = builtin('photon'), nominatim = builtin('nominatim');
        if (preferPhoton) {
          add(photon);
          add(nominatim);
        } else {
          add(nominatim);
          add(photon);
        }
      } else {
        add(sel);
        if (r.settings.autoFallback) {
          // Secours : l'autre fournisseur intégré.
          add(sel.adapter == 'photon' ? builtin('nominatim') : builtin('photon'));
        }
      }
      return out;
    }

    final suggest = [for (final e in chain(ServiceCategory.geocoding, preferPhoton: true)) if (e.$2.allowsAutocomplete) e];
    final search = chain(ServiceCategory.geocoding, preferPhoton: false);
    final reverse = chain(ServiceCategory.reverse, preferPhoton: false);
    return GeocodingService._(suggest, search, reverse);
  }

  /// Suggestions pendant la saisie (à appeler avec un délai de frappe, voir [SuggestDebouncer]).
  Future<List<Place>> suggest(String query, {GeoPoint? near, int limit = 6, CancelToken? cancel}) {
    if (_suggest.isEmpty) return Future.value(const []);
    return _tolerant(query, near, limit, _suggest, (b, q) => b.search(q, near: near, limit: limit, cancel: cancel));
  }

  /// Recherche validée (touche Entrée) ou par catégorie dans une zone.
  Future<List<Place>> search(
    String query, {
    GeoPoint? near,
    GeoBounds? bounds,
    bool bounded = false,
    int limit = 8,
    CancelToken? cancel,
  }) {
    if (_search.isEmpty) throw Failure.notConfigured('La recherche d\'adresses');
    return _tolerant(
      query,
      near ?? bounds?.center,
      limit,
      _search,
      (b, q) => b.search(q, near: near, bounds: bounds, bounded: bounded, limit: limit, cancel: cancel),
      // Nominatim ne corrige pas les fautes : Photon sert de filet, sans restriction de zone.
      rescue: bounded ? null : _suggest,
    );
  }

  /// Interroge le fournisseur principal ; si rien de convaincant n'en sort (aucun résultat, ou noms trop
  /// éloignés de la saisie), réessaie avec des variantes de la requête puis avec le fournisseur tolérant aux fautes.
  /// Les résultats sont fusionnés, dédoublonnés et classés par ressemblance puis par proximité.
  Future<List<Place>> _tolerant(
    String query,
    GeoPoint? near,
    int limit,
    List<(String, GeoBackend)> chain,
    Future<List<Place>> Function(GeoBackend, String) call, {
    List<(String, GeoBackend)>? rescue,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    var merged = <Place>[];
    Object? firstError;
    try {
      merged = await FailoverRunner.run([for (final e in chain) e.$1], (i) => call(chain[i].$2, q), retryClientErrors: true);
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) rethrow;
      if (e is Failure && e.code == 'cancelled') rethrow;
      firstError = e;
    }
    var ranked = SearchRanking.rank(q, merged, near: near);
    if (ranked.isNotEmpty && SearchRanking.score(q, ranked.first, near: null) >= _goodEnough) {
      return ranked.take(limit).toList();
    }
    final extra = <Place>[];
    final tolerant = rescue ?? chain;
    for (final v in TextMatch.variants(q)) {
      try {
        extra.addAll(await FailoverRunner.run([for (final e in tolerant) e.$1], (i) => call(tolerant[i].$2, v), retryClientErrors: true));
      } catch (e) {
        if (e is DioException && CancelToken.isCancel(e)) rethrow;
        if (e is Failure && e.code == 'cancelled') rethrow;
        firstError ??= e;
      }
      if (extra.length >= limit) break;
    }
    if (rescue != null && rescue.isNotEmpty && ranked.length < 3) {
      try {
        extra.addAll(await FailoverRunner.run([for (final e in rescue) e.$1], (i) => call(rescue[i].$2, q), retryClientErrors: true));
      } catch (e) {
        firstError ??= e;
      }
    }
    ranked = SearchRanking.rank(q, [...merged, ...extra], near: near);
    if (ranked.isEmpty && firstError != null && merged.isEmpty) throw firstError;
    return ranked.take(limit).toList();
  }

  Future<Place?> reverse(GeoPoint p, {CancelToken? cancel}) async {
    if (_reverse.isEmpty) return null;
    final key = '${p.lat.toStringAsFixed(5)},${p.lon.toStringAsFixed(5)}';
    final cached = _reverseCache.get(key);
    if (cached != null) return cached;
    try {
      final place = await _run(_reverse, (b) => b.reverse(p, cancel: cancel));
      if (place != null) _reverseCache.put(key, place);
      return place;
    } on Failure {
      return null;
    }
  }

  Future<T> _run<T>(List<(String, GeoBackend)> chain, Future<T> Function(GeoBackend) call) =>
      FailoverRunner.run([for (final e in chain) e.$1], (i) => call(chain[i].$2), retryClientErrors: true);
}

/// Retarde les requêtes de suggestion jusqu'à une courte pause de frappe, et annule la précédente.
class SuggestDebouncer {
  SuggestDebouncer({this.delay = const Duration(milliseconds: 320)});

  final Duration delay;
  int _gen = 0;

  /// Retourne null si une saisie plus récente a pris le relais.
  Future<T?> run<T>(Future<T> Function() job) async {
    final mine = ++_gen;
    await Future<void>.delayed(delay);
    if (mine != _gen) return null;
    final r = await job();
    return mine == _gen ? r : null;
  }

  void cancel() => _gen++;
}
