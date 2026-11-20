import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';

/// Classement des résultats de recherche : d'abord la ressemblance avec la saisie (fautes tolérées),
/// ensuite la proximité de l'utilisateur.
class SearchRanking {
  SearchRanking._();

  /// Lieux que l'utilisateur a lui-même ouverts récemment (historique local, jamais envoyé nulle part) : ils remontent
  /// légèrement dans les résultats. Renseigné depuis `recentPlacesProvider`.
  static List<Place> personalPlaces = const [];

  /// Importance a priori d'un type de lieu (0–1) : une ville ou une gare avant une rue homonyme.
  static double categoryPrior(String? category) {
    final c = (category ?? '').toLowerCase();
    if (c.isEmpty) return 0.35;
    bool has(List<String> k) => k.any(c.contains);
    if (has(['capital', 'city', 'ville', 'municipality'])) return 1.0;
    if (has(['airport', 'aerodrome', 'station', 'railway', 'town'])) return 0.8;
    if (has(['museum', 'attraction', 'monument', 'castle', 'stadium', 'university', 'hospital', 'cathedral', 'tourism'])) return 0.65;
    if (has(['village', 'suburb', 'island', 'peak', 'lake'])) return 0.55;
    if (has(['neighbourhood', 'quarter', 'hamlet'])) return 0.45;
    if (has(['house', 'residential', 'street', 'road', 'footway', 'service'])) return 0.25;
    return 0.4;
  }

  static double _personal(Place p) {
    for (final r in personalPlaces) {
      if (distanceM(r.point, p.point) < 150 && TextMatch.fold(r.name) == TextMatch.fold(p.name)) return 1.0;
    }
    return 0.0;
  }

  /// Score de 0 à 1 : ressemblance 62 %, proximité 18 %, importance du type de lieu 12 %, historique local 8 %.
  /// Sans position, la proximité est ignorée et son poids revient à la ressemblance.
  static double score(String query, Place p, {GeoPoint? near}) {
    final text = '${p.name} ${p.address ?? ''}';
    final nameSim = TextMatch.similarity(query, p.name);
    final fullSim = TextMatch.similarity(query, text);
    final sim = nameSim > fullSim ? nameSim : fullSim * 0.95;
    final prior = categoryPrior(p.category);
    final personal = _personal(p);
    if (near == null) return sim * 0.80 + prior * 0.12 + personal * 0.08;
    final km = distanceM(near, p.point) / 1000;
    final closeness = 1 / (1 + km / 25);
    return sim * 0.62 + closeness * 0.18 + prior * 0.12 + personal * 0.08;
  }

  /// Trie par score décroissant et retire les doublons (même nom normalisé à moins de ~100 m, ou même identifiant).
  static List<Place> rank(String query, List<Place> places, {GeoPoint? near}) {
    final scored = [for (final p in places) (p, score(query, p, near: near))]..sort((a, b) => b.$2.compareTo(a.$2));
    final seen = <String>{};
    final out = <Place>[];
    for (final e in scored) {
      final p = e.$1;
      final key = '${TextMatch.fold(p.name)}|${p.point.lat.toStringAsFixed(3)}|${p.point.lon.toStringAsFixed(3)}';
      if (!seen.add(key) || !seen.add('id:${p.id}')) continue;
      out.add(p);
    }
    return out;
  }
}
