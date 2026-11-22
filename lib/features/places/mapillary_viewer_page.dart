import 'package:flutter/material.dart';
import 'package:strasse/domain/domain.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Ouvre le visualiseur public Mapillary dans Strasse, centré sur le lieu choisi.
/// Aucun jeton API n'est intégré à l'application : il s'agit du site officiel embarqué dans une WebView.
class MapillaryViewerPage extends StatefulWidget {
  const MapillaryViewerPage({super.key, required this.place});

  final Place place;

  @override
  State<MapillaryViewerPage> createState() => _MapillaryViewerPageState();
}

class _MapillaryViewerPageState extends State<MapillaryViewerPage> {
  late final Uri _uri;
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _uri = Uri.https('www.mapillary.com', '/app/', {
      'lat': widget.place.point.lat.toStringAsFixed(7),
      'lng': widget.place.point.lon.toStringAsFixed(7),
      'z': '17',
    });
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() {
              _loading = true;
              _error = null;
            });
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _loading = false;
                _error = error.description;
              });
            }
          },
        ),
      )
      ..loadRequest(_uri);
  }

  Future<void> _openInBrowser() async {
    final opened = await launchUrl(_uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir Mapillary dans le navigateur.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Images de rue'),
        actions: [
          IconButton(
            tooltip: 'Ouvrir dans le navigateur',
            onPressed: _openInBrowser,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 36),
                    const SizedBox(height: 12),
                    const Text('Impossible de charger les images de rue.'),
                    const SizedBox(height: 6),
                    Text(_error!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          _loading = true;
                          _error = null;
                        });
                        _controller.reload();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Réessayer'),
                    ),
                    TextButton(onPressed: _openInBrowser, child: const Text('Ouvrir dans le navigateur')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
