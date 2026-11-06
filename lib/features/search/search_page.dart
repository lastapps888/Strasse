import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/geocoder_client.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';

/// Résultat renvoyé par la page de recherche : un lieu choisi, ou un ensemble de résultats à montrer sur la carte.
class SearchOutcome {
  const SearchOutcome.place(Place this.place)
      : results = const [],
        label = null;
  const SearchOutcome.results(this.results, this.label) : place = null;

  final Place? place;
  final List<Place> results;
  final String? label;
}

IconData categoryIcon(PlaceCategory c) => switch (c) {
      PlaceCategory.fuel => Icons.local_gas_station_rounded,
      PlaceCategory.parking => Icons.local_parking_rounded,
      PlaceCategory.restaurant => Icons.restaurant_rounded,
      PlaceCategory.cafe => Icons.local_cafe_rounded,
      PlaceCategory.pharmacy => Icons.local_pharmacy_rounded,
      PlaceCategory.hotel => Icons.hotel_rounded,
      PlaceCategory.supermarket => Icons.shopping_cart_rounded,
      PlaceCategory.charging => Icons.ev_station_rounded,
      PlaceCategory.atm => Icons.atm_rounded,
      PlaceCategory.toilets => Icons.wc_rounded,
      PlaceCategory.rest => Icons.airline_seat_recline_normal_rounded,
    };

IconData iconForPlace(Place p) {
  switch (p.source) {
    case 'favorite':
      return Icons.star_rounded;
    case 'history':
      return Icons.history_rounded;
    case 'coordinates':
      return Icons.my_location_rounded;
    default:
      return Icons.place_rounded;
  }
}

