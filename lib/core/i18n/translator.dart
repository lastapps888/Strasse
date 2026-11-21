import 'dart:collection';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:strasse/core/i18n/app_language.dart';

/// Traduit les textes de l'interface. Le code source écrit tout en français ; ce traducteur retrouve la phrase
/// dans le dictionnaire de la langue choisie (`assets/i18n/<code>.json`) au moment de l'affichage.
///
/// - Phrase exacte : recherche directe.
/// - Phrase avec valeurs insérées (« Marche 5 min jusqu'à Gare ») : reconnue par son modèle (« Marche {0} jusqu'à {1} »),
///   traduite, puis les valeurs sont remises en place.
/// - Texte composé de morceaux séparés par « · » ou « , » : chaque morceau est traduit séparément.
/// - Texte inconnu (nom de lieu, adresse, saisie de l'utilisateur) : affiché tel quel.
class Translator {
  Translator._();

  static AppLanguage language = AppLanguage.fr;
  static Map<String, String> _exact = const {};
  static List<_Template> _templates = const [];
  static final LinkedHashMap<String, String> _cache = LinkedHashMap();

  static bool get isFrench => language == AppLanguage.fr;

  /// Charge le dictionnaire d'une langue depuis les ressources de l'application. Le français n'en a pas besoin.
  static Future<void> load(AppLanguage lang, {Future<String> Function(String path)? loader}) async {
    if (lang == AppLanguage.fr) {
      use(lang, const {});
      return;
    }
    try {
      final raw = await (loader ?? rootBundle.loadString)('assets/i18n/${lang.code}.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      use(lang, {for (final e in json.entries) if (e.value is String && (e.value as String).isNotEmpty) e.key: e.value as String});
    } catch (_) {
      // Dictionnaire absent ou illisible : l'interface reste en français plutôt que de planter.
      use(AppLanguage.fr, const {});
    }
  }

  /// Installe un dictionnaire (utilisé aussi par les tests).
  static void use(AppLanguage lang, Map<String, String> dictionary) {
    language = lang;
    _exact = dictionary;
    _cache.clear();
    final t = <_Template>[];
    for (final e in dictionary.entries) {
      if (e.key.contains('{0}')) {
        final tpl = _Template.parse(e.key, e.value);
        if (tpl != null) t.add(tpl);
      }
    }
    // Les modèles les plus précis (le plus de texte fixe) passent en premier.
    t.sort((a, b) => b.fixedLength.compareTo(a.fixedLength));
    _templates = t;
  }

  static String translate(String s) {
    if (isFrench || s.isEmpty) return s;
    final hit = _cache.remove(s);
    if (hit != null) {
      _cache[s] = hit;
      return hit;
    }
    final out = _translate(s);
    _cache[s] = out;
    if (_cache.length > 3000) _cache.remove(_cache.keys.first);
    return out;
  }

  static String _translate(String s) {
    final exact = _exact[s];
    if (exact != null) return exact;
    for (final t in _templates) {
      final r = t.apply(s, _exact);
      if (r != null) return r;
    }
    for (final sep in const [' · ', ' — ', '\n']) {
      if (s.contains(sep)) {
        final parts = s.split(sep);
        var any = false;
        final out = [
          for (final p in parts)
            () {
              final t = _translate(p);
              if (t != p) any = true;
              return t;
            }(),
        ];
        if (any) return out.join(sep);
      }
    }
    // Phrases terminées par une ponctuation : « Réessayer. » → « Réessayer »
    final m = RegExp(r'^(.*?)([\s.!?…:]+)$', dotAll: true).firstMatch(s);
    if (m != null && m.group(1)!.isNotEmpty) {
      final core = _exact[m.group(1)!];
      if (core != null) return '$core${m.group(2)}';
    }
    return s;
  }
}

class _Template {
  _Template(this.pattern, this.translation, this.fixedLength);

  final RegExp pattern;
  final String translation;
  final int fixedLength;

  static final _placeholder = RegExp(r'\{(\d+)\}');

  static _Template? parse(String key, String translation) {
    final buf = StringBuffer('^');
    var fixed = 0;
    var last = 0;
    var count = 0;
    for (final m in _placeholder.allMatches(key)) {
      final lit = key.substring(last, m.start);
      buf.write(RegExp.escape(lit));
      fixed += lit.length;
      buf.write('(.+?)');
      last = m.end;
      count++;
    }
    final tail = key.substring(last);
    buf.write(RegExp.escape(tail));
    buf.write(r'$');
    fixed += tail.length;
    if (count == 0 || fixed < 3) return null; // « {0} » seul ou presque : trop ambigu
    return _Template(RegExp(buf.toString(), dotAll: true), translation, fixed);
  }

  String? apply(String s, Map<String, String> dict) {
    final m = pattern.firstMatch(s);
    if (m == null) return null;
    var out = translation;
    for (var i = 1; i <= m.groupCount; i++) {
      final value = m.group(i)!;
      out = out.replaceAll('{${i - 1}}', dict[value] ?? value);
    }
    return out;
  }
}

/// Traduit un texte écrit en français dans la langue choisie.
String tr(String french) => Translator.translate(french);

/// Traduit une chaîne facultative sans transformer null en chaîne vide.
String? trn(String? french) => french == null ? null : tr(french);
