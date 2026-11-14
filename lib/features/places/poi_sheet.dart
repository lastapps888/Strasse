import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/places/booking_page.dart';
import 'package:strasse/features/services/provider_models.dart';
import 'package:url_launcher/url_launcher.dart';

/// Fiche d'un hôtel, restaurant ou site : informations d'OpenStreetMap / OpenTripMap, et accès à la réservation.
///
/// Quatre notions restent séparées à l'écran : la découverte (le lieu existe), l'information (ce que disent les données
/// ouvertes), la disponibilité (jamais affichée : aucune source ouverte) et la réservation (faite sur le site).
class PoiSheet extends ConsumerWidget {
  const PoiSheet({super.key, required this.poi, required this.onRoute});
  final Poi poi;
  final VoidCallback onRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.cs;
    final units = ref.watch(settingsProvider.select((s) => s.units));
    final provider = ref.watch(providerResolverProvider).selected(ServiceCategory.booking);
    final url = poi.kind == PoiKind.tourism || poi.kind == PoiKind.other ? poi.place.website : bookingUrlFor(poi, provider.adapter);
    final place = poi.place;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (poi.photoUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(poi.photoUrl!, height: 150, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            const SizedBox(height: 10),
            Text(place.name, style: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text([poi.kind.label, if (place.category != null && place.category != poi.kind.label) place.category!, if (poi.cuisine != null) poi.cuisine!.replaceAll(';', ', ')].join(' · '), style: context.tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            if (poi.stars != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${'★' * poi.stars!} classement officiel (pas une note d\'utilisateurs)', style: context.tt.bodySmall)),
            if (poi.distanceMeters != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('À ${formatDistance(poi.distanceMeters!, units)}', style: context.tt.bodySmall)),
            if (place.address != null) _line(context, Icons.place_outlined, place.address!),
            if (place.openingHours != null) _line(context, Icons.schedule_rounded, 'Horaires OSM : ${place.openingHours}'),
            if (place.phone != null) _line(context, Icons.phone_outlined, place.phone!, onTap: () => launchUrl(Uri(scheme: 'tel', path: place.phone!.replaceAll(' ', '')))),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(onPressed: onRoute, icon: const Icon(Icons.directions_rounded), label: const Text('Itinéraire')),
                if (place.website != null)
                  OutlinedButton.icon(onPressed: () => _open(context, place.name, place.website!), icon: const Icon(Icons.public_rounded), label: const Text('Site Internet')),
                if ((poi.kind == PoiKind.hotel || poi.kind == PoiKind.restaurant) && url != null)
                  OutlinedButton.icon(onPressed: () => _open(context, place.name, url), icon: const Icon(Icons.event_available_outlined), label: Text(poi.kind == PoiKind.hotel ? 'Réserver / voir les disponibilités' : 'Réserver une table')),
              ],
            ),
            if ((poi.kind == PoiKind.hotel || poi.kind == PoiKind.restaurant) && url == null)
              Padding(padding: const EdgeInsets.only(top: 10), child: Text('Aucun lien de réservation n\'est renseigné pour cet établissement dans les données ouvertes.', style: context.tt.bodySmall)),
            const SizedBox(height: 10),
            Text('Source : ${poi.source == 'osm' ? 'OpenStreetMap' : 'OpenTripMap'}. Strasse n\'affiche ni disponibilité ni prix : ils dépendent du site de réservation.', style: context.tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context, IconData icon, String text, {VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.only(top: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 18, color: context.cs.primary), const SizedBox(width: 8), Expanded(child: Text(text))])),
      );

  void _open(BuildContext context, String title, String url) {
    if (!url.startsWith('https://')) {
      showMessage(context, 'Ce lien n\'est pas sécurisé (HTTPS) : il n\'est pas ouvert dans l\'application.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookingPage(title: title, url: url)));
  }
}
