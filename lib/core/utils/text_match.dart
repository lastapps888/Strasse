import 'dart:math' as math;

/// Outils de comparaison de textes pour la recherche de lieux : insensible à la casse, aux accents
/// et aux abréviations courantes, tolérant aux fautes de frappe.
class TextMatch {
  TextMatch._();

  static const _accents = {
    'àáâãäåā': 'a', 'çćč': 'c', 'èéêëēė': 'e', 'ìíîïī': 'i', 'ñń': 'n', 'òóôõöøō': 'o',
    'ùúûüū': 'u', 'ýÿ': 'y', 'œ': 'oe', 'æ': 'ae', 'ß': 'ss', 'šś': 's', 'žźż': 'z', 'łľ': 'l',
  };

  static const _abbr = {
    'av': 'avenue', 'ave': 'avenue', 'bd': 'boulevard', 'bld': 'boulevard', 'blvd': 'boulevard',
    'r': 'rue', 'pl': 'place', 'imp': 'impasse', 'all': 'allee', 'chem': 'chemin', 'rte': 'route',
    'fg': 'faubourg', 'fbg': 'faubourg', 'qu': 'quai', 'sq': 'square', 'cr': 'cours', 'crs': 'cours',
    'st': 'saint', 'ste': 'sainte', 'sts': 'saints', 'stes': 'saintes', 'gal': 'general', 'mal': 'marechal',
    'pt': 'pont', 'ch': 'chateau', 'cc': 'centre commercial', 'gare sncf': 'gare',
  };

  /// Minuscules, sans accents ni ponctuation, espaces simples.
  static String fold(String s) {
    final b = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      final c = String.fromCharCode(r);
      var out = c;
      for (final e in _accents.entries) {
        if (e.key.contains(c)) {
          out = e.value;
          break;
        }
      }
      b.write(out);
    }
    return b.toString().replaceAll(RegExp(r"[^a-z0-9Ѐ-ӿ؀-ۿ぀-ヿ一-鿿 ]+"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Comme [fold], avec les abréviations développées (« bd st michel » → « boulevard saint michel »).
  static String normalize(String s) {
    final words = fold(s).split(' ').where((w) => w.isNotEmpty);
    return words.map((w) => _abbr[w] ?? w).join(' ');
  }

  /// Distance de Damerau-Levenshtein (substitution, insertion, suppression, transposition).
  static int distance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final d = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0));
    for (var i = 0; i <= a.length; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var v = math.min(math.min(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + cost);
        if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) v = math.min(v, d[i - 2][j - 2] + 1);
        d[i][j] = v;
      }
    }
    return d[a.length][b.length];
  }

  /// Ressemblance entre 0 et 1 de deux mots.
  static double wordSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final m = math.max(a.length, b.length);
    return 1 - distance(a, b) / m;
  }

  /// Ressemblance entre une requête et un texte candidat (0 à 1).
  /// Chaque mot de la requête est comparé au meilleur mot du candidat ; un préfixe compte comme une correspondance
  /// (la saisie est souvent incomplète).
  static double similarity(String query, String candidate) {
    final q = normalize(query).split(' ').where((w) => w.isNotEmpty).toList();
    final c = normalize(candidate).split(' ').where((w) => w.isNotEmpty).toList();
    if (q.isEmpty || c.isEmpty) return 0;
    var total = 0.0;
    for (final w in q) {
      var best = 0.0;
      for (final x in c) {
        var s = wordSimilarity(w, x);
        if (w.length >= 2 && x.startsWith(w)) s = math.max(s, 0.92);
        if (s > best) best = s;
        if (best == 1) break;
      }
      total += best;
    }
    return total / q.length;
  }

  /// Variantes d'une requête à essayer quand la première ne donne rien de convaincant :
  /// lettres doublées réduites, mots d'articles retirés, dernier mot tronqué, numéro retiré.
  static List<String> variants(String query) {
    final base = normalize(query);
    final out = <String>{};
    void add(String v) {
      final t = v.trim();
      if (t.length >= 2 && t != base) out.add(t);
    }

    add(base.replaceAllMapped(RegExp(r'([a-z])\1+'), (m) => m[1]!));
    final words = base.split(' ');
    add(words.where((w) => !const {'de', 'du', 'des', 'la', 'le', 'les', 'l', 'd', 'et', 'en', 'sur', 'sous', 'aux', 'au'}.contains(w)).join(' '));
    if (words.length > 1) add(words.sublist(0, words.length - 1).join(' '));
    final last = words.last;
    if (last.length > 5) {
      add([...words.sublist(0, words.length - 1), last.substring(0, last.length - 2)].join(' '));
    }
    final noNumber = words.where((w) => !RegExp(r'^\d+[a-z]?$').hasMatch(w)).join(' ');
    add(noNumber);
    return out.take(3).toList();
  }
}
