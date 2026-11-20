import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:share_plus/share_plus.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';

/// Partage de lieux, d'itinéraires et de textes.
///
/// Utilise l'API actuelle de share_plus (`SharePlus.instance.share(ShareParams(...))`). Si la feuille de partage système
/// est indisponible ou échoue, le texte est copié dans le presse-papiers et l'utilisateur en est informé :
/// un partage ne doit jamais échouer en silence.
class ShareService {
  const ShareService._();

  /// Lien OpenStreetMap d'un point (ouvrable dans n'importe quel navigateur, sans compte).
  static String osmPointLink(GeoPoint p) =>
      'https://www.openstreetmap.org/?mlat=${p.lat.toStringAsFixed(6)}&mlon=${p.lon.toStringAsFixed(6)}#map=17/${p.lat.toStringAsFixed(6)}/${p.lon.toStringAsFixed(6)}';

  /// Lien d'itinéraire OpenStreetMap (moteur FOSSGIS OSRM), départ → arrivée.
  static String osmRouteLink(GeoPoint from, GeoPoint to, TravelMode mode) {
    final engine = switch (mode) {
      TravelMode.bike => 'fossgis_osrm_bike',
      TravelMode.walk => 'fossgis_osrm_foot',
      _ => 'fossgis_osrm_car',
    };
    String c(GeoPoint p) => '${p.lat.toStringAsFixed(6)},${p.lon.toStringAsFixed(6)}';
    return 'https://www.openstreetmap.org/directions?engine=$engine&route=${c(from)};${c(to)}';
  }

  static String geoUri(GeoPoint p, [String? label]) {
    final q = label == null || label.isEmpty ? '' : '?q=${p.lat.toStringAsFixed(6)},${p.lon.toStringAsFixed(6)}(${Uri.encodeComponent(label)})';
    return 'geo:${p.lat.toStringAsFixed(6)},${p.lon.toStringAsFixed(6)}$q';
  }

  static String placeText(Place place) {
    final b = StringBuffer(place.title);
    final sub = place.subtitle;
    if (sub != null && sub.isNotEmpty) b.write('\n$sub');
    b.write('\n${place.point.lat.toStringAsFixed(5)}, ${place.point.lon.toStringAsFixed(5)}');
    b.write('\n${osmPointLink(place.point)}');
    b.write('\n${geoUri(place.point, place.title)}');
    return b.toString();
  }

  static String routeText({
    required String originLabel,
    required String destinationLabel,
    required GeoPoint from,
    required GeoPoint to,
    required TravelMode mode,
    required String summary,
  }) {
    final b = StringBuffer('$originLabel → $destinationLabel');
    if (summary.isNotEmpty) b.write('\n$summary');
    b.write('\n${osmRouteLink(from, to, mode)}');
    b.write('\n${geoUri(to, destinationLabel)}');
    return b.toString();
  }

  static Rect? _origin(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize && box.attached) {
      final r = box.localToGlobal(Offset.zero) & box.size;
      if (r.width > 0 && r.height > 0) return r;
    }
    return null;
  }

  /// Ouvre la feuille de partage. Renvoie vrai si elle s'est ouverte, faux si le texte a été copié à la place.
  static Future<bool> shareText(BuildContext context, String text, {String? subject}) async {
    final origin = _origin(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: text, subject: subject, title: subject, sharePositionOrigin: origin),
      );
      if (result.status != ShareResultStatus.unavailable) return true;
    } catch (_) {
      // on bascule sur le presse-papiers ci-dessous
    }
    await Clipboard.setData(ClipboardData(text: text));
    messenger?.showSnackBar(const SnackBar(content: Text('Partage indisponible sur cet appareil : le texte a été copié dans le presse-papiers.')));
    return false;
  }

  static Future<bool> sharePlace(BuildContext context, Place place) => shareText(context, placeText(place), subject: place.title);

  static Future<bool> shareRoute(
    BuildContext context, {
    required String originLabel,
    required String destinationLabel,
    required GeoPoint from,
    required GeoPoint to,
    required TravelMode mode,
    required String summary,
  }) =>
      shareText(
        context,
        routeText(originLabel: originLabel, destinationLabel: destinationLabel, from: from, to: to, mode: mode, summary: summary),
        subject: '$originLabel → $destinationLabel',
      );
}
