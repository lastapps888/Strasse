import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';

/// Portion de l'itinéraire où une limite de vitesse est connue (indices de points de la polyligne).
class SpeedLimitSpan {
  const SpeedLimitSpan(this.begin, this.end, this.kmh);
  final int begin;
  final int end;
  final int kmh;
}

/// Limites de vitesse le long d'un itinéraire. Les données viennent d'OpenStreetMap (balise maxspeed) via Valhalla :
/// elles sont incomplètes et parfois fausses ; l'absence de limite ne signifie pas « pas de limite ».
class SpeedLimitMap {
  const SpeedLimitMap(this.spans);
  static const empty = SpeedLimitMap([]);

  final List<SpeedLimitSpan> spans;
  bool get isEmpty => spans.isEmpty;

  /// Limite au segment [segment] de la polyligne (entre les points `segment` et `segment + 1`), ou null si inconnue.
  int? at(int segment) {
    if (spans.isEmpty) return null;
    // Recherche dichotomique : les tronçons sont triés et ne se chevauchent pas.
    var lo = 0, hi = spans.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final s = spans[mid];
      if (segment < s.begin) {
        hi = mid - 1;
      } else if (segment >= s.end) {
        lo = mid + 1;
      } else {
        return s.kmh;
      }
    }
    return null;
  }

  /// Interprète la réponse `trace_attributes` de Valhalla (arêtes avec `speed_limit` et indices de forme).
  static SpeedLimitMap fromTraceAttributes(Map<String, dynamic> json) {
    final out = <SpeedLimitSpan>[];
    for (final e in (json['edges'] as List?) ?? const []) {
      if (e is! Map) continue;
      final limit = e['speed_limit'];
      final b = e['begin_shape_index'];
      final en = e['end_shape_index'];
      if (limit is! num || b is! num || en is! num) continue;
      final kmh = limit.round();
      // 0 ou valeurs aberrantes : limite inconnue.
      if (kmh < 5 || kmh > 200) continue;
      out.add(SpeedLimitSpan(b.toInt(), en.toInt(), kmh));
    }
    out.sort((a, b) => a.begin.compareTo(b.begin));
    return SpeedLimitMap(out);
  }
}

enum SpeedLevel { unknown, ok, over }

/// Compare la vitesse mesurée à la limite connue. L'alerte ne se déclenche qu'au-delà de limite + [marginKmh] et
/// seulement si la vitesse GPS est fiable (au moins 8 km/h), pour ne pas réagir au bruit du GPS à l'arrêt.
SpeedLevel evaluateSpeed({required double speedKmh, required int? limitKmh, required int marginKmh}) {
  if (limitKmh == null) return SpeedLevel.unknown;
  if (speedKmh < 8) return SpeedLevel.ok;
  return speedKmh >= limitKmh + marginKmh ? SpeedLevel.over : SpeedLevel.ok;
}

/// Lissage de la vitesse affichée : moyenne exponentielle, pour éviter les sauts d'une position GPS à l'autre.
class SpeedSmoother {
  SpeedSmoother({this.alpha = 0.4});
  final double alpha;
  double? _v;

  double add(double speedMps) {
    final kmh = speedMps.isNaN || speedMps < 0 ? 0.0 : speedMps * 3.6;
    final prev = _v;
    _v = prev == null ? kmh : prev + alpha * (kmh - prev);
    if (_v! < 1) _v = 0;
    return _v!;
  }

  void reset() => _v = null;
}

/// Limite de vitesse affichée avec une unité : miles par heure si l'utilisateur a choisi les unités impériales.
int displaySpeed(double kmh, Units units) => units == Units.metric ? kmh.round() : (kmh * 0.621371).round();
