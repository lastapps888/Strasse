import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/geocoder_client.dart';
import 'package:strasse/domain/domain.dart';

enum AssistantAction { navigate, searchPlace, searchCategory, planTrip, unknown }

/// Intention comprise à partir d'une phrase : requêtes géographiques et paramètres d'itinéraire.
/// L'assistant ne produit jamais de lieu ni de donnée : il ne fait que préparer une recherche ou un calcul.
class AssistantIntent {
  const AssistantIntent({
    required this.action,
    required this.summary,
    this.query,
    this.category,
    this.mode,
    this.avoidTolls = false,
    this.avoidHighways = false,
    this.shortest = false,
    this.waypointQueries = const [],
    this.stopCount,
  });

  final AssistantAction action;

  /// Reformulation affichée à l'utilisateur avant exécution.
  final String summary;
  final String? query;
  final PlaceCategory? category;
  final TravelMode? mode;
  final bool avoidTolls;
  final bool avoidHighways;
  final bool shortest;
  final List<String> waypointQueries;
  final int? stopCount;

  RoutePrefs applyTo(RoutePrefs base) => base.copyWith(
        avoidTolls: avoidTolls ? true : null,
        avoidHighways: avoidHighways ? true : null,
        criterion: shortest ? RouteCriterion.shortest : null,
      );
}

/// Interface d'assistant : l'implémentation locale ci-dessous fonctionne sans réseau et sans rien transmettre.
/// Un assistant distant pourrait être branché ici, mais il ne doit jamais recevoir l'historique personnel automatiquement.
abstract class AssistantEngine {
  AssistantIntent interpret(String utterance);
}

/// Analyse par règles de phrases françaises courantes.
class LocalRuleAssistant implements AssistantEngine {
  const LocalRuleAssistant();

  static const _numberWords = {
    'un': 1, 'une': 1, 'deux': 2, 'trois': 3, 'quatre': 4, 'cinq': 5, 'six': 6, 'sept': 7, 'huit': 8, 'neuf': 9, 'dix': 10,
  };

  @override
  AssistantIntent interpret(String utterance) {
    final raw = utterance.trim();
    final t = foldText(raw);
    if (t.isEmpty) return const AssistantIntent(action: AssistantAction.unknown, summary: 'Dites-moi où vous souhaitez aller.');

    final avoidTolls = RegExp(r'sans peage|eviter les peages|pas de peage').hasMatch(t);
    final avoidHighways = RegExp(r'sans autoroute|eviter les autoroutes|pas d.autoroute').hasMatch(t);
    final shortest = RegExp(r'le plus court|plus court').hasMatch(t);
    TravelMode? mode;
    if (RegExp(r'a pied|en marchant|marche').hasMatch(t)) {
      mode = TravelMode.walk;
    } else if (RegExp(r'a velo|en velo|velo').hasMatch(t)) {
      mode = TravelMode.bike;
    } else if (RegExp(r'en voiture|en auto').hasMatch(t)) {
      mode = TravelMode.car;
    } else if (RegExp(r'transports? en commun|en bus|en metro|en train').hasMatch(t)) {
      mode = TravelMode.transit;
    }

    // Voyage à étapes.
    if (RegExp(r'voyage|etapes?').hasMatch(t) && RegExp(r'prepare|planifie|organise|cree|voyage').hasMatch(t)) {
      final count = _stopCount(t);
      final names = _waypointNames(raw);
      if (names.length >= 2) {
        return AssistantIntent(
          action: AssistantAction.planTrip,
          summary: 'Préparer un voyage : ${names.join(' → ')}.',
          waypointQueries: names,
          mode: mode,
          avoidTolls: avoidTolls,
          avoidHighways: avoidHighways,
          shortest: shortest,
        );
      }
      return AssistantIntent(
        action: AssistantAction.planTrip,
        summary: count == null ? 'Préparer un voyage : choisissez vos étapes.' : 'Préparer un voyage avec $count étapes : choisissez-les une à une.',
        stopCount: count,
        mode: mode,
      );
    }

    // Catégories de lieux (station-service, pause…).
    final cat = _category(t);
    if (cat != null && !RegExp(r'rejoindre|aller a|va a|vers').hasMatch(t)) {
      final onRoute = RegExp(r'sur mon trajet|sur ma route').hasMatch(t);
      return AssistantIntent(
        action: AssistantAction.searchCategory,
        summary: onRoute
            ? '${cat.label} : recherche autour de votre position (la recherche le long du trajet n\'est pas disponible).'
            : '${cat.label} : recherche autour de votre position.',
        category: cat,
      );
    }

    // Destination.
    final dest = _destination(raw);
    if (dest != null) {
      final parts = <String>[
        if (mode != null) mode.label.toLowerCase(),
        if (avoidTolls) 'sans péages',
        if (avoidHighways) 'sans autoroutes',
        if (shortest) 'le plus court',
      ];
      return AssistantIntent(
        action: AssistantAction.navigate,
        summary: 'Itinéraire vers $dest${parts.isEmpty ? '' : ' (${parts.join(', ')})'}.',
        query: dest,
        mode: mode,
        avoidTolls: avoidTolls,
        avoidHighways: avoidHighways,
        shortest: shortest,
      );
    }

    if (RegExp(r'cherche|trouve|ou est|ou se trouve').hasMatch(t)) {
      final q = raw.replaceFirst(RegExp(r'^(cherche|trouve(-moi)?|o[uù] (est|se trouve))\s+', caseSensitive: false), '').trim();
      if (q.isNotEmpty) {
        return AssistantIntent(action: AssistantAction.searchPlace, summary: 'Rechercher « $q ».', query: q);
      }
    }

    return const AssistantIntent(
      action: AssistantAction.unknown,
      summary: 'Je n\'ai pas compris. Essayez par exemple « Je veux rejoindre Lyon sans péages ».',
    );
  }

