import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:url_launcher/url_launcher.dart';

/// Fiche d'un lieu : adresse, catégorie, coordonnées et — uniquement si la source les fournit — téléphone,
/// site web et horaires. Aucune note, photo ni avis n'est affiché : ces données n'existent pas dans OpenStreetMap.
class PlaceSheet extends ConsumerWidget {
  const PlaceSheet({super.key, required this.place, required this.onRoute, this.onClose, this.loading = false, this.distanceFrom});

  final Place place;
  final VoidCallback onRoute;
  final VoidCallback? onClose;

  /// Vrai pendant la recherche inverse (appui long) : l'adresse n'est pas encore connue.
  final bool loading;
  final GeoPoint? distanceFrom;

  Favorite? _favoriteFor(List<Favorite> favs) {
    for (final f in favs) {
      if (f.deleted) continue;
      if (distanceM(f.point, place.point) < 30) return f;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoritesProvider).valueOrNull ?? const <Favorite>[];
    final fav = _favoriteFor(favs);
    final units = ref.watch(settingsProvider.select((s) => s.units));
    final actions = ref.read(dataActionsProvider);
    final cs = context.cs;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(place.title, style: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w800), maxLines: 3, overflow: TextOverflow.ellipsis),
                    if (loading)
                      const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator())
                    else if (place.subtitle != null)
                      Padding(padding: const EdgeInsets.only(top: 4), child: Text(place.subtitle!, style: context.tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
                  ],
                ),
              ),
              if (onClose != null) IconButton(tooltip: 'Fermer', icon: const Icon(Icons.close_rounded), onPressed: onClose),
            ],
          ),
          if (distanceFrom != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('À ${formatDistance(distanceM(distanceFrom!, place.point), units)} à vol d\'oiseau', style: context.tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(onPressed: onRoute, icon: const Icon(Icons.directions_rounded), label: const Text('Itinéraire')),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (fav != null) {
                      await actions.deleteFavorite(fav.id);
                      if (context.mounted) {
                        showMessage(context, 'Retiré des favoris', action: SnackBarAction(label: 'Annuler', onPressed: () => actions.restoreFavorite(fav.id)));
                      }
                    } else {
                      await actions.addFavorite(place);
                      await actions.rememberPlace(place);
                      if (context.mounted) showMessage(context, 'Ajouté aux favoris');
                    }
                  },
                  icon: Icon(fav != null ? Icons.star_rounded : Icons.star_outline_rounded, color: fav != null ? context.sc.warning : null),
                  label: Text(fav != null ? 'Favori' : 'Enregistrer'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('Partager'),
                onPressed: () => Share.share(_shareText(), subject: place.title),
              ),
              ActionChip(
                avatar: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copier les coordonnées'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: place.coordsLabel));
                  if (context.mounted) showMessage(context, 'Coordonnées copiées');
                },
              ),
              if (place.phone != null)
                ActionChip(
                  avatar: const Icon(Icons.call_rounded, size: 18),
                  label: const Text('Appeler'),
                  onPressed: () => _open(context, Uri(scheme: 'tel', path: place.phone!.replaceAll(RegExp(r'\s'), ''))),
                ),
              if (place.website != null)
                ActionChip(
                  avatar: const Icon(Icons.language_rounded, size: 18),
                  label: const Text('Site web'),
                  onPressed: () {
                    final u = Uri.tryParse(place.website!.startsWith('http') ? place.website! : 'https://${place.website}');
                    if (u != null) _open(context, u);
                  },
                ),
            ],
          ),
          const Divider(height: 28),
          if (place.category != null) _info(context, Icons.category_outlined, place.category!),
          if (place.openingHours != null) _info(context, Icons.schedule_rounded, place.openingHours!, caption: 'Horaires (données OpenStreetMap, non vérifiées)'),
          if (place.phone != null) _info(context, Icons.call_outlined, place.phone!),
          if (place.description != null) _info(context, Icons.notes_rounded, place.description!),
          _info(context, Icons.my_location_rounded, place.coordsLabel, caption: 'Coordonnées GPS'),
        ],
      ),
    );
  }

  String _shareText() {
    final b = StringBuffer(place.title);
    if (place.subtitle != null) b.write('\n${place.subtitle}');
    b.write('\n${place.coordsLabel}');
    b.write('\nhttps://www.openstreetmap.org/?mlat=${place.point.lat}&mlon=${place.point.lon}#map=17/${place.point.lat}/${place.point.lon}');
    return b.toString();
  }

  Future<void> _open(BuildContext context, Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) showMessage(context, 'Impossible d\'ouvrir ce lien sur cet appareil.');
    } catch (_) {
      if (context.mounted) showMessage(context, 'Impossible d\'ouvrir ce lien sur cet appareil.');
    }
  }

  Widget _info(BuildContext context, IconData icon, String text, {String? caption}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: context.cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(text, style: context.tt.bodyMedium),
                  if (caption != null) Text(caption, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      );
}
