import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/app/widgets/vehicle_icons.dart';
import 'package:strasse/core/i18n/translator.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/settings/settings_model.dart';
import 'package:strasse/features/settings/settings_widgets.dart';

/// Véhicule : type (profil de calcul réel), pictogramme sur la carte, dimensions du camion, coût et alerte de vitesse.
class VehicleSettingsPage extends ConsumerWidget {
  const VehicleSettingsPage({super.key});

  static const Map<VehicleType, String> _details = {
    VehicleType.car: 'Profil voiture de Valhalla.',
    VehicleType.microcar: 'Profil voiture, autoroutes évitées et vitesse modélisée plafonnée à 45 km/h. Les voies rapides non classées autoroute restent possibles : vérifiez les panneaux.',
    VehicleType.motorcycle: 'Profil moto de Valhalla (routes sinueuses acceptées, chemins évités).',
    VehicleType.bicycle: 'Active le mode vélo par défaut (profil vélo de Valhalla, options dans Options d\'itinéraire).',
    VehicleType.electric: 'Même calcul que la voiture : Valhalla ne gère ni l\'autonomie ni les bornes de recharge. L\'estimation d\'énergie utilise vos kWh/100 km.',
    VehicleType.van: 'Profil poids lourd avec des dimensions de fourgon courantes (2,7 m de haut, 2,1 m de large, 6 m, 3,5 t).',
    VehicleType.truck: 'Profil poids lourd avec vos dimensions : hauteur, largeur, longueur et poids sont transmis à Valhalla pour éviter les passages interdits connus d\'OpenStreetMap.',
  };

  Future<void> _set(WidgetRef ref, AppSettings Function(AppSettings) f) => ref.read(settingsProvider.notifier).update(f);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final cs = context.cs;
    final electric = s.vehicleType == VehicleType.electric;
    final truck = s.vehicleType == VehicleType.truck;
    return SettingsPageScaffold(
      title: 'Véhicule et vitesse',
      children: [
        const SectionTitle('Type de véhicule'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final t in VehicleType.values)
                ChoiceChip(
                  label: Text(t.label),
                  selected: s.vehicleType == t,
                  onSelected: (_) => _set(
                    ref,
                    (x) => x.copyWith(
                      vehicleType: t,
                      vehicleIcon: defaultIconFor(t),
                      defaultMode: t == VehicleType.bicycle ? TravelMode.bike : (x.defaultMode == TravelMode.bike ? TravelMode.car : x.defaultMode),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 0), child: Text(_details[s.vehicleType] ?? '', style: context.tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
        if (truck) ...[
          const SectionTitle('Dimensions du camion'),
          _slider(context, 'Hauteur', s.truckHeightM, 1.5, 6.0, 'm', (v) => _set(ref, (x) => x.copyWith(truckHeightM: v))),
          _slider(context, 'Largeur', s.truckWidthM, 1.5, 4.0, 'm', (v) => _set(ref, (x) => x.copyWith(truckWidthM: v))),
          _slider(context, 'Longueur', s.truckLengthM, 3.0, 25.0, 'm', (v) => _set(ref, (x) => x.copyWith(truckLengthM: v))),
          _slider(context, 'Poids', s.truckWeightT, 1.0, 60.0, 't', (v) => _set(ref, (x) => x.copyWith(truckWeightT: v))),
        ],
        const SectionTitle('Icône sur la carte'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final i in VehicleIcon.values)
                Semantics(
                  label: tr(i.label),
                  selected: s.vehicleIcon == i,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _set(ref, (x) => x.copyWith(vehicleIcon: i)),
                    child: Container(
                      width: 78,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: s.vehicleIcon == i ? cs.primaryContainer : cs.surfaceContainerHighest.withOpacity(0.5),
                        border: Border.all(color: s.vehicleIcon == i ? cs.primary : Colors.transparent, width: 1.6),
                      ),
                      child: Column(children: [
                        VehicleGlyph(i, color: s.primary, size: 44),
                        const SizedBox(height: 4),
                        Text(i.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SectionTitle(electric ? 'Coût de l\'énergie (facultatif)' : 'Coût du carburant (facultatif)'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text('Sans ces deux valeurs, aucun coût n\'est affiché. Les péages ne sont jamais chiffrés : aucune source de tarifs fiable n\'est utilisée.', style: context.tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        _slider(context, electric ? 'Consommation (kWh/100 km)' : 'Consommation (L/100 km)', s.fuelConsumption, 0, electric ? 40 : 30, '', (v) => _set(ref, (x) => x.copyWith(fuelConsumption: double.parse(v.toStringAsFixed(1)))), zeroLabel: 'non renseignée'),
        _slider(context, electric ? 'Prix du kWh (€)' : 'Prix du litre (€)', s.fuelPrice, 0, electric ? 1.0 : 3.0, '€', (v) => _set(ref, (x) => x.copyWith(fuelPrice: double.parse(v.toStringAsFixed(2)))), zeroLabel: 'non renseigné', decimals: 2),
        const SectionTitle('Vitesse pendant le guidage'),
        SwitchRow(title: 'Afficher la vitesse', subtitle: 'Vitesse mesurée par le GPS, avec la limite affichée quand elle est connue.', value: s.showSpeed, onChanged: (v) => _set(ref, (x) => x.copyWith(showSpeed: v))),
        SwitchRow(
          title: 'Alerte de dépassement',
          subtitle: 'Signal visuel discret lorsque vous dépassez la limite connue.',
          value: s.speedAlertEnabled,
          onChanged: (v) => _set(ref, (x) => x.copyWith(speedAlertEnabled: v)),
        ),
        if (s.speedAlertEnabled) ...[
          SwitchRow(title: 'Bip sonore', subtitle: 'Un court signal, au plus une fois toutes les 30 secondes.', value: s.speedAlertSound, onChanged: (v) => _set(ref, (x) => x.copyWith(speedAlertSound: v))),
          _slider(context, 'Marge avant alerte', s.speedAlertMarginKmh.toDouble(), 0, 15, 'km/h', (v) => _set(ref, (x) => x.copyWith(speedAlertMarginKmh: v.round())), decimals: 0),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Text(
            'Les limites viennent d\'OpenStreetMap (balise maxspeed) : elles peuvent être absentes, anciennes ou erronées, et ne remplacent pas la signalisation. '
            'Respectez toujours les panneaux et le code de la route local.',
            style: context.tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _slider(BuildContext context, String label, double value, double min, double max, String unit, ValueChanged<double> onChanged, {String? zeroLabel, int decimals = 1}) {
    final shown = (value == 0 && zeroLabel != null) ? zeroLabel : '${value.toStringAsFixed(decimals)} $unit'.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label : $shown'),
          Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ],
      ),
    );
  }
}