  PlaceCategory? _category(String t) {
    if (RegExp(r'station.?service|essence|carburant|faire le plein|diesel').hasMatch(t)) return PlaceCategory.fuel;
    if (RegExp(r'pause|me reposer|aire de repos|me reposer|dormir un peu').hasMatch(t)) return PlaceCategory.rest;
    if (RegExp(r'cafe|boire un cafe').hasMatch(t)) return PlaceCategory.cafe;
    if (RegExp(r'restaurant|manger|dejeuner|diner').hasMatch(t)) return PlaceCategory.restaurant;
    if (RegExp(r'parking|me garer|stationner').hasMatch(t)) return PlaceCategory.parking;
    if (RegExp(r'pharmacie').hasMatch(t)) return PlaceCategory.pharmacy;
    if (RegExp(r'hotel').hasMatch(t)) return PlaceCategory.hotel;
    if (RegExp(r'recharge|borne|electrique').hasMatch(t)) return PlaceCategory.charging;
    if (RegExp(r'distributeur|retirer de l.argent').hasMatch(t)) return PlaceCategory.atm;
    if (RegExp(r'toilettes|wc').hasMatch(t)) return PlaceCategory.toilets;
    if (RegExp(r'supermarche|courses').hasMatch(t)) return PlaceCategory.supermarket;
    return null;
  }

  int? _stopCount(String t) {
    final digits = RegExp(r'(\d+)\s*etapes?').firstMatch(t);
    if (digits != null) return int.tryParse(digits.group(1)!);
    final word = RegExp(r'(un|une|deux|trois|quatre|cinq|six|sept|huit|neuf|dix)\s+etapes?').firstMatch(t);
    return word == null ? null : _numberWords[word.group(1)!];
  }

  /// Extrait « Paris, Lyon puis Marseille » d'une phrase de voyage.
  List<String> _waypointNames(String raw) {
    final m = RegExp(r'(?:voyage|trajet|itin[ée]raire)\s+(?:de\s+|entre\s+)?(.+)$', caseSensitive: false).firstMatch(raw);
    if (m == null) return const [];
    var rest = m.group(1)!;
    rest = rest.replaceAll(RegExp(r'\b(sans p[ée]ages?|sans autoroutes?|le plus court|en voiture|[àa] v[ée]lo|[àa] pied)\b', caseSensitive: false), '');
    final parts = rest
        .split(RegExp(r'\s*(?:,|;|\bpuis\b|\bet\b|\bvia\b|\bensuite\b|→|->|\b[àa]\b)\s*', caseSensitive: false))
        .map((s) => s.replaceAll(RegExp(r'^(avec\s+\w+\s+[ée]tapes?\s*)', caseSensitive: false), '').trim())
        .where((s) => s.length >= 2 && !RegExp(r'^(\d+|un|une|deux|trois|quatre|cinq)\s+[ée]tapes?$', caseSensitive: false).hasMatch(s))
        .toList();
    return parts;
  }

  String? _destination(String raw) {
    final patterns = [
      RegExp(r'(?:je\s+(?:veux|voudrais|souhaite)\s+)?(?:rejoindre|aller\s+(?:[àa]|vers|jusqu.[àa])|va\s+[àa]|vais\s+[àa])\s+(.+)$', caseSensitive: false),
      RegExp(r'(?:navigue|emm[eè]ne-moi|guide-moi|conduis-moi|itin[ée]raire)\s+(?:vers|[àa]|pour)\s+(.+)$', caseSensitive: false),
      RegExp(r'(?:direction|vers)\s+(.+)$', caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(raw);
      if (m != null) {
        var d = m.group(1)!;
        d = d.replaceAll(RegExp(r'\b(sans p[ée]ages?|sans autoroutes?|[ée]viter les p[ée]ages?|[ée]viter les autoroutes?|le plus court|en voiture|[àa] v[ée]lo|en v[ée]lo|[àa] pied|en marchant)\b', caseSensitive: false), '');
        d = d.replaceAll(RegExp(r'[\s,.;]+$'), '').trim();
        if (d.length >= 2) return d;
      }
    }
    return null;
  }
}
