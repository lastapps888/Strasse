import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/app/widgets/nav_helpers.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/offline_maps/offline_page.dart';
import 'package:strasse/features/routing/route_preview_page.dart';
import 'package:strasse/features/search/search_page.dart';

/// Onglet Favoris : domicile, travail, lieux enregistrés et collections.
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  String? _collectionFilter; // null = tous
  bool _searching = false;
  String _filter = '';

  bool get _reduce => ref.read(settingsProvider).reduceAnimations;

  Future<void> _setSpecial(FavoriteKind kind) async {
    final out = await Navigator.of(context).push<SearchOutcome>(
      MaterialPageRoute(builder: (_) => SearchPage(hint: kind == FavoriteKind.home ? 'Adresse du domicile' : 'Adresse du travail', showCategories: false)),
    );
    final p = out?.place;
    if (p == null || !mounted) return;
    await ref.read(dataActionsProvider).setSpecial(kind, p);
  }

  Future<void> _addFavorite() async {
    final out = await Navigator.of(context).push<SearchOutcome>(MaterialPageRoute(builder: (_) => const SearchPage(hint: 'Ajouter un favori', showCategories: false)));
    final p = out?.place;
    if (p == null || !mounted) return;
    await ref.read(dataActionsProvider).addFavorite(p, collectionId: _collectionFilter);
  }

  void _show(Favorite f) {
    ref.read(mapFocusProvider.notifier).state = MapFocus(place: f.toPlace());
    ref.read(shellIndexProvider.notifier).state = 1;
  }

  Future<void> _newCollection() async {
    final name = await askText(context, title: 'Nouvelle collection', hint: 'Ex. : Restaurants, Randonnées…');
    if (name == null || name.isEmpty) return;
    await ref.read(dataActionsProvider).createCollection(name);
  }

  Future<void> _collectionMenu(PlaceCollection c, List<Favorite> favs) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.edit_rounded), title: const Text('Renommer'), onTap: () => Navigator.pop(ctx, 'rename')),
            ListTile(leading: const Icon(Icons.arrow_back_rounded), title: const Text('Déplacer avant'), onTap: () => Navigator.pop(ctx, 'up')),
            ListTile(leading: const Icon(Icons.arrow_forward_rounded), title: const Text('Déplacer après'), onTap: () => Navigator.pop(ctx, 'down')),
            ListTile(leading: const Icon(Icons.ios_share_rounded), title: const Text('Partager la liste'), onTap: () => Navigator.pop(ctx, 'share')),
            ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Supprimer la collection'), onTap: () => Navigator.pop(ctx, 'delete')),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final actions = ref.read(dataActionsProvider);
    switch (choice) {
      case 'rename':
        final name = await askText(context, title: 'Renommer la collection', initial: c.name);
        if (name != null && name.isNotEmpty) await actions.updateCollection(c.copyWith(name: name));
      case 'up':
      case 'down':
        final list = [...(ref.read(collectionsProvider).valueOrNull ?? const <PlaceCollection>[])];
        final i = list.indexWhere((x) => x.id == c.id);
        final j = choice == 'up' ? i - 1 : i + 1;
        if (i < 0 || j < 0 || j >= list.length) return;
        list.insert(j, list.removeAt(i));
        await actions.reorderCollections(list);
      case 'share':
        final items = favs.where((f) => f.collectionId == c.id).toList();
        if (items.isEmpty) {
          showMessage(context, 'Cette collection est vide.');
          return;
        }
        final text = StringBuffer('${c.name}\n');
        for (final f in items) {
          text.writeln('• ${f.name} — https://www.openstreetmap.org/?mlat=${f.point.lat}&mlon=${f.point.lon}#map=17/${f.point.lat}/${f.point.lon}');
        }
        await Share.share(text.toString(), subject: c.name);
      case 'delete':
        final ok = await confirm(context, title: 'Supprimer « ${c.name} » ?', message: 'Les lieux de cette collection sont conservés dans vos favoris.');
        if (ok) {
          if (_collectionFilter == c.id) setState(() => _collectionFilter = null);
          await actions.deleteCollection(c.id);
        }
    }
  }

  Future<void> _favoriteMenu(Favorite f, List<PlaceCollection> collections) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.directions_rounded), title: const Text('Itinéraire'), onTap: () => Navigator.pop(ctx, 'route')),
            ListTile(leading: const Icon(Icons.edit_rounded), title: const Text('Renommer'), onTap: () => Navigator.pop(ctx, 'rename')),
            ListTile(leading: const Icon(Icons.notes_rounded), title: const Text('Note personnelle'), onTap: () => Navigator.pop(ctx, 'note')),
            ListTile(leading: const Icon(Icons.folder_open_rounded), title: const Text('Ranger dans une collection'), onTap: () => Navigator.pop(ctx, 'move')),
            ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Supprimer'), onTap: () => Navigator.pop(ctx, 'delete')),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final actions = ref.read(dataActionsProvider);
    switch (choice) {
      case 'route':
        pushPage(context, RoutePreviewPage(destination: f.toPlace()), reduce: _reduce);
      case 'rename':
        final name = await askText(context, title: 'Renommer', initial: f.name);
        if (name != null && name.isNotEmpty) await actions.updateFavorite(f.copyWith(name: name));
      case 'note':
        final note = await askText(context, title: 'Note personnelle', initial: f.note, maxLength: 300, maxLines: 4, hint: 'Visible uniquement par vous');
        if (note != null) await actions.updateFavorite(f.copyWith(note: note));
      case 'move':
        final target = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(leading: const Icon(Icons.folder_off_outlined), title: const Text('Aucune collection'), onTap: () => Navigator.pop(ctx, '')),
                for (final c in collections) ListTile(leading: const Icon(Icons.folder_rounded), title: Text(c.name), onTap: () => Navigator.pop(ctx, c.id)),
                if (collections.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Créez d\'abord une collection.')),
              ],
            ),
          ),
        );
        if (target == null) return;
        await actions.updateFavorite(target.isEmpty ? f.copyWith(clearCollection: true) : f.copyWith(collectionId: target));
      case 'delete':
        await actions.deleteFavorite(f.id);
        if (mounted) showMessage(context, 'Favori supprimé', action: SnackBarAction(label: 'Annuler', onPressed: () => actions.restoreFavorite(f.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final favsAsync = ref.watch(favoritesProvider);
    final collections = ref.watch(collectionsProvider).valueOrNull ?? const <PlaceCollection>[];
    final padding = MediaQuery.paddingOf(context);
    final home = ref.watch(homeFavoriteProvider).valueOrNull;
    final work = ref.watch(workFavoriteProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(autofocus: true, decoration: const InputDecoration(hintText: 'Filtrer mes favoris'), onChanged: (v) => setState(() => _filter = foldText(v.trim())))
            : const Text('Favoris'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Fermer la recherche' : 'Rechercher dans mes favoris',
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _searching = !_searching;
              _filter = '';
            }),
          ),
          IconButton(tooltip: 'Nouvelle collection', icon: const Icon(Icons.create_new_folder_outlined), onPressed: _newCollection),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 80 + padding.bottom),
        child: FloatingActionButton.extended(onPressed: _addFavorite, icon: const Icon(Icons.add_rounded), label: const Text('Ajouter')),
      ),
      body: favsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(favoritesProvider)),
        data: (all) {
          final places = all.where((f) => f.kind == FavoriteKind.place && (_collectionFilter == null || f.collectionId == _collectionFilter) && (_filter.isEmpty || foldText('${f.name} ${f.address ?? ''} ${f.note ?? ''}').contains(_filter))).toList();
          return ListView(
            padding: EdgeInsets.only(bottom: 180 + padding.bottom),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Expanded(child: _special(context, Icons.home_rounded, 'Domicile', home)),
                    const SizedBox(width: 12),
                    Expanded(child: _special(context, Icons.work_rounded, 'Travail', work)),
                  ],
                ),
              ),
              if (collections.isNotEmpty) ...[
                const SectionTitle('Collections'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.45,
                    children: [
                      for (var i = 0; i < collections.length; i++)
                        _collectionTile(context, collections[i], all.where((f) => f.collectionId == collections[i].id && !f.deleted).length, i, () => _collectionMenu(collections[i], all)),
                    ],
                  ),
                ),
                const Padding(padding: EdgeInsets.fromLTRB(20, 6, 20, 0), child: Text('Touchez une collection pour filtrer · appui long : renommer, déplacer, partager, supprimer', style: TextStyle(fontSize: 11))),
              ],
              SectionTitle(_collectionFilter == null ? 'Mes lieux enregistrés' : 'Dans cette collection'),
              if (places.isEmpty)
                const EmptyViewInline(icon: Icons.star_outline_rounded, text: 'Aucun favori ici. Touchez « Ajouter » ou enregistrez un lieu depuis la carte.')
              else
                for (final f in places)
                  ListTile(
                    leading: IconBadge(icon: Icons.star_rounded, color: context.sc.warning),
                    title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text([if (f.note != null && f.note!.isNotEmpty) f.note!, if (f.address != null) f.address!].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => _show(f),
                    trailing: IconButton(tooltip: 'Options', icon: const Icon(Icons.more_vert_rounded), onPressed: () => _favoriteMenu(f, collections)),
                  ),
              const SectionTitle('Cartes hors connexion'),
              _offlineCard(context),
            ],
          );
        },
      ),
    );
  }

  Widget _collectionTile(BuildContext context, PlaceCollection c, int count, int index, VoidCallback onMenu) {
    final cs = context.cs;
    final selected = _collectionFilter == c.id;
    // Dégradé issu des couleurs du thème (pas de photo : aucune image n'est inventée).
    final tints = [context.sc.land, context.sc.sea, cs.primary, context.sc.warning];
    final base = tints[index % tints.length];
    return Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _collectionFilter = selected ? null : c.id),
        onLongPress: onMenu,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [base.withOpacity(0.85), base.withOpacity(0.45)]),
            border: selected ? Border.all(color: cs.primary, width: 3) : null,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.folder_rounded, color: Colors.white, size: 28),
              const Spacer(),
              Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              Text('($count lieu${count > 1 ? 'x' : ''})', style: const TextStyle(color: Colors.white, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _offlineCard(BuildContext context) {
    final regions = ref.watch(offlineManagerProvider);
    final units = ref.watch(settingsProvider.select((s) => s.units));
    final cs = context.cs;
    final r = regions.isEmpty ? null : regions.first;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => pushPage(context, const OfflinePage(), reduce: _reduce),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const IconBadge(icon: Icons.download_for_offline_rounded, size: 48, iconSize: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: r == null
                      ? const Text('Aucune zone téléchargée. Touchez pour en ajouter.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(
                              r.status == OfflineStatus.downloading ? '${r.progress.toStringAsFixed(0)} % · ${formatBytes(r.sizeBytes)} estimés' : (r.isComplete ? 'Disponible · ${formatBytes(r.sizeBytes)}' : 'Échec du téléchargement'),
                              style: context.tt.bodySmall,
                            ),
                            if (r.status == OfflineStatus.downloading) Padding(padding: const EdgeInsets.only(top: 6), child: LinearProgressIndicator(value: r.progress > 0 ? (r.progress / 100).clamp(0.0, 1.0) : null, color: cs.primary)),
                          ],
                        ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _special(BuildContext context, IconData icon, String title, Favorite? f) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => f == null ? _setSpecial(title == 'Domicile' ? FavoriteKind.home : FavoriteKind.work) : _show(f),
          onLongPress: () => _setSpecial(title == 'Domicile' ? FavoriteKind.home : FavoriteKind.work),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                IconBadge(icon: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(f == null ? 'Touchez pour définir' : (f.address ?? 'Définie'), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// État vide compact, à l'intérieur d'une liste.
class EmptyViewInline extends StatelessWidget {
  const EmptyViewInline({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [Icon(icon, size: 44, color: context.cs.outline), const SizedBox(height: 10), Text(text, textAlign: TextAlign.center)]),
      );
}
