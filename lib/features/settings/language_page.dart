import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/settings/settings_widgets.dart';

/// Choix de la langue de l'interface, de la voix de guidage et des noms de la carte.
class LanguagePage extends ConsumerWidget {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setting = ref.watch(settingsProvider.select((s) => s.language));
    final c = ref.read(settingsProvider.notifier);
    final device = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final current = AppLanguage.resolve(setting, device);

    return SettingsPageScaffold(
      title: 'Langue',
      children: [
        ListTile(
          leading: const Icon(Icons.phone_android_rounded),
          title: const Text('Langue de l\'appareil'),
          subtitle: Text('${AppLanguage.fromDevice(device).nativeName}${AppLanguage.values.any((l) => l.code == device) ? '' : ' (non disponible : français)'}'),
          trailing: setting.isEmpty ? const Icon(Icons.check_rounded) : null,
          onTap: () => c.update((x) => x.copyWith(language: '')),
        ),
        const Divider(height: 1),
        for (final l in AppLanguage.values)
          ListTile(
            // Le nom de chaque langue reste écrit dans cette langue pour pouvoir toujours la retrouver.
            title: Text(l.nativeName, textDirection: l.rtl ? TextDirection.rtl : TextDirection.ltr),
            trailing: setting.isNotEmpty && current == l ? const Icon(Icons.check_rounded) : null,
            onTap: () => c.update((x) => x.copyWith(language: l.code)),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            'La langue s\'applique à toute l\'interface, aux messages et aux annonces vocales. '
            'Les noms de lieux, d\'adresses et de lignes viennent des données de la carte : ils s\'affichent dans la langue des données lorsque celles-ci en proposent une. '
            'La voix utilise les voix installées sur l\'appareil ; les instructions de guidage du calcul d\'itinéraire n\'existent pas en arabe ni en chinois (elles sont alors en anglais).',
          ),
        ),
      ],
    );
  }
}