/// Recherche de lieux : saisie avec attente, résultats locaux (favoris, récents) puis géocodeur,
/// coordonnées GPS, catégories autour de soi, historique des recherches.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.hint = 'Rechercher un lieu ou une adresse', this.showCategories = true, this.title});

  final String hint;
  final bool showCategories;
  final String? title;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  CancelToken? _cancel;

  List<Place> _remote = const [];
  bool _loading = false;
  Object? _error;
  String _lastQuery = '';
  bool _inViewport = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cancel?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  GeoPoint? get _here => ref.read(locationControllerProvider).fix?.point;

  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      _cancel?.cancel();
      setState(() {
        _remote = const [];
        _loading = false;
        _error = null;
        _lastQuery = '';
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 380), () => _run(q));
  }

  Future<void> _run(String q) async {
    _cancel?.cancel();
    final token = _cancel = CancelToken();
    final geocoder = ref.read(geocoderProvider);
    try {
      final viewport = _inViewport ? ref.read(mapViewportProvider) : null;
      final res = await geocoder.search(q, near: _here ?? ref.read(mapViewportProvider)?.center, bounds: viewport, bounded: viewport != null, cancel: token);
      if (!mounted || token.isCancelled) return;
      setState(() {
        _remote = res;
        _loading = false;
        _error = null;
        _lastQuery = q;
      });
    } catch (e) {
      if (!mounted || (e is DioException && CancelToken.isCancel(e))) return;
      setState(() {
        _remote = const [];
        _loading = false;
        _error = e;
        _lastQuery = q;
      });
    }
  }

  Future<void> _choose(Place p) async {
    final actions = ref.read(dataActionsProvider);
    final settings = ref.read(settingsProvider);
    if (settings.historyEnabled) {
      await actions.rememberPlace(p);
      if (_controller.text.trim().isNotEmpty) await actions.rememberQuery(_controller.text.trim());
    }
    if (!mounted) return;
    Navigator.of(context).pop(SearchOutcome.place(p));
  }

  Future<void> _category(PlaceCategory c) async {
    final geocoder = ref.read(geocoderProvider);
    final viewport = ref.read(mapViewportProvider);
    final here = _here;
    final bounds = here != null ? GeoBounds.around(here, 5000) : viewport;
    if (bounds == null) {
      showMessage(context, 'Activez la localisation ou déplacez la carte pour chercher autour de vous.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await geocoder.search(c.query, bounds: bounds, bounded: true, limit: 20);
      if (!mounted) return;
      if (res.isEmpty) {
        setState(() => _loading = false);
        showMessage(context, 'Aucun résultat « ${c.label} » dans cette zone.');
        return;
      }
      Navigator.of(context).pop(SearchOutcome.results(res, c.label));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  List<Place> _localMatches(String q) {
    final fq = foldText(q);
    if (fq.length < 2) return const [];
    final out = <Place>[];
    final favs = ref.read(favoritesProvider).valueOrNull ?? const <Favorite>[];
    for (final f in favs) {
      if (f.deleted) continue;
      if (foldText('${f.name} ${f.address ?? ''}').contains(fq)) out.add(f.toPlace());
    }
    final recents = ref.read(recentPlacesProvider).valueOrNull ?? const <Place>[];
    for (final p in recents) {
      if (foldText('${p.name} ${p.address ?? ''}').contains(fq) && !out.any((o) => distanceM(o.point, p.point) < 30)) {
        out.add(p.copyWith(source: 'history'));
      }
    }
    return out.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text.trim();
    final online = ref.watch(onlineProvider).valueOrNull ?? true;
    final geocoder = ref.watch(geocoderProvider);
    final coords = GeocoderClient.parseCoordinates(text);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (v) {
            _debounce?.cancel();
            if (v.trim().length >= 2) _run(v.trim());
          },
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Effacer',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                    },
                  ),
          ),
        ),
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (!online)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: InfoBanner(
                icon: Icons.wifi_off_rounded,
                tone: BannerTone.warning,
                message: 'Hors connexion : seuls vos favoris, lieux récents et coordonnées GPS sont disponibles. La recherche d\'adresses hors connexion n\'est pas disponible.',
              ),
            ),
          if (!geocoder.configured)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: InfoBanner(
                icon: Icons.settings_suggest_outlined,
                tone: BannerTone.warning,
                message: 'Aucun service de recherche d\'adresses n\'est configuré (Réglages > Services). Les favoris, lieux récents et coordonnées GPS fonctionnent.',
              ),
            ),
          if (text.isEmpty) ..._idle(context) else ..._results(context, text, coords),
        ],
      ),
    );
  }

  List<Widget> _idle(BuildContext context) {
    final queries = ref.watch(searchQueriesProvider).valueOrNull ?? const <String>[];
    final recents = ref.watch(recentPlacesProvider).valueOrNull ?? const <Place>[];
    final historyOn = ref.watch(settingsProvider.select((s) => s.historyEnabled));
    final home = ref.watch(homeFavoriteProvider).valueOrNull;
    final work = ref.watch(workFavoriteProvider).valueOrNull;
    return [
      if (widget.showCategories) ...[
        const SectionTitle('Autour de moi'),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final c in PlaceCategory.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(avatar: Icon(categoryIcon(c), size: 18), label: Text(c.label), onPressed: _loading ? null : () => _category(c)),
                ),
            ],
          ),
        ),
        if (_loading) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        if (_error != null) Padding(padding: const EdgeInsets.all(16), child: InfoBanner(icon: Icons.error_outline_rounded, tone: BannerTone.error, message: toFailure(_error!).message)),
      ],
      if (home != null || work != null) ...[
        const SectionTitle('Raccourcis'),
        if (home != null) _tile(context, home.toPlace().copyWith(name: 'Domicile'), icon: Icons.home_rounded),
        if (work != null) _tile(context, work.toPlace().copyWith(name: 'Travail'), icon: Icons.work_rounded),
      ],
      if (historyOn && queries.isNotEmpty) ...[
        SectionTitle('Recherches récentes', trailing: TextButton(onPressed: () => ref.read(dataActionsProvider).clearSearchData(), child: const Text('Tout effacer'))),
        for (final q in queries)
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: Text(q),
            trailing: IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.close_rounded, size: 20), onPressed: () => ref.read(dataActionsProvider).removeQuery(q)),
            onTap: () {
              _controller.text = q;
              _controller.selection = TextSelection.collapsed(offset: q.length);
              _onChanged(q);
            },
          ),
      ],
      if (historyOn && recents.isNotEmpty) ...[
        const SectionTitle('Lieux récents'),
        for (final p in recents.take(6)) _tile(context, p.copyWith(source: 'history'), onDelete: () => ref.read(dataActionsProvider).removeRecent(p.id)),
      ],
      if (!historyOn)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('L\'historique est désactivé : vos recherches ne sont pas enregistrées (Réglages > Confidentialité).', textAlign: TextAlign.center),
        ),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _results(BuildContext context, String text, GeoPoint? coords) {
    final local = _localMatches(text);
    final cs = context.cs;
    return [
      if (coords != null) _tile(context, Place.fromCoordinates(coords), titleOverride: 'Aller aux coordonnées', icon: Icons.my_location_rounded),
      if (local.isNotEmpty) ...[
        const SectionTitle('Mes lieux'),
        for (final p in local) _tile(context, p),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            FilterChip(
              label: const Text('Dans la zone de la carte'),
              selected: _inViewport,
              onSelected: ref.watch(mapViewportProvider) == null
                  ? null
                  : (v) {
                      setState(() => _inViewport = v);
                      if (text.length >= 2) _run(text);
                    },
            ),
          ],
        ),
      ),
      if (_loading) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
      if (_error != null && !_loading)
        Padding(padding: const EdgeInsets.all(16), child: InfoBanner(icon: Icons.error_outline_rounded, tone: BannerTone.error, message: toFailure(_error!).message, action: 'Réessayer', onAction: () => _run(text))),
      if (!_loading && _error == null && _lastQuery == text && _remote.isEmpty && local.isEmpty && coords == null)
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Aucun résultat pour « $text ».\nEssayez avec une adresse plus complète ou une autre orthographe.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      if (_remote.isNotEmpty) ...[
        const SectionTitle('Résultats'),
        for (final p in _remote) _tile(context, p),
      ],
      const SizedBox(height: 24),
    ];
  }

  Widget _tile(BuildContext context, Place p, {IconData? icon, String? titleOverride, VoidCallback? onDelete}) {
    final here = _here;
    final units = ref.watch(settingsProvider.select((s) => s.units));
    return ListTile(
      leading: IconBadge(icon: icon ?? iconForPlace(p), color: p.source == 'favorite' ? context.sc.warning : null),
      title: Text(titleOverride ?? p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [if (p.subtitle != null) p.subtitle!, if (here != null) formatDistance(distanceM(here, p.point), units)].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onDelete == null ? null : IconButton(tooltip: 'Retirer', icon: const Icon(Icons.close_rounded, size: 20), onPressed: onDelete),
      onTap: () => _choose(p),
    );
  }
}
