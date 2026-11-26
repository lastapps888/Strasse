import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/places/mapillary_viewer_page.dart';
import 'package:url_launcher/url_launcher.dart';

/// Photo (Wikimedia Commons, avec auteur et licence) et résumé (Wikipédia) d'un lieu nommé, si un article correspond
/// vraiment à ce lieu. Les avis Google Maps sont affichés uniquement lorsque le fournisseur est configuré et qu'un lieu correspondant est trouvé. La vue Mapillary est ouverte séparément à la demande.
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
    final reviews = named ? ref.watch(placeReviewsProvider((place.name, place.point.lat, place.point.lon))).valueOrNull : null;
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
        if (reviews != null) ...[
          const SizedBox(height: 12),
          const Divider(),
          Text('Avis Google Maps', style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              'Jusqu’à cinq avis, classés par pertinence selon Google Maps.',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
          if (reviews.rating != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.star_rounded, size: 20, color: context.sc.warning),
                  const SizedBox(width: 5),
                  Text(reviews.rating!.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 6),
                  Text('· ${reviews.userRatingCount} évaluations', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
          for (final review in reviews.reviews)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (review.authorPhotoUri != null)
                        CircleAvatar(
                          radius: 14,
                          backgroundImage: NetworkImage(review.authorPhotoUri!),
                        )
                      else
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: cs.surfaceContainerHighest,
                          child: Icon(Icons.person_outline_rounded, size: 17, color: cs.onSurfaceVariant),
                        ),
                      const SizedBox(width: 7),
                      Icon(Icons.star_rounded, size: 16, color: context.sc.warning),
                      const SizedBox(width: 3),
                      Text(review.rating.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 7),
                      Expanded(
                        child: InkWell(
                          onTap: review.authorUri == null ? null : () => _open(review.authorUri!),
                          child: Text(
                            review.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              decoration: review.authorUri == null ? TextDecoration.none : TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (review.relativeTime != null || review.visitDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        [
                          if (review.relativeTime != null) review.relativeTime!,
                          if (review.visitDate != null) 'Visite : ${review.visitDate}',
                        ].join(' · '),
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(review.text, style: const TextStyle(fontSize: 13)),
                  if (review.translated)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('Avis traduit automatiquement.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    ),
                  if (review.googleMapsUri != null || review.flagContentUri != null)
                    Wrap(
                      spacing: 4,
                      children: [
                        if (review.googleMapsUri != null)
                          TextButton.icon(
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 30)),
                            onPressed: () => _open(review.googleMapsUri!),
                            icon: const Icon(Icons.open_in_new_rounded, size: 14),
                            label: const Text('Voir cet avis'),
                          ),
                        if (review.flagContentUri != null)
                          TextButton.icon(
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 30)),
                            onPressed: () => _open(review.flagContentUri!),
                            icon: const Icon(Icons.flag_outlined, size: 14),
                            label: const Text('Signaler'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          Text('Avis et évaluations fournis par Google Maps.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          if (reviews.googleMapsUri != null)
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32), alignment: Alignment.centerLeft),
              onPressed: () => _open(reviews.googleMapsUri!),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Voir sur Google Maps'),
            ),
        ],
        if (named) ...[
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32), alignment: Alignment.centerLeft),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => MapillaryViewerPage(place: place),
            )),
            icon: const Icon(Icons.streetview_rounded, size: 18),
            label: const Text('Explorer les images de rue (Mapillary)'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'La vue dépend des images communautaires disponibles à cet endroit. Le lieu est transmis à Mapillary pour centrer la carte.',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}
