import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/settings/settings_model.dart';

/// Pictogrammes de véhicules vus de dessus, dessinés par le code (aucun fichier image) et orientés vers le haut.
/// Le même dessin sert dans les réglages et, converti en image, comme repère de position sur la carte.
class VehicleGlyphPainter extends CustomPainter {
  const VehicleGlyphPainter(this.icon, this.color, {this.outline = Colors.white});

  final VehicleIcon icon;
  final Color color;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s / 100);
    final fill = Paint()..color = color;
    final edge = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeJoin = StrokeJoin.round;
    final glass = Paint()..color = Colors.black.withOpacity(0.45);
    final light = Paint()..color = Colors.white.withOpacity(0.9);

    void body(Rect r, double radius) {
      final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
      canvas.drawRRect(rr, edge);
      canvas.drawRRect(rr, fill);
    }

    void windows(double top, double bottom, double w) {
      final r = RRect.fromRectAndRadius(Rect.fromLTRB(50 - w / 2, top, 50 + w / 2, bottom), const Radius.circular(5));
      canvas.drawRRect(r, glass);
    }

    void headlights(double y, double spread) {
      canvas.drawCircle(Offset(50 - spread, y), 3, light);
      canvas.drawCircle(Offset(50 + spread, y), 3, light);
    }

    switch (icon) {
      case VehicleIcon.car:
        body(const Rect.fromLTRB(30, 8, 70, 92), 15);
        windows(30, 66, 30);
        headlights(14, 14);
      case VehicleIcon.compact:
        body(const Rect.fromLTRB(32, 18, 68, 84), 15);
        windows(34, 62, 26);
        headlights(23, 12);
      case VehicleIcon.electric:
        body(const Rect.fromLTRB(30, 8, 70, 92), 15);
        windows(30, 66, 30);
        final bolt = Path()
          ..moveTo(54, 36)
          ..lineTo(43, 52)
          ..lineTo(50, 52)
          ..lineTo(46, 66)
          ..lineTo(58, 48)
          ..lineTo(51, 48)
          ..close();
        canvas.drawPath(bolt, Paint()..color = const Color(0xFFFFD54F));
        headlights(14, 14);
      case VehicleIcon.sport:
        body(const Rect.fromLTRB(28, 6, 72, 94), 20);
        windows(38, 62, 28);
        headlights(13, 15);
      case VehicleIcon.suv:
        body(const Rect.fromLTRB(26, 8, 74, 92), 12);
        windows(28, 70, 34);
        headlights(14, 17);
      case VehicleIcon.motorcycle:
        final wheel = Paint()..color = Colors.black.withOpacity(0.7);
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(46, 8, 54, 36), const Radius.circular(4)), edge);
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(46, 64, 54, 94), const Radius.circular(4)), edge);
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(46, 8, 54, 36), const Radius.circular(4)), wheel);
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(46, 64, 54, 94), const Radius.circular(4)), wheel);
        body(const Rect.fromLTRB(40, 30, 60, 72), 10);
        canvas.drawLine(const Offset(30, 34), const Offset(70, 34), Paint()..color = Colors.black.withOpacity(0.7)..strokeWidth = 5..strokeCap = StrokeCap.round);
        canvas.drawCircle(const Offset(50, 54), 5, light);
      case VehicleIcon.bicycle:
        final wheel = Paint()..color = Colors.black.withOpacity(0.7);
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(47, 6, 53, 34), const Radius.circular(3)), wheel);
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(47, 66, 53, 94), const Radius.circular(3)), wheel);
        canvas.drawLine(const Offset(50, 20), const Offset(50, 80), edge..strokeWidth = 9);
        canvas.drawLine(const Offset(50, 20), const Offset(50, 80), Paint()..color = color..strokeWidth = 5..strokeCap = StrokeCap.round);
        canvas.drawLine(const Offset(36, 30), const Offset(64, 30), Paint()..color = color..strokeWidth = 5..strokeCap = StrokeCap.round);
        canvas.drawCircle(const Offset(50, 52), 6, light);
      case VehicleIcon.van:
        body(const Rect.fromLTRB(28, 6, 72, 94), 10);
        windows(14, 34, 34);
        canvas.drawRect(const Rect.fromLTRB(32, 42, 68, 88), Paint()..color = Colors.white.withOpacity(0.22));
        headlights(11, 15);
      case VehicleIcon.truck:
        body(const Rect.fromLTRB(32, 4, 68, 28), 8);
        windows(10, 20, 28);
        body(const Rect.fromLTRB(28, 31, 72, 96), 6);
        canvas.drawRect(const Rect.fromLTRB(33, 38, 67, 90), Paint()..color = Colors.white.withOpacity(0.22));
      case VehicleIcon.arrow:
        final p = Path()
          ..moveTo(50, 6)
          ..lineTo(80, 88)
          ..lineTo(50, 70)
          ..lineTo(20, 88)
          ..close();
        canvas.drawPath(p, edge);
        canvas.drawPath(p, fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(VehicleGlyphPainter old) => old.icon != icon || old.color != color || old.outline != outline;
}

/// Widget d'aperçu d'un pictogramme (réglages).
class VehicleGlyph extends StatelessWidget {
  const VehicleGlyph(this.icon, {super.key, required this.color, this.size = 40});
  final VehicleIcon icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: VehicleGlyphPainter(icon, color)));
}

/// Image PNG du pictogramme, pour l'ajouter à la carte (repère de position).
Future<Uint8List> renderVehiclePng(VehicleIcon icon, Color color, {int px = 128}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  VehicleGlyphPainter(icon, color).paint(canvas, Size(px.toDouble(), px.toDouble()));
  final image = await recorder.endRecording().toImage(px, px);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Rendu du pictogramme impossible.');
  return data.buffer.asUint8List();
}

/// Véhicule suggéré pour un type de véhicule (premier choix à la sélection du type).
VehicleIcon defaultIconFor(VehicleType t) => switch (t) {
      VehicleType.car => VehicleIcon.car,
      VehicleType.microcar => VehicleIcon.compact,
      VehicleType.motorcycle => VehicleIcon.motorcycle,
      VehicleType.bicycle => VehicleIcon.bicycle,
      VehicleType.electric => VehicleIcon.electric,
      VehicleType.van => VehicleIcon.van,
      VehicleType.truck => VehicleIcon.truck,
    };
