import 'dart:ui' as ui;

import 'package:flutter/material.dart' as m;
import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/translator.dart';

/// Remplace le widget `Text` de Flutter dans toute l'application : le texte est traduit au moment de l'affichage
/// (voir [Translator]). Les fichiers importent `package:flutter/material.dart' hide Text` et ce fichier.
///
/// Le widget dépend de la langue de l'application (`Localizations`) : changer de langue le reconstruit,
/// même s'il est déclaré `const`.
class Text extends StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null;

  const Text.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null;

  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final ui.TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  static InlineSpan _translateSpan(InlineSpan s) {
    if (s is TextSpan) {
      return TextSpan(
        text: s.text == null ? null : tr(s.text!),
        children: s.children?.map(_translateSpan).toList(),
        style: s.style,
        recognizer: s.recognizer,
        semanticsLabel: s.semanticsLabel == null ? null : tr(s.semanticsLabel!),
      );
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    // Crée la dépendance à la langue : le texte est reconstruit quand elle change.
    Localizations.localeOf(context);
    if (textSpan != null) {
      return m.Text.rich(
        _translateSpan(textSpan!),
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel == null ? null : tr(semanticsLabel!),
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }
    return m.Text(
      tr(data ?? ''),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel == null ? null : tr(semanticsLabel!),
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
