import 'package:flutter/material.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/features/settings/settings_model.dart';

/// Ligne de réglage avec une pastille de couleur ; ouvre une feuille de choix (palette + code hexadécimal).
class ColorTile extends StatelessWidget {
  const ColorTile({super.key, required this.title, required this.value, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Container(width: 30, height: 30, decoration: BoxDecoration(color: Color(value), shape: BoxShape.circle, border: Border.all(color: context.cs.outline))),
        onTap: () async {
          final c = await showModalBottomSheet<int>(context: context, isScrollControlled: true, builder: (_) => _ColorSheet(initial: value, title: title));
          if (c != null) onChanged(c);
        },
      );
}

class _ColorSheet extends StatefulWidget {
  const _ColorSheet({required this.initial, required this.title});
  final int initial;
  final String title;

  @override
  State<_ColorSheet> createState() => _ColorSheetState();
}

class _ColorSheetState extends State<_ColorSheet> {
  late final TextEditingController _hex = TextEditingController(text: hex(Color(widget.initial)));
  String? _error;

  static const _extra = [0xFFFFFFFF, 0xFFF5F5F5, 0xFFBDBDBD, 0xFF616161, 0xFF000000, 0xFFE0F2F1, 0xFFFFF8E1, 0xFFE8F5E9, 0xFFE3F2FD, 0xFFFFEBEE, 0xFF90CAF9, 0xFFA5D6A7];

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in [...kPalette, ..._extra])
                    Semantics(
                      button: true,
                      label: 'Couleur ${hex(Color(c))}',
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context, c),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: c == widget.initial ? context.cs.primary : context.cs.outlineVariant, width: c == widget.initial ? 3 : 1)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _hex,
                decoration: InputDecoration(labelText: 'Code hexadécimal', hintText: '#1f7fd1', errorText: _error),
                autocorrect: false,
                onSubmitted: (_) => _apply(),
              ),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: _apply, child: const Text('Appliquer'))),
            ],
          ),
        ),
      ),
    );
  }

  void _apply() {
    final c = parseHex(_hex.text);
    if (c == null) {
      setState(() => _error = 'Code invalide (ex. #1f7fd1)');
      return;
    }
    Navigator.pop(context, c.value);
  }
}

/// Ligne avec un curseur et sa valeur.
class SliderTile extends StatelessWidget {
  const SliderTile({super.key, required this.title, required this.value, required this.min, required this.max, required this.onChanged, this.divisions, this.display});
  final String title;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Expanded(child: Text(title)), Text(display ?? value.toStringAsFixed(2), style: context.tt.bodySmall)]),
            Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged),
          ],
        ),
      );
}

/// Page de réglages standard.
class SettingsPageScaffold extends StatelessWidget {
  const SettingsPageScaffold({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(padding: const EdgeInsets.only(bottom: 40), children: children),
      );
}
