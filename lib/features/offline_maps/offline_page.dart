import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/app/widgets/nav_helpers.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/map/strasse_map.dart';
import 'package:strasse/features/offline_maps/offline_manager.dart';
import 'package:strasse/features/offline_routing/routing_graph_store.dart';

/// Cartes hors connexion : régions téléchargées, progression, vérification, mise à jour, suppression, espace utilisé.
class OfflinePage extends ConsumerStatefulWidget {
  const OfflinePage({super.key});

  @override
  ConsumerState<OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends ConsumerState<OfflinePage> {
  int? _free;
  int? _used;

  @override
  void initState() {
    super.initState();
    _refreshSpace();
  }

  Future<void> _refreshSpace() async {
    final m = ref.read(offlineManagerProvider.notifier);
    final free = await m.freeBytes();
    final used = await m.storageUsedBytes();
    if (mounted) setState(() {
      _free = free;
      _used = used;
    });
  }

  @override
  Widget build(BuildContext context) {
    final regions = ref.watch(offlineManagerProvider);
    final manager = ref.read(offlineManagerProvider.notifier);
    final units = ref.watch(settingsProvider.select((s) => s.units));
    final hasTiles = ref.watch(providerResolverProvider.select((r) => r.mapSource().available));

    return Scaffold(
      appBar: AppBar(title: const Text('Cartes hors connexion')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await pushPage(context, const RegionPickerPage());
          _refreshSpace();
        },
        icon: const Icon(Icons.download_rounded),
        label: const Text('Télécharger une zone'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          if (!hasTiles)
            const Padding(padding: EdgeInsets.only(bottom: 12), child: InfoBanner(icon: Icons.settings_suggest_outlined, tone: BannerTone.warning, message: 'Aucun serveur de cartes n\'est configuré : le téléchargement est impossible (Réglages > Services).')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Stockage', style: context.tt.titleSmall),
                  const SizedBox(height: 8),
                  Text('Cartes téléchargées : ${_used == null ? 'non mesurable' : formatBytes(_used!)}'),
                  Text('Espace libre sur l\'appareil : ${_free == null ? 'inconnu' : formatBytes(_free!)}'),
                  const SizedBox(height: 8),
                  Text(
                    'Hors connexion, la carte s\'affiche dans les zones téléchargées. Les itinéraires déjà calculés restent guidés sans réseau. '
                    'Pour calculer de nouveaux itinéraires (voiture, vélo, marche) sans réseau, téléchargez aussi les itinéraires de la zone (maximum environ 35 km de côté) : '
                    'le calcul est alors fait sur l\'appareil, sans trafic ni restrictions de virage, et les transports en commun ne sont pas disponibles.',
                    style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (regions.isEmpty)
            const EmptyViewInline2(icon: Icons.cloud_download_outlined, text: 'Aucune zone téléchargée.')
          else
            for (final r in regions) _regionCard(context, r, manager, units),
        ],
      ),
    );
  }

  Widget _regionCard(BuildContext context, OfflineRegionInfo r, OfflineManager manager, Units units) {
    final cs = context.cs;
    final running = r.status == OfflineStatus.downloading;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(icon: r.isComplete ? Icons.download_done_rounded : (running ? Icons.downloading_rounded : Icons.error_outline_rounded), color: r.status == OfflineStatus.failed ? cs.error : null),
                  const SizedBox(width: 12),
                  Expanded(child: Text(r.name, style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Zoom ${r.minZoom}–${r.maxZoom} · ${r.isComplete ? 'environ ${formatBytes(r.sizeBytes)}' : 'estimé à ${formatBytes(r.sizeBytes)}'} · ${formatDate(r.updatedAt)}', style: context.tt.bodySmall),
              if (running) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: r.progress > 0 ? (r.progress / 100).clamp(0.0, 1.0) : null),
                const SizedBox(height: 4),
                Text('${r.progress.toStringAsFixed(0)} %', style: context.tt.bodySmall),
              ],
              if (r.status == OfflineStatus.failed && r.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(r.error!, style: TextStyle(color: cs.error, fontSize: 13))),
              if (r.isComplete) _routingRow(context, r),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (running)
                    OutlinedButton.icon(onPressed: () => manager.cancel(r.id), icon: const Icon(Icons.close_rounded), label: const Text('Annuler')),
                  if (r.isComplete) ...[
                    OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await manager.verify(r.id);
                        if (context.mounted) showMessage(context, ok ? 'Région vérifiée : les données sont présentes.' : 'Les données de cette région sont absentes. Retéléchargez-la.');
                      },
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Vérifier'),
                    ),
                    OutlinedButton.icon(onPressed: () => _update(r, manager), icon: const Icon(Icons.update_rounded), label: const Text('Mettre à jour')),
                  ],
                  if (r.status == OfflineStatus.failed) OutlinedButton.icon(onPressed: () => _update(r, manager), icon: const Icon(Icons.refresh_rounded), label: const Text('Relancer')),
                  if (!running)
                    TextButton.icon(
                      onPressed: () async {
                        final ok = await confirm(context, title: 'Supprimer « ${r.name} » ?', message: 'La carte de cette zone ne sera plus disponible hors connexion.');
                        if (ok) {
                          await ref.read(routingGraphStoreProvider.notifier).delete(r.id);
                          await manager.delete(r.id);
                          _refreshSpace();
                        }
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Supprimer'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _routingRow(BuildContext context, OfflineRegionInfo r) {
    final zones = ref.watch(routingGraphStoreProvider);
    final store = ref.read(routingGraphStoreProvider.notifier);
    RoutingZone? z;
    for (final e in zones) {
      if (e.id == r.id) z = e;
    }
    final cs = context.cs;
    final tooBig = RoutingGraphStore.checkBounds(r.bounds) != null;
    final String text;
    if (z == null) {
      text = tooBig ? 'Itinéraires hors connexion : zone trop grande (maximum environ 35 km de côté).' : 'Itinéraires hors connexion : non téléchargés.';
    } else if (z.status == RoutingZoneStatus.downloading) {
      text = 'Itinéraires hors connexion : téléchargement en cours…';
    } else if (z.status == RoutingZoneStatus.ready) {
      text = 'Itinéraires hors connexion : prêts (${formatBytes(z.sizeBytes)}).';
    } else {
      text = 'Itinéraires hors connexion : ${z.error ?? 'échec'}';
    }
    final busy = z?.status == RoutingZoneStatus.downloading;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(Icons.alt_route_rounded, size: 18, color: z?.status == RoutingZoneStatus.failed ? cs.error : cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: context.tt.bodySmall)),
          if (busy)
            TextButton(onPressed: () => store.cancel(r.id), child: const Text('Annuler'))
          else if (z?.status == RoutingZoneStatus.ready)
            TextButton(
              onPressed: () async {
                final ok = await confirm(context, title: 'Supprimer les itinéraires de cette zone ?', message: 'La carte reste disponible, mais les itinéraires ne seront plus calculables sans réseau.');
                if (ok) {
                  await store.delete(r.id);
                  _refreshSpace();
                }
              },
              child: const Text('Retirer'),
            )
          else if (!tooBig)
            TextButton(
              onPressed: () async {
                final online = ref.read(onlineProvider).valueOrNull ?? true;
                if (!online) {
                  showMessage(context, 'Une connexion est nécessaire pour télécharger les itinéraires.');
                  return;
                }
                try {
                  await store.download(id: r.id, name: r.name, bounds: r.bounds);
                  if (mounted) showMessage(context, 'Itinéraires hors connexion prêts.');
                } catch (e) {
                  if (mounted) showMessage(context, toFailure(e).message);
                }
              },
              child: Text(z == null ? 'Télécharger' : 'Relancer'),
            ),
        ],
      ),
    );
  }

  Future<void> _update(OfflineRegionInfo r, OfflineManager manager) async {
    try {
      await manager.update(r.id);
      if (mounted) showMessage(context, 'Mise à jour lancée.');
    } catch (e) {
      if (mounted) showMessage(context, toFailure(e).message);
    }
  }
}

