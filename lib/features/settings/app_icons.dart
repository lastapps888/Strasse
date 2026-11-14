import 'dart:io';

import 'package:flutter/services.dart';

/// Une des 13 icônes de l'application (images fournies, utilisées sans retouche).
class AppIconChoice {
  const AppIconChoice(this.id, this.label);
  final String id;
  final String label;

  String get asset => 'assets/app_icons/$id.png';
}

const List<AppIconChoice> kAppIcons = [
  AppIconChoice('clair', 'Mode clair'),
  AppIconChoice('sombre', 'Mode sombre'),
  AppIconChoice('arc_en_ciel', 'Arc-en-ciel'),
  AppIconChoice('retro', 'Rétro'),
  AppIconChoice('rouge', 'Rouge'),
  AppIconChoice('vert', 'Vert'),
  AppIconChoice('bleu', 'Bleu'),
  AppIconChoice('violet', 'Violet'),
  AppIconChoice('crepuscule', 'Crépuscule'),
  AppIconChoice('aurore', 'Aurore'),
  AppIconChoice('minimaliste', 'Minimaliste'),
  AppIconChoice('mignon', 'Mignon'),
  AppIconChoice('inverse', 'Inversé'),
];

const String kDefaultAppIcon = 'clair';

/// Changement réel de l'icône sur l'écran d'accueil.
/// Android : un activity-alias par icône, un seul actif. iOS : setAlternateIconName avec un jeu d'icônes par variante.
class AppIconService {
  static const _channel = MethodChannel('fr.strasse.strasse/icons');

  static List<String> get _androidNames => [for (final i in kAppIcons) i.id];

  /// Nom iOS d'une icône ; l'icône principale (« clair ») n'a pas de nom alternatif.
  static String _iosName(String id) => id == kDefaultAppIcon ? 'default' : 'AppIcon-$id';

  Future<bool> supported() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('supported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Icône actuellement active d'après le système (et non d'après nos réglages).
  Future<String?> current() async {
    try {
      final r = await _channel.invokeMethod<String>('current', {'names': _androidNames});
      if (Platform.isIOS) {
        if (r == null || r == 'default') return kDefaultAppIcon;
        return r.startsWith('AppIcon-') ? r.substring(8) : kDefaultAppIcon;
      }
      return r;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Applique l'icône. Lève une [PlatformException] avec un message lisible en cas d'échec.
  Future<void> set(String id) async {
    await _channel.invokeMethod<bool>('set', {'name': Platform.isIOS ? _iosName(id) : id, 'names': _androidNames});
  }
}
