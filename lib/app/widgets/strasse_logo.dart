import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Logo Strasse dessiné en vectoriel : carré arrondi, campagne verte à gauche, mer bleue à droite,
/// et un « S » gris en forme de route vue du dessus avec une ligne médiane pointillée.
class StrasseLogo extends StatelessWidget {
  const StrasseLogo({super.key, this.size = 96, this.dark = false});

  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Logo Strasse',
        image: true,
        child: SizedBox(width: size, height: size, child: CustomPaint(painter: _LogoPainter(dark))),
      );
}

/// Reprend exactement la géométrie de tool/generate_logo.py (même sinusoïde, mêmes largeurs, mêmes couleurs).
class _LogoPainter extends CustomPainter {
  _LogoPainter(this.dark);
  final bool dark;

  static const double _amp = 215, _exp = 0.82, _road = 150, _shoulder = 170, _over = 40;
  static const int _steps = 260;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 1024.0;
    canvas.save();
    canvas.scale(k);
    const w = 1024.0;
    final card = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, w, w), const Radius.circular(230));
    canvas.clipRRect(card);

    final green = dark ? const Color(0xFF4F8A45) : const Color(0xFF7DB251);
    final greenHi = dark ? const Color(0xFF6CA555) : const Color(0xFFA3CC62);
    final greenLo = dark ? const Color(0xFF3E7339) : const Color(0xFF5A9C48);
    final blue = dark ? const Color(0xFF2F6FA6) : const Color(0xFF4B98CC);
    final blueHi = dark ? const Color(0xFF6FA8D2) : const Color(0xFFA9D3EE);
    final shoulder = dark ? const Color(0xFF1B1F25) : const Color(0xFF4A4F57);
    final asphalt = dark ? const Color(0xFF7A828E) : const Color(0xFF707680);
    final marking = dark ? const Color(0xFFEEF1F4) : Colors.white;
    final edge = dark ? const Color(0xFFD5DAE0) : const Color(0xFFF4F6F8);
    final frame = dark ? const Color(0xFF1B2029) : Colors.white;

    Path line(double dx) {
      final path = Path();
      const y0 = -_over, y1 = w + _over;
      for (var i = 0; i <= _steps; i++) {
        final t = i / _steps;
        final y = y0 + (y1 - y0) * t;
        final s = math.sin(2 * math.pi * t);
        final x = 512.0 - _amp * (s < 0 ? -1 : 1) * math.pow(s.abs(), _exp) + dx;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    Path region(bool left) {
      final p = line(0);
      p.lineTo(left ? 0 : w, w + _over);
      p.lineTo(left ? 0 : w, -_over);
      p.close();
      return p;
    }

    Paint stroke(Color c, double width, {StrokeCap cap = StrokeCap.butt}) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = cap
      ..color = c;

    // Campagne.
    canvas.drawPath(region(true), Paint()..color = green);
    canvas.save();
    canvas.clipPath(region(true));
    canvas.drawPath(line(-215), stroke(greenHi, 64));
    canvas.drawPath(line(-345), stroke(greenLo, 64));
    canvas.drawPath(line(-475), stroke(greenHi, 64));
    canvas.restore();

    // Mer.
    canvas.drawPath(region(false), Paint()..color = blue);
    canvas.save();
    canvas.clipPath(region(false));
    for (final dx in const [215.0, 305.0, 395.0, 485.0]) {
      canvas.drawPath(line(dx), stroke(blueHi.withOpacity(0.65), 12, cap: StrokeCap.round));
    }
    canvas.restore();

    // Route.
    final road = line(0);
    canvas.drawPath(road, stroke(shoulder, _shoulder));
    canvas.drawPath(road, stroke(edge, _road + 14));
    canvas.drawPath(road, stroke(asphalt, _road - 12));
    final dash = stroke(marking, 9);
    for (final m in road.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, (d + 44).clamp(0.0, m.length)), dash);
        d += 80;
      }
    }

    // Cadre.
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(14, 14, w - 28, w - 28), const Radius.circular(216)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 28
        ..color = frame,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.dark != dark;
}
