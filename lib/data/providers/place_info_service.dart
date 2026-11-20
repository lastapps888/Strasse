import 'package:dio/dio.dart';
import 'package:strasse/data/providers/geo_backend.dart';
import 'package:strasse/domain/domain.dart';

/// Photo et résumé d'un lieu, tirés de Wikipédia et de Wikimedia Commons (API publiques, sans clé, gratuites).
///
/// Le lieu est rattaché à un article uniquement si l'article est proche des coordonnées (≤ 250 m) ET si son titre
/// correspond au nom du lieu : on préfère ne rien afficher plutôt qu'une photo qui ne serait pas la sienne.
/// La licence et l'auteur de la photo sont lus sur Commons et affichés avec elle.
class PlaceInfo {
  const PlaceInfo({this.photoUrl, this.photoAuthor, this.photoLicense, this.photoPageUrl, this.summary, this.articleUrl, this.articleTitle});
  final String? photoUrl;
  final String? photoAuthor;
  final String? photoLicense;
  final String? photoPageUrl;
  final String? summary;
  final String? articleUrl;
  final String? articleTitle;

  bool get isEmpty => photoUrl == null && summary == null;
  static const none = PlaceInfo();
}

class PlaceInfoService {
  PlaceInfoService({Dio? dio, String language = 'fr', String userAgent = ''})
      : language = RegExp(r'^[a-z]{2,3}$').hasMatch(language) ? language : 'fr',
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'Accept': 'application/json', if (userAgent.isNotEmpty) 'User-Agent': userAgent},
            ));

  final Dio _dio;
  final String language;
  final TtlCache<PlaceInfo> _cache = TtlCache(ttl: const Duration(hours: 12), maxEntries: 200);

  static String _norm(String s) {
    const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
    final b = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      final ch = String.fromCharCode(r);
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Vrai si le titre de l'article et le nom du lieu désignent la même chose (l'un contient l'autre, mots entiers).
  static bool sameName(String place, String article) {
    final a = _norm(place), b = _norm(article);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final short = a.length <= b.length ? a : b;
    final long = a.length <= b.length ? b : a;
    if (short.length < 5) return false;
    return ' $long '.contains(' $short ');
  }

  Future<PlaceInfo> lookup(Place place, {CancelToken? cancel}) async {
    if (place.name.trim().length < 3) return PlaceInfo.none;
    final key = '${place.point.lat.toStringAsFixed(4)},${place.point.lon.toStringAsFixed(4)}|${place.name}';
    final hit = _cache.get(key);
    if (hit != null) return hit;
    PlaceInfo info = PlaceInfo.none;
    try {
      info = await _fetch(place, language, cancel) ?? (language == 'en' ? PlaceInfo.none : (await _fetch(place, 'en', cancel) ?? PlaceInfo.none));
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      return PlaceInfo.none; // réseau indisponible : pas mis en cache, on réessaiera
    }
    _cache.put(key, info);
    return info;
  }

  Future<PlaceInfo?> _fetch(Place place, String lang, CancelToken? cancel) async {
    final r = await _dio.get<Map<String, dynamic>>(
      'https://$lang.wikipedia.org/w/api.php',
      cancelToken: cancel,
      queryParameters: {
        'action': 'query',
        'format': 'json',
        'generator': 'geosearch',
        'ggscoord': '${place.point.lat}|${place.point.lon}',
        'ggsradius': 250,
        'ggslimit': 10,
        'prop': 'pageimages|extracts|info',
        'piprop': 'thumbnail|name',
        'pithumbsize': 640,
        'exintro': 1,
        'explaintext': 1,
        'exchars': 420,
        'exlimit': 'max',
        'inprop': 'url',
      },
    );
    final pages = (r.data?['query'] as Map?)?['pages'];
    if (pages is! Map) return null;
    for (final p in pages.values) {
      if (p is! Map) continue;
      final title = '${p['title'] ?? ''}';
      if (!sameName(place.name, title)) continue;
      final thumb = p['thumbnail'] is Map ? (p['thumbnail'] as Map)['source'] as String? : null;
      final file = p['pageimage'] as String?;
      String? author, license, filePage;
      if (file != null) {
        final meta = await _commonsMeta(file, cancel);
        author = meta.$1;
        license = meta.$2;
        filePage = 'https://commons.wikimedia.org/wiki/File:${Uri.encodeComponent(file)}';
      }
      final extract = '${p['extract'] ?? ''}'.trim();
      return PlaceInfo(
        photoUrl: thumb,
        photoAuthor: author,
        photoLicense: license,
        photoPageUrl: thumb == null ? null : filePage,
        summary: extract.isEmpty ? null : extract,
        articleUrl: p['fullurl'] as String?,
        articleTitle: title,
      );
    }
    return null;
  }

  Future<(String?, String?)> _commonsMeta(String file, CancelToken? cancel) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('https://commons.wikimedia.org/w/api.php', cancelToken: cancel, queryParameters: {
        'action': 'query',
        'format': 'json',
        'titles': 'File:$file',
        'prop': 'imageinfo',
        'iiprop': 'extmetadata',
      });
      final pages = (r.data?['query'] as Map?)?['pages'];
      if (pages is! Map || pages.isEmpty) return (null, null);
      final ii = ((pages.values.first as Map)['imageinfo'] as List?)?.first;
      final meta = ii is Map ? ii['extmetadata'] : null;
      if (meta is! Map) return (null, null);
      String? v(String k) {
        final x = meta[k];
        return x is Map && x['value'] != null ? '${x['value']}' : null;
      }
      String clean(String? s) => (s ?? '').replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&amp;', '&').trim();
      final a = clean(v('Artist'));
      final l = clean(v('LicenseShortName'));
      return (a.isEmpty ? null : a, l.isEmpty ? null : l);
    } on DioException {
      return (null, null);
    }
  }
}