class EmptyViewInline2 extends StatelessWidget {
  const EmptyViewInline2({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [Icon(icon, size: 48, color: context.cs.outline), const SizedBox(height: 10), Text(text)]),
      );
}

/// Sélection d'une zone : un rectangle redimensionnable librement (poignées aux coins et aux côtés) posé sur la carte.
/// On déplace et on zoome la carte pour choisir le lieu ; on tire les poignées pour obtenir la forme voulue
/// (200 × 200 km comme 100 × 400 km).
class RegionPickerPage extends ConsumerStatefulWidget {
  const RegionPickerPage({super.key});

  @override
  ConsumerState<RegionPickerPage> createState() => _RegionPickerPageState();
}

class _RegionPickerPageState extends ConsumerState<RegionPickerPage> {
  static const _autoZoom = -1;
  static const _minZoom = 6;

  StrasseMapController? _map;
  GeoBounds? _view;
  GeoBounds? _bounds;
  Rect? _rect;
  Size _size = Size.zero;
  int _level = _autoZoom;
  int? _free;
  bool _busy = false;
  final _name = TextEditingController();

  static const _levels = <int, String>{_autoZoom: 'Automatique', 12: 'Aperçu (zoom 12)', 14: 'Détaillé (zoom 14)', 16: 'Très détaillé (zoom 16)'};

