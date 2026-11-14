import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';

/// Classement des résultats de recherche : d'abord la ressemblance avec la saisie (fautes tolérées),
/// ensuite la proximité de l'utilisateur.
class SearchRanking {
  SearchRanking._();

  /// Score de 0 à 1. La ressemblance pèse 80 %, la proximité 20 % (décroissance sur ~50 km).
  static double score(String query, Place p, {GeoPoint? near}) {
    final text = '${p.name} ${p.address ?? ''}';
    final nameSim = TextMatch.similarity(query, p.name);
    final fullSim = TextMatch.similarity(query, text);
    final sim = nameSim > fullSim ? nameSim : fullSim * 0.95;
    if (near == null) return sim;
    final km = distanceM(near, p.point) / 1000;
    final closeness = 1 / (1 + km / 50);
    return sim * 0.8 + closeness * 0.2;
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
