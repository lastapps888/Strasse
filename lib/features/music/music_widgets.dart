import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/core/i18n/translator.dart';
import 'package:strasse/features/music/music_controller.dart';
import 'package:strasse/features/music/music_models.dart';

/// Pochette (image réseau avec repli sur une icône).
class Artwork extends StatelessWidget {
  const Artwork({super.key, required this.url, this.size = 52, this.radius = 10});
  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final fallback = Container(width: size, height: size, color: cs.surfaceContainerHighest, child: Icon(Icons.music_note_rounded, color: cs.onSurfaceVariant, size: size * 0.5));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null
          ? fallback
          : Image.network(url!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback, loadingBuilder: (_, child, p) => p == null ? child : fallback),
    );
  }
}

/// Barre de progression : suit la position estimée, et envoie un `seek` à la fin du glissement.
class MusicProgress extends ConsumerStatefulWidget {
  const MusicProgress({super.key, this.compact = false});
  final bool compact;

  @override
  ConsumerState<MusicProgress> createState() => _MusicProgressState();
}

class _MusicProgressState extends ConsumerState<MusicProgress> {
  Timer? _tick;
  double? _drag;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _drag == null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(musicProvider);
    final snap = st.snapshot;
    final dur = snap.durationMs;
    final pos = _drag?.round() ?? st.positionNow(DateTime.now());
    final canSeek = ref.read(musicProvider.notifier).backend?.capabilities.seek ?? false;
    final value = dur <= 0 ? 0.0 : (pos / dur).clamp(0.0, 1.0);
    if (widget.compact) {
      return LinearProgressIndicator(value: dur <= 0 ? null : value, minHeight: 3);
    }
    return Column(
      children: [
        Slider(
          value: dur <= 0 ? 0 : (_drag ?? pos.toDouble()).clamp(0, dur.toDouble()),
          max: dur <= 0 ? 1 : dur.toDouble(),
          onChanged: canSeek && dur > 0 ? (v) => setState(() => _drag = v) : null,
          onChangeEnd: canSeek
              ? (v) {
                  setState(() => _drag = null);
                  ref.read(musicProvider.notifier).seek(v.round());
                }
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(formatMs(pos), style: context.tt.labelSmall), Text(dur > 0 ? formatMs(dur) : '', style: context.tt.labelSmall)]),
        ),
      ],
    );
  }
}

/// Mini-lecteur : titre en cours, lecture/pause et suivant. Affiché pendant le guidage ; invisible sans titre en cours.
/// [dark] force des couleurs claires sur fond sombre (écran de guidage).
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key, this.dark = false});
  final bool dark;

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  late final MusicController _ctrl = ref.read(musicProvider.notifier);

  @override
  void initState() {
    super.initState();
    _ctrl.watch();
    // Reprend la source mémorisée si l'écran Musique n'a jamais été ouvert.
    if (ref.read(musicProvider).source == null) _ctrl.init();
  }

  @override
  void dispose() {
    _ctrl.unwatch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(musicProvider);
    final t = st.snapshot.track;
    if (!st.connected || t == null) return const SizedBox.shrink();
    final fg = widget.dark ? Colors.white : context.cs.onSurface;
    final caps = _ctrl.backend?.capabilities;
    return Material(
      color: widget.dark ? const Color(0xFF1C2125) : context.sc.panel,
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
            child: Row(
              children: [
                Artwork(url: t.artUrl, size: 40, radius: 8),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14)),
                      if (t.artist.isNotEmpty) Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg.withOpacity(0.7), fontSize: 12)),
                    ],
                  ),
                ),
                if (caps?.skip ?? true) IconButton(tooltip: tr('Précédent'), icon: Icon(Icons.skip_previous_rounded, color: fg), onPressed: _ctrl.previous),
                IconButton(tooltip: trn(st.snapshot.playing ? 'Pause' : 'Lecture'), icon: Icon(st.snapshot.playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: fg, size: 34), onPressed: _ctrl.togglePlay),
                if (caps?.skip ?? true) IconButton(tooltip: tr('Suivant'), icon: Icon(Icons.skip_next_rounded, color: fg), onPressed: _ctrl.next),
              ],
            ),
          ),
          const MusicProgress(compact: true),
        ],
      ),
    );
  }
}
