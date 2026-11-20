import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Catégories de lieux affichées sur la carte, chacune avec son badge (pastille colorée + pictogramme blanc).
/// Les pictogrammes viennent de la police d'icônes Material embarquée ; les pastilles sont dessinées par le code.
class PoiBadge {
  const PoiBadge(this.id, this.icon, this.color, this.classes);
  final String id;
  final IconData icon;
  final Color color;

  /// Valeurs de `class` du schéma de tuiles OpenMapTiles associées à ce badge.
  final List<String> classes;

  String get image => 'poi-$id';
}

class PoiBadges {
  const PoiBadges._();

  static const other = PoiBadge('other', Icons.place_rounded, Color(0xFF607D8B), []);

  static const all = <PoiBadge>[
    PoiBadge('food', Icons.restaurant_rounded, Color(0xFFE65100), ['restaurant', 'fast_food', 'food_court', 'ice_cream']),
    PoiBadge('cafe', Icons.local_cafe_rounded, Color(0xFF6D4C41), ['cafe', 'bakery', 'confectionery']),
    PoiBadge('bar', Icons.local_bar_rounded, Color(0xFF8E24AA), ['bar', 'pub', 'biergarten', 'nightclub', 'alcohol_shop']),
    PoiBadge('shop', Icons.shopping_bag_rounded, Color(0xFF1E88E5), ['shop', 'grocery', 'clothing_store', 'convenience', 'supermarket', 'mall', 'department_store', 'furniture', 'hardware', 'butcher', 'florist', 'bicycle', 'library', 'bookstore']),
    PoiBadge('lodging', Icons.hotel_rounded, Color(0xFF6A1B9A), ['lodging', 'hotel', 'hostel', 'guest_house', 'camp_site', 'caravan_site']),
    PoiBadge('transit', Icons.directions_transit_rounded, Color(0xFF00897B), ['bus', 'railway', 'subway', 'tram', 'ferry_terminal', 'aerialway', 'station', 'bus_station']),
    PoiBadge('health', Icons.local_hospital_rounded, Color(0xFFD32F2F), ['hospital', 'doctors', 'dentist', 'clinic', 'pharmacy', 'veterinary']),
    PoiBadge('culture', Icons.museum_rounded, Color(0xFFF9A825), ['museum', 'attraction', 'gallery', 'theatre', 'cinema', 'zoo', 'castle', 'monument', 'artwork', 'viewpoint', 'information']),
    PoiBadge('park', Icons.park_rounded, Color(0xFF388E3C), ['park', 'playground', 'garden', 'dog_park', 'picnic_site', 'nature_reserve', 'beach', 'campsite']),
    PoiBadge('sport', Icons.fitness_center_rounded, Color(0xFF0288D1), ['stadium', 'swimming', 'sports_centre', 'pitch', 'golf', 'fitness_centre', 'swimming_pool', 'ski']),
    PoiBadge('fuel', Icons.local_gas_station_rounded, Color(0xFFEF6C00), ['fuel', 'charging_station', 'car_repair', 'car_wash']),
    PoiBadge('parking', Icons.local_parking_rounded, Color(0xFF3949AB), ['parking', 'bicycle_parking', 'bicycle_rental']),
    PoiBadge('school', Icons.school_rounded, Color(0xFF5D4037), ['school', 'college', 'university', 'kindergarten']),
    PoiBadge('service', Icons.account_balance_rounded, Color(0xFF455A64), ['bank', 'atm', 'post', 'police', 'townhall', 'town_hall', 'courthouse', 'fire_station', 'place_of_worship', 'religious', 'toilets']),
  ];

  static PoiBadge forClass(String? c) {
    if (c == null) return other;
    for (final b in all) {
      if (b.classes.contains(c)) return b;
    }
    return other;
  }

  /// Expression MapLibre : `class` → nom de l'image du badge.
  static List<dynamic> iconExpression() => [
        'match',
        ['get', 'class'],
        for (final b in all) ...[b.classes, b.image],
        other.image,
      ];

  /// Dessine le badge en PNG (pastille de 40 px logiques ; rendu ×3 pour rester net sur les écrans denses).
  static Future<Uint8List> render(PoiBadge b, {double scale = 3}) async {
    const size = 40.0;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.scale(scale);
    final center = const Offset(size / 2, size / 2);
    canvas.drawCircle(center + const Offset(0, 1), 17, Paint()..color = const Color(0x33000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawCircle(center, 17, Paint()..color = Colors.white);
    canvas.drawCircle(center, 15, Paint()..color = b.color);
    final tp = TextPainter(
      text: TextSpan(text: String.fromCharCode(b.icon.codePoint), style: TextStyle(fontFamily: b.icon.fontFamily, package: b.icon.fontPackage, fontSize: 21, color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    final img = await rec.endRecording().toImage((size * scale).round(), (size * scale).round());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
}
