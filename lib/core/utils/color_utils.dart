import 'dart:math' as math;
import 'package:flutter/material.dart';

double _channel(int v) {
  final c = v / 255.0;
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// Luminance relative WCAG.
double luminance(Color c) => 0.2126 * _channel(c.red) + 0.7152 * _channel(c.green) + 0.0722 * _channel(c.blue);

/// Rapport de contraste WCAG entre deux couleurs (de 1 à 21).
double contrastRatio(Color a, Color b) {
  final la = luminance(a), lb = luminance(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Éclaircit ou assombrit `c` jusqu'à atteindre `minRatio` de contraste avec `bg`.
/// Garantit que les éléments essentiels (itinéraire, texte) restent lisibles quel que soit le choix de l'utilisateur.
Color ensureContrast(Color c, Color bg, {double minRatio = 3.0}) {
  if (contrastRatio(c, bg) >= minRatio) return c;
  final bgLight = luminance(bg) > 0.4;
  final hsl = HSLColor.fromColor(c);
  var l = hsl.lightness;
  for (var i = 0; i < 40; i++) {
    l = bgLight ? l - 0.025 : l + 0.025;
    l = l.clamp(0.0, 1.0);
    final candidate = hsl.withLightness(l).toColor();
    if (contrastRatio(candidate, bg) >= minRatio) return candidate;
    if (l <= 0.0 || l >= 1.0) break;
  }
  return bgLight ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
}

/// « #rrggbb » (sans canal alpha) pour les styles MapLibre.
String hex(Color c) => '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Analyse « #rgb », « #rrggbb » ou « rrggbb ». Retourne null si invalide.
Color? parseHex(String input) {
  var s = input.trim().replaceFirst('#', '');
  if (s.length == 3) s = s.split('').map((ch) => '$ch$ch').join();
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}
