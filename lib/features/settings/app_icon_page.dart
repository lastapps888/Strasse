import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/i18n/translator.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/settings/app_icons.dart';
import 'package:strasse/features/settings/settings_widgets.dart';

/// Choix de l'icône de l'application parmi les 13 images fournies.
class AppIconPage extends ConsumerStatefulWidget {
  const AppIconPage({super.key});

  @override
  ConsumerState<AppIconPage> createState() => _AppIconPageState();
}

class _AppIconPageState extends ConsumerState<AppIconPage> {
  final _service = AppIconService();
  bool _supported = true;
  String? _active;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ok = await _service.supported();
    final cur = ok ? await _service.current() : null;
    if (!mounted) return;
    setState(() {
      _supported = ok;
      _active = cur ?? ref.read(settingsProvider).appIcon;
    });
  }

  Future<void> _choose(AppIconChoice icon) async {
    if (_busy != null || icon.id == _active) return;
    setState(() => _busy = icon.id);
    try {
      await _service.set(icon.id);
      await ref.read(settingsProvider.notifier).update((s) => s.copyWith(appIcon: icon.id));
      if (!mounted) return;
      setState(() => _active = icon.id);
      showMessage(context, Platform.isAndroid ? 'Icône modifiée. Selon votre lanceur, elle peut mettre quelques secondes à s\'actualiser.' : 'Icône modifiée.');
    } catch (e) {
      if (mounted) showMessage(context, 'Impossible de changer l\'icône : ${e is Exception ? e.toString().replaceFirst('PlatformException', '') : e}');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return SettingsPageScaffold(
      title: 'Icône de l\'application',
      children: [
        if (!_supported)
          const Padding(
            padding: EdgeInsets.all(16),
            child: InfoBanner(icon: Icons.block_rounded, tone: BannerTone.warning, message: 'Le changement d\'icône n\'est pas disponible sur cet appareil.'),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.82,
            children: [
              for (final i in kAppIcons)
                Semantics(
                  button: true,
                  selected: _active == i.id,
                  label: tr(i.label),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _supported ? () => _choose(i) : null,
                    child: Column(
                      children: [
                        Expanded(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: _active == i.id ? cs.primary : Colors.transparent, width: 3),
                                ),
                                padding: const EdgeInsets.all(3),
                                child: Image.asset(i.asset, fit: BoxFit.contain),
                              ),
                              if (_busy == i.id) const CircularProgressIndicator(),
                              if (_active == i.id && _busy == null) Positioned(right: 4, bottom: 4, child: Icon(Icons.check_circle_rounded, color: cs.primary)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(i.label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelMedium),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
