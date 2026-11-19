import 'package:halyard_core/halyard_core.dart';

abstract final class ParametersStrings {
  static String unit(MeasurementUnit u) => switch (u) {
    MeasurementUnit.celsius => '°C',
    MeasurementUnit.fahrenheit => '°F',
    MeasurementUnit.volt => 'V',
    MeasurementUnit.ohm => 'Ω',
    MeasurementUnit.kPa => 'kPa',
    MeasurementUnit.psi => 'psi',
    _ => '',
  };

  static const notOnline = 'Connect to an ECU to see its settings.';
  static const choose = 'Choose a settings page.';
  static const readOnly = 'Read only: editing arrives with the write gate.';
  static const doesNotApply = 'Does not apply with the current settings';
  static const links = 'Links';
  static String driver(int id) => 'Settings $id';
  static String unset(int id) => id == 0 ? 'None' : 'Link $id';
}
