import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/i18n/translator.dart';
import 'package:strasse/features/music/local_music_backend.dart';
import 'package:strasse/features/music/deezer_backend.dart';
import 'package:strasse/features/music/music_controller.dart';
import 'package:strasse/features/music/music_models.dart';
import 'package:strasse/features/music/music_widgets.dart';

/// Onglet Musique : choix de la source, lecteur, recherche et bibliothèque. Seules les commandes
/// réellement supportées par la source active sont affichées.
class MusicScreen extends ConsumerStatefulWidget {
  const MusicScreen({super.key});

  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen> {
  late final MusicController _ctrl = ref.read(musicProvider.notifier);
  final _query = TextEditingController();
  Timer? _debounce;

  MusicResults? _results;
  CollectionKind? _kind;
  List<MusicCollection> _collections = const [];
  List<MusicTrack> _tracks = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ctrl.watch();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl.init());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.unwatch();
    _query.dispose();
    super.dispose();
  }

  Future<void> _selectSource(MusicSource s) async {
    setState(() {
      _results = null;
      _kind = null;
      _collections = const [];
      _tracks = const [];
      _query.clear();
    });
    await _ctrl.select(s);
    final state = ref.read(musicProvider);
    if (state.connected || state.catalogAvailable) await _openKind(_defaultKind());
  }

  CollectionKind? _defaultKind() {
    final caps = _ctrl.backend?.capabilities;
    if (caps == null || caps.browse.isEmpty) return null;
    for (final k in const [CollectionKind.playlist, CollectionKind.album, CollectionKind.artist, CollectionKind.track]) {
      if (caps.browse.contains(k)) return k;
    }
    return null;
  }

  Future<void> _openKind(CollectionKind? k) async {
    if (k == null) return;
    setState(() {
      _kind = k;
      _loading = true;
      _results = null;
    });
    final b = _ctrl.backend;
    if (k == CollectionKind.track) {
      final List<MusicTrack> t;
      if (b is LocalMusicBackend) {
        t = await b.allTracks();
      } else if (b is DeezerBackend) {
        t = await b.chartTracks();
      } else {
        t = await _chartTracks();
      }
      if (mounted) setState(() {
        _tracks = t;
        _collections = const [];
        _loading = false;
      });
      return;
    }
    final c = await _ctrl.library(k);
    if (mounted) setState(() {
      _collections = c;
      _tracks = const [];
      _loading = false;
    });
  }

  Future<List<MusicTrack>> _chartTracks() async {
    final r = await _ctrl.search('a');
    return r.tracks;
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _loading = true);
      final r = await _ctrl.search(q);
      if (mounted) setState(() {
        _results = r;
        _loading = false;
      });
    });
  }

  Future<void> _openCollection(MusicCollection c) async {
    final tracks = await _ctrl.tracksOf(c);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          children: [
            ListTile(
              leading: Artwork(url: c.artUrl, size: 56),
              title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(c.subtitle),
              trailing: FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Lire'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _ctrl.playCollection(c);
                },
              ),
            ),
            if (tracks.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Aucun titre à afficher pour cette sélection ; « Lire » lance tout de même la sélection si la source le permet.')),
            for (final t in tracks) _trackTile(t, tracks, onTap: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
  }

  Widget _trackTile(MusicTrack t, List<MusicTrack> queue, {VoidCallback? onTap}) => ListTile(
        leading: Artwork(url: t.artUrl, size: 44, radius: 8),
        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text([t.artist, if (t.previewOnly) 'extrait 30 s'].where((e) => e.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: t.durationMs > 0 ? Text(formatMs(t.durationMs), style: context.tt.labelSmall) : null,
        onTap: () {
          onTap?.call();
          _ctrl.playTrack(t, queue: queue);
        },
      );

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(musicProvider);
    final padding = MediaQuery.paddingOf(context);
    final backend = _ctrl.backend;
    final caps = backend?.capabilities;
    return Scaffold(
      appBar: AppBar(title: const Text('Musique'), actions: [
        if (st.connected && st.source != null)
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'out') _ctrl.disconnect();
              if (v == 'files') _ctrl.pickLocalFiles().then((n) {
                if (n > 0) _openKind(CollectionKind.track);
              });
            },
            itemBuilder: (_) => [
              if (st.source == MusicSource.local) const PopupMenuItem(value: 'files', child: Text('Ajouter des fichiers…')),
              PopupMenuItem(value: 'out', child: Text(st.source == MusicSource.deezer ? 'Arrêter les extraits' : 'Se déconnecter de la source')),
            ],
          ),
      ]),
      body: ListView(
        padding: EdgeInsets.only(bottom: 120 + padding.bottom),
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final s in MusicSource.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Tooltip(
                      message: tr(st.availability[s] ?? s.label),
                      child: ChoiceChip(
                        avatar: Icon(s.icon, size: 18),
                        label: Text(s.label),
                        selected: st.source == s,
                        onSelected: st.availability[s] == null || st.availability.isEmpty ? (_) => _selectSource(s) : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (st.source == null)
            const Padding(padding: EdgeInsets.all(16), child: InfoBanner(icon: Icons.library_music_outlined, message: 'Choisissez une source de musique. Spotify et Apple Music se commandent depuis Strasse ; Deezer (extraits) et la musique de l\'appareil sont lues par Strasse.')),
          if (st.unavailable != null) Padding(padding: const EdgeInsets.all(16), child: InfoBanner(icon: Icons.block_rounded, tone: BannerTone.warning, message: st.unavailable!)),
          if (st.catalogAvailable)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: InfoBanner(
                icon: Icons.info_outline_rounded,
                message: 'Catalogue public Deezer : recherche, classements et extraits de 30 secondes sans compte. Strasse ne prétend pas être connectée à votre compte Deezer et ne donne pas accès à votre bibliothèque personnelle ni à la lecture complète.',
              ),
            ),
          if (st.error != null) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: InfoBanner(icon: Icons.error_outline_rounded, tone: BannerTone.error, message: st.error!, action: st.needsLogin ? 'Se connecter' : null, onAction: st.needsLogin ? _ctrl.connect : null)),
          if (st.source != null && st.unavailable == null && !st.connected && !st.catalogAvailable) _connectCard(context, st),
          if (st.connected) _nowPlaying(context, st, caps!),
          if (st.connected || st.catalogAvailable) ...[
            if (caps.search)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SearchBar(controller: _query, hintText: tr('Rechercher un titre, un artiste, un album'), leading: const Icon(Icons.search_rounded), onChanged: _onQuery, elevation: const WidgetStatePropertyAll(0)),
              ),
            if (_results == null && caps.browse.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  children: [for (final k in caps.browse) ChoiceChip(label: Text(k == CollectionKind.track && st.source == MusicSource.deezer ? 'Titres populaires' : k.label), selected: _kind == k, onSelected: (_) => _openKind(k))],
                ),
              ),
            if (_loading || st.busy) const Padding(padding: EdgeInsets.all(24), child: LoadingView()),
            if (!_loading) ..._list(context),
          ],
        ],
      ),
    );
  }

  List<Widget> _list(BuildContext context) {
    final r = _results;
    if (r != null) {
      if (r.isEmpty) return [const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucun résultat.')))];
      return [
        for (final c in r.collections) _collectionTile(c),
        for (final t in r.tracks) _trackTile(t, r.tracks),
      ];
    }
    if (_kind == CollectionKind.track) {
      if (_tracks.isEmpty) return [_emptyLibrary()];
      return [for (final t in _tracks) _trackTile(t, _tracks)];
    }
    if (_collections.isEmpty && _kind != null) return [_emptyLibrary()];
    return [for (final c in _collections) _collectionTile(c)];
  }

  Widget _emptyLibrary() => const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Rien à afficher ici pour le moment.', textAlign: TextAlign.center)));

  Widget _collectionTile(MusicCollection c) => ListTile(
        leading: Artwork(url: c.artUrl, size: 48),
        title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text([c.kind.label.replaceAll('s', ''), if (c.subtitle.isNotEmpty) c.subtitle].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(tooltip: tr('Lire'), icon: const Icon(Icons.play_circle_outline_rounded), onPressed: () => _ctrl.playCollection(c)),
        onTap: () => _openCollection(c),
      );

  Widget _connectCard(BuildContext context, MusicState st) {
    final s = st.source!;
    final (text, button) = switch (s) {
      MusicSource.spotify => ('Connectez votre compte Spotify. Strasse commande l\'application Spotify installée sur cet appareil (compte Premium requis) : l\'audio n\'est pas lu par Strasse.', 'Se connecter à Spotify'),
      MusicSource.appleMusic => ('Autorisez l\'accès à Apple Music. Un abonnement actif est nécessaire pour la lecture ; iOS 15 ou plus récent.', 'Autoriser Apple Music'),
      MusicSource.deezer => ('Deezer propose ici la recherche et des extraits de 30 secondes, sans compte.', 'Utiliser Deezer'),
      MusicSource.local => ('Lisez les musiques de votre appareil. Rien n\'est envoyé sur Internet.', 'Autoriser l\'accès à la musique'),
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Icon(s.icon), const SizedBox(width: 10), Text(s.label, style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800))]),
              const SizedBox(height: 10),
              Text(text),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton(onPressed: st.busy ? null : () async {
                  await _ctrl.connect();
                  if (ref.read(musicProvider).connected) await _openKind(_defaultKind());
                }, child: Text(button)),
                if (s == MusicSource.local)
                  OutlinedButton(onPressed: () async {
                    if (await _ctrl.pickLocalFiles() > 0) await _openKind(CollectionKind.track);
                  }, child: const Text('Choisir des fichiers')),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nowPlaying(BuildContext context, MusicState st, MusicCapabilities caps) {
    final snap = st.snapshot;
    final t = snap.track;
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
          child: Column(
            children: [
              Row(
                children: [
                  Artwork(url: t?.artUrl, size: 84, radius: 14),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t?.title ?? 'Aucun titre en cours', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        if (t != null && t.artist.isNotEmpty) Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
                        if (snap.deviceName != null) Text('Sur ${snap.deviceName}', style: context.tt.labelSmall?.copyWith(color: cs.primary)),
                        if (t?.previewOnly ?? false) Text('Extrait de 30 secondes', style: context.tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const MusicProgress(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (caps.shuffle) IconButton(tooltip: tr('Aléatoire'), icon: Icon(Icons.shuffle_rounded, color: snap.shuffle ? cs.primary : cs.onSurfaceVariant), onPressed: _ctrl.toggleShuffle),
                  if (caps.skip) IconButton(iconSize: 34, tooltip: tr('Précédent'), icon: const Icon(Icons.skip_previous_rounded), onPressed: _ctrl.previous),
                  IconButton.filled(iconSize: 36, tooltip: trn(snap.playing ? 'Pause' : 'Lecture'), icon: Icon(snap.playing ? Icons.pause_rounded : Icons.play_arrow_rounded), onPressed: _ctrl.togglePlay),
                  if (caps.skip) IconButton(iconSize: 34, tooltip: tr('Suivant'), icon: const Icon(Icons.skip_next_rounded), onPressed: _ctrl.next),
                  if (caps.repeat)
                    IconButton(
                      tooltip: tr('Répéter'),
                      icon: Icon(snap.repeat == PlayerRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded, color: snap.repeat == PlayerRepeatMode.off ? cs.onSurfaceVariant : cs.primary),
                      onPressed: _ctrl.cycleRepeat,
                    ),
                ],
              ),
              if (caps.volume && snap.volume != null)
                Row(children: [
                  const Icon(Icons.volume_down_rounded, size: 20),
                  Expanded(child: Slider(value: snap.volume!.clamp(0.0, 1.0), onChanged: (v) => _ctrl.setVolume(v))),
                  const Icon(Icons.volume_up_rounded, size: 20),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}
