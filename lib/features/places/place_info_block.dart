import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:url_launcher/url_launcher.dart';

/// Photo (Wikimedia Commons, avec auteur et licence) et résumé (Wikipédia) d'un lieu nommé, si un article correspond
/// vraiment à ce lieu. Les notes et avis d'utilisateurs n'existent dans aucune source ouverte : le bouton « Notes et avis »
/// ouvre, à la demande, la fiche du lieu dans le service de cartes de l'utilisateur ; rien n'est envoyé avant ce geste.
class PlaceInfoBlock extends ConsumerWidget {
  const PlaceInfoBlock({super.key, required this.place, this.showOwnPhoto = true});
  final Place place;
  final bool showOwnPhoto;

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.cs;
    final named = place.name.trim().length >= 3;
    final info = named ? ref.watch(placeInfoProvider((place.name, place.point.lat, place.point.lon))).valueOrNull : null;
    final reviewsUrl = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('${place.name} ${place.point.lat},${place.point.lon}')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (info?.photoUrl != null && showOwnPhoto) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(info!.photoUrl!, height: 150, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
          InkWell(
            onTap: info.photoPageUrl == null ? null : () => _open(info.photoPageUrl!),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [if (info.photoAuthor != null) '© ${info.photoAuthor}', if (info.photoLicense != null) info.photoLicense!, 'Wikimedia Commons'].join(' · '),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (info?.summary != null) ...[
          Text(info!.summary!, maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
          if (info.articleUrl != null)
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32), alignment: Alignment.centerLeft),
              onPressed: () => _open(info.articleUrl!),
              child: const Text('Lire la suite sur Wikipédia (CC BY-SA)'),
            ),
        ],
        if (named)
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32), alignment: Alignment.centerLeft),
            onPressed: () => _open(reviewsUrl),
            icon: const Icon(Icons.star_border_rounded, size: 18),
            label: const Text('Notes et avis (ouvre Google Maps)'),
          ),
      ],
    );
  }
}
