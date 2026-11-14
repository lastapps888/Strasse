import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/core/i18n/translator.dart';
import 'package:strasse/domain/domain.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Adresse à ouvrir pour réserver, selon le fournisseur choisi dans Réglages > Services > Réservations.
/// Retourne null quand rien d'exploitable n'existe (on ne fabrique jamais de lien de réservation direct).
String? bookingUrlFor(Poi poi, String adapter) {
  final name = Uri.encodeQueryComponent([poi.place.name, if (poi.place.address != null) poi.place.address!.split(',').last.trim()].join(' '));
  switch (adapter) {
    case 'link-booking':
      return poi.kind == PoiKind.hotel ? 'https://www.booking.com/searchresults.html?ss=$name' : poi.bookingTarget;
    case 'link-thefork':
      // Adresse de recherche non vérifiée : TheFork n'a pas d'API publique.
      return poi.kind == PoiKind.restaurant ? 'https://www.thefork.fr/search?q=$name' : poi.bookingTarget;
    default:
      return poi.bookingTarget;
  }
}

/// Navigateur intégré pour la réservation. HTTPS uniquement. Strasse ne lit rien de la page et ne confirme
/// aucune disponibilité : la réservation est faite sur le site de l'établissement ou du service.
class BookingPage extends StatefulWidget {
  const BookingPage({super.key, required this.title, required this.url});
  final String title;
  final String url;

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _blocked;

  @override
  void initState() {
    super.initState();
    final uri = Uri.parse(widget.url);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onNavigationRequest: (req) {
          if (!req.url.startsWith('https://')) {
            setState(() => _blocked = 'Lien non sécurisé bloqué : ${req.url}');
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ));
    if (uri.scheme == 'https') {
      _controller.loadRequest(uri);
    } else {
      _blocked = 'Seules les adresses HTTPS sont ouvertes dans l\'application.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: tr('Ouvrir dans le navigateur'), icon: const Icon(Icons.open_in_new_rounded), onPressed: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication)),
        ],
        bottom: _progress < 100 ? PreferredSize(preferredSize: const Size.fromHeight(3), child: LinearProgressIndicator(value: _progress / 100)) : null,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: context.cs.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(_blocked ?? 'Site externe : Strasse ne vérifie ni la disponibilité ni le prix. La réservation est confirmée par le site.', style: context.tt.bodySmall),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
