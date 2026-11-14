import 'package:flutter/material.dart';
import 'package:strasse/core/i18n/translator.dart';

/// Logo de l'application : l'icône « Mode clair » fournie (ou « Mode sombre » avec [dark]), affichée sans retouche.
class StrasseLogo extends StatelessWidget {
  const StrasseLogo({super.key, this.size = 96, this.dark = false});

  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) => Semantics(
        label: tr('Logo Strasse'),
        image: true,
        child: SizedBox(
          width: size,
          height: size,
          child: Image.asset(dark ? 'assets/app_icons/sombre.png' : 'assets/app_icons/clair.png', fit: BoxFit.contain, filterQuality: FilterQuality.high),
        ),
      );
}
