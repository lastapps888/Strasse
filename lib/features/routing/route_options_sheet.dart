import 'package:flutter/material.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/domain/domain.dart';

/// Options d'itinéraire selon le mode. Renvoie les nouvelles préférences, ou null si l'utilisateur annule.
Future<RoutePrefs?> showRouteOptionsSheet(BuildContext context, {required TravelMode mode, required RoutePrefs prefs}) {
  return showModalBottomSheet<RoutePrefs>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _OptionsSheet(mode: mode, initial: prefs),
  );
}

class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet({required this.mode, required this.initial});
  final TravelMode mode;
  final RoutePrefs initial;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late RoutePrefs p = widget.initial;
  late bool _custom = widget.initial.customHighwayUse != null || widget.initial.customTollUse != null;

  @override
  Widget build(BuildContext context) {
    final car = widget.mode == TravelMode.car;
    final bike = widget.mode == TravelMode.bike;
    final walk = widget.mode == TravelMode.walk;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Critère'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<RouteCriterion>(
                segments: const [
                  ButtonSegment(value: RouteCriterion.fastest, label: Text('Plus rapide'), icon: Icon(Icons.bolt_rounded)),
                  ButtonSegment(value: RouteCriterion.shortest, label: Text('Plus court'), icon: Icon(Icons.straighten_rounded)),
                ],
                selected: {p.criterion},
                onSelectionChanged: (s) => setState(() => p = p.copyWith(criterion: s.first)),
              ),
            ),
            if (car) ...[
              const SectionTitle('Éviter'),
              SwitchRow(title: 'Péages', value: p.avoidTolls, onChanged: (v) => setState(() => p = p.copyWith(avoidTolls: v))),
              SwitchRow(title: 'Autoroutes', value: p.avoidHighways, onChanged: (v) => setState(() => p = p.copyWith(avoidHighways: v))),
              SwitchRow(title: 'Ferries', value: p.avoidFerries, onChanged: (v) => setState(() => p = p.copyWith(avoidFerries: v))),
              SwitchRow(
                title: 'Itinéraire personnalisé',
                subtitle: 'Ajuste la préférence pour les autoroutes et les péages',
                value: _custom,
                onChanged: (v) => setState(() {
                  _custom = v;
                  p = v ? p.copyWith(customHighwayUse: p.customHighwayUse ?? 0.5, customTollUse: p.customTollUse ?? 0.5) : p.copyWith(clearCustom: true);
                }),
              ),
              if (_custom) ...[
                _slider('Usage des autoroutes', p.customHighwayUse ?? 0.5, (v) => setState(() => p = p.copyWith(customHighwayUse: v))),
                _slider('Usage des péages', p.customTollUse ?? 0.5, (v) => setState(() => p = p.copyWith(customTollUse: v))),
              ],
            ],
            if (bike) ...[
              const SectionTitle('Vélo'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  children: [for (final b in BikeType.values) ChoiceChip(label: Text(b.label), selected: p.bikeType == b, onSelected: (_) => setState(() => p = p.copyWith(bikeType: b)))],
                ),
              ),
              SwitchRow(title: 'Privilégier les pistes cyclables', value: p.preferCycleways, onChanged: (v) => setState(() => p = p.copyWith(preferCycleways: v))),
              SwitchRow(title: 'Éviter les côtes', value: p.avoidHills, onChanged: (v) => setState(() => p = p.copyWith(avoidHills: v))),
            ],
            if (walk) ...[
              const SectionTitle('Marche'),
              SwitchRow(title: 'Éviter les escaliers', value: p.avoidStairs, onChanged: (v) => setState(() => p = p.copyWith(avoidStairs: v))),
              SwitchRow(title: 'Éviter les côtes', value: p.avoidHills, onChanged: (v) => setState(() => p = p.copyWith(avoidHills: v))),
              _slider('Vitesse de marche : ${p.walkSpeedKmh.toStringAsFixed(1)} km/h', (p.walkSpeedKmh - 2) / 5, (v) => setState(() => p = p.copyWith(walkSpeedKmh: 2 + v * 5)), showValue: false),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler'))),
                  const SizedBox(width: 12),
                  Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, p), child: const Text('Appliquer'))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(String label, double value, ValueChanged<double> onChanged, {bool showValue = true}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(showValue ? '$label : ${(value * 100).round()} %' : label),
            Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged),
          ],
        ),
      );
}
