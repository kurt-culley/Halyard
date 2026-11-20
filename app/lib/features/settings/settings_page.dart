import 'package:auto_route/auto_route.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'strings.dart';

/// The app's own preferences: for now the four unit choices the original's View menu offered.
@RoutePage()
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<ValueNotifier<UnitPreferences>>();
    final u = notifier.value;
    final theme = Theme.of(context);
    Widget choice(
      String label,
      MeasurementUnit value,
      List<MeasurementUnit> options,
      UnitPreferences Function(UnitPreferences u, MeasurementUnit v) set,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          SizedBox(width: 240, child: Text(label)),
          SegmentedButton<MeasurementUnit>(
            segments: [
              for (final o in options) ButtonSegment(value: o, label: Text(SettingsStrings.names[o.key] ?? o.key)),
            ],
            selected: {value},
            onSelectionChanged: (s) => notifier.value = set(notifier.value, s.first),
          ),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(SettingsStrings.title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        Text(SettingsStrings.units, style: theme.textTheme.titleLarge),
        Text(SettingsStrings.unitsHint, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        choice(
          SettingsStrings.pressure,
          u.pressure,
          const [MeasurementUnit.kPa, MeasurementUnit.psi],
          (u, v) => (analog: u.analog, analogTemperature: u.analogTemperature, pressure: v, temperature: u.temperature),
        ),
        choice(SettingsStrings.temperature, u.temperature, const [
          MeasurementUnit.celsius,
          MeasurementUnit.fahrenheit,
        ], (u, v) => (analog: u.analog, analogTemperature: u.analogTemperature, pressure: u.pressure, temperature: v)),
        choice(
          SettingsStrings.analog,
          u.analog,
          const [MeasurementUnit.raw, MeasurementUnit.volt],
          (u, v) =>
              (analog: v, analogTemperature: u.analogTemperature, pressure: u.pressure, temperature: u.temperature),
        ),
        choice(SettingsStrings.analogTemperature, u.analogTemperature, const [
          MeasurementUnit.raw,
          MeasurementUnit.volt,
          MeasurementUnit.ohm,
        ], (u, v) => (analog: u.analog, analogTemperature: v, pressure: u.pressure, temperature: u.temperature)),
      ],
    );
  }
}