  @override
  void initState() {
    super.initState();
    ref.read(offlineManagerProvider.notifier).freeBytes().then((v) {
      if (mounted) setState(() => _free = v);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Zoom effectivement téléchargé : en automatique, le plus détaillé qui reste sous le plafond de tuiles.
  /// Les tuiles vectorielles standard s'arrêtent au zoom 14 : au-delà, la carte réutilise leurs données.
  int _effectiveZoom(GeoBounds b) {
    if (_level != _autoZoom) return _level;
    return maxZoomWithinLimit(b, _minZoom, ceiling: 14) ?? _minZoom;
  }

  void _recompute() {
    final v = _view, r = _rect;
    if (v == null || r == null || _size.isEmpty) return;
    final b = subBounds(v, left: r.left / _size.width, top: r.top / _size.height, right: r.right / _size.width, bottom: r.bottom / _size.height);
    setState(() => _bounds = b);
  }

  Future<void> _onCameraIdle() async {
    final v = await _map?.visibleBounds();
    if (v == null || !mounted) return;
    _view = v;
    _recompute();
  }

  Future<void> _download() async {
    final b = _bounds;
    if (b == null) return;
    final zoom = _effectiveZoom(b);
    final problem = regionLimitMessage(b, _minZoom, zoom);
    if (problem != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: const Text('Zone trop grande'),
          content: Text('$problem\n\nLe téléchargement n\'a pas été lancé.'),
          actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Réduire la zone'))],
        ),
      );
      return;
    }
    final online = ref.read(onlineProvider).valueOrNull ?? true;
    if (!online) {
      showMessage(context, 'Une connexion est nécessaire pour télécharger une zone.');
      return;
    }
    var name = _name.text.trim();
    if (name.isEmpty) {
      final place = await ref.read(geocoderProvider).reverse(b.center);
      name = place?.title ?? 'Zone ${formatDate(DateTime.now())}';
    }
    setState(() => _busy = true);
    try {
      await ref.read(offlineManagerProvider.notifier).download(name: name, bounds: b, minZoom: _minZoom, maxZoom: zoom);
      if (mounted) {
        showMessage(context, 'Téléchargement lancé. Vous pouvez quitter cet écran.');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        final f = toFailure(e);
        if (f.code == 'region_too_big') {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.warning_amber_rounded),
              title: const Text('Zone trop grande'),
              content: Text(f.message),
              actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Réduire la zone'))],
            ),
          );
        } else {
          showMessage(context, f.message);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _bounds;
    final zoom = b == null ? 0 : _effectiveZoom(b);
    final tiles = b == null ? 0 : estimateTileCount(b, _minZoom, zoom);
    final bytes = b == null ? 0 : estimateRegionBytes(b, _minZoom, zoom);
    final problem = b == null ? null : regionLimitMessage(b, _minZoom, zoom);
    final notEnough = _free != null && bytes * 1.2 > _free!;
    final padding = MediaQuery.paddingOf(context);
    final dims = b == null ? '' : '${boundsWidthKm(b).round()} × ${boundsHeightKm(b).round()} km';

    return Scaffold(
      appBar: AppBar(title: const Text('Choisir la zone')),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final size = Size(box.maxWidth, box.maxHeight);
                if (size != _size || _rect == null) {
                  final old = _rect, oldSize = _size;
                  _size = size;
                  _rect = (old == null || oldSize.isEmpty)
                      ? Rect.fromLTRB(size.width * 0.12, size.height * 0.12, size.width * 0.88, size.height * 0.88)
                      : Rect.fromLTRB(old.left / oldSize.width * size.width, old.top / oldSize.height * size.height, old.right / oldSize.width * size.width, old.bottom / oldSize.height * size.height);
                }
                return Stack(
                  children: [
                    Positioned.fill(
                      child: StrasseMap(
                        lockNorth: true,
                        onReady: (c) {
                          _map = c;
                          _onCameraIdle();
                        },
                        onCameraIdle: _onCameraIdle,
                      ),
                    ),
                    Positioned.fill(
                      child: _FrameOverlay(
                        rect: _rect!,
                        bounds: Offset.zero & size,
                        invalid: problem != null,
                        label: dims,
                        onChanged: (r) => setState(() => _rect = r),
                        onEnd: _recompute,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.58),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Material(
                color: context.sc.panel,
            elevation: 12,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + padding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Déplacez et zoomez la carte, puis tirez les poignées du cadre pour l\'étirer dans la forme voulue.', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 6),
                  const InfoBanner(
                    icon: Icons.info_outline_rounded,
                    tone: BannerTone.info,
                    compact: true,
                    message: 'Avec OpenFreeMap, chaque téléchargement est limité à 3 000 tuiles et 50 Mo. Strasse ajuste automatiquement le zoom ; pour couvrir une plus grande zone, créez plusieurs zones distinctes.',
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: _level,
                    isDense: true,
                    decoration: InputDecoration(labelText: tr('Niveau de détail'), border: const OutlineInputBorder()),
                    items: [for (final e in _levels.entries) DropdownMenuItem<int>(value: e.key, child: Text(e.value))],
                    onChanged: (v) => setState(() => _level = v ?? _autoZoom),
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: _name, maxLength: 50, decoration: InputDecoration(hintText: tr('Nom (facultatif)'), counterText: tr(''))),
                  const SizedBox(height: 8),
                  Text(
                    b == null ? 'Calcul de la zone…' : '$dims · zoom $zoom · $tiles tuiles · environ ${formatBytes(bytes)} (estimation) · espace libre ${_free == null ? 'inconnu' : formatBytes(_free!)}',
                    style: TextStyle(fontSize: 13, color: (problem != null || notEnough) ? context.cs.error : null, fontWeight: FontWeight.w600),
                  ),
                  if (problem != null) Text(problem, style: TextStyle(fontSize: 12, color: context.cs.error)),
                  if (notEnough && problem == null) const Text('Espace insuffisant sur l\'appareil.', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: (_busy || b == null || notEnough) ? null : _download,
                      icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded),
                      label: const Text('Télécharger'),
                    ),
                  ),
                ],
              ),
            ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

/// Cadre rectangulaire à huit poignées (coins et milieux des côtés). Le fond hors cadre est assombri ; l'intérieur
/// laisse passer les gestes vers la carte.
class _FrameOverlay extends StatelessWidget {
  const _FrameOverlay({required this.rect, required this.bounds, required this.invalid, required this.label, required this.onChanged, required this.onEnd});

  final Rect rect;
  final Rect bounds;
  final bool invalid;
  final String label;
  final ValueChanged<Rect> onChanged;
  final VoidCallback onEnd;

  static const double _minSide = 90;

  Rect _resize(Rect r, {double dl = 0, double dt = 0, double dr = 0, double db = 0}) {
    final l = (r.left + dl).clamp(bounds.left, r.right - _minSide).toDouble();
    final t = (r.top + dt).clamp(bounds.top, r.bottom - _minSide).toDouble();
    final rr = (r.right + dr).clamp(r.left + _minSide, bounds.right).toDouble();
    final b = (r.bottom + db).clamp(r.top + _minSide, bounds.bottom).toDouble();
    return Rect.fromLTRB(l, t, rr, b);
  }

  Widget _handle(BuildContext context, Offset at, void Function(Offset d) apply) {
    final color = invalid ? context.cs.error : context.cs.primary;
    return Positioned(
      left: at.dx - 24,
      top: at.dy - 24,
      width: 48,
      height: 48,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => apply(d.delta),
        onPanEnd: (_) => onEnd(),
        onPanCancel: onEnd,
        child: Center(child: Container(width: 18, height: 18, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = invalid ? context.cs.error : context.cs.primary;
    final r = rect;
    void set({double dl = 0, double dt = 0, double dr = 0, double db = 0}) => onChanged(_resize(r, dl: dl, dt: dt, dr: dr, db: db));
    return Stack(
      children: [
        IgnorePointer(child: CustomPaint(size: Size.infinite, painter: _FramePainter(rect: r, color: color))),
        Positioned(
          left: r.left,
          top: r.top + 8,
          width: r.width,
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                child: Text(label.isEmpty ? '…' : label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ),
          ),
        ),
        _handle(context, r.topLeft, (d) => set(dl: d.dx, dt: d.dy)),
        _handle(context, r.topRight, (d) => set(dr: d.dx, dt: d.dy)),
        _handle(context, r.bottomLeft, (d) => set(dl: d.dx, db: d.dy)),
        _handle(context, r.bottomRight, (d) => set(dr: d.dx, db: d.dy)),
        _handle(context, r.topCenter, (d) => set(dt: d.dy)),
        _handle(context, r.bottomCenter, (d) => set(db: d.dy)),
        _handle(context, r.centerLeft, (d) => set(dl: d.dx)),
        _handle(context, r.centerRight, (d) => set(dr: d.dx)),
      ],
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({required this.rect, required this.color});
  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = const Color(0x66000000));
    canvas.drawRect(rect, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.rect != rect || old.color != color;
}
