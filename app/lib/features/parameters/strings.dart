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
  static const readOnly = 'Read only: turn off read only on the connect page to edit.';
  static const store = 'Store to flash';
  static const stored = 'Stored.';
  static const sent = 'Sent.';
  static const setAnyway = 'Set it anyway';
  static const resetOthers = 'Set it, and reset the others';
  static const cancel = 'Cancel';
  static const ok = 'OK';
  static const notValid = 'That is not a valid value.';
  static String failed(String what) => 'The ECU did not accept the change ($what).';
  static String duplicates(List<String> names, String value) =>
      'Also set to this value: ${names.join(', ')}. They will be reset to $value.';

  static String _f2(double v) => formatDecimals(v, 0, 2);

  /// The original's wording for why a change was refused or needs a word.
  static String problem(SettingCheck c, String name) {
    final v = c.values;
    const nl = '\n';
    return switch (c.problem) {
      SettingProblem.none || SettingProblem.duplicate => '',
      SettingProblem.tooManyDuplicates =>
        'There is a maximum of ${formatGeneral(v[0])} configuration items already set to the same value.',
      SettingProblem.outOfRange => '$name value needs to be between ${formatGeneral(v[0])} and ${formatGeneral(v[1])}.',
      SettingProblem.idleClDutiesInverted =>
        'CL Min Duty (${_f2(v[0])}) must be below CL Max Duty (${_f2(v[1])}). With the pair inverted the ECU gives '
            'closed loop the whole ${_f2(v[2])} to ${_f2(v[3])} range instead.',
      SettingProblem.idleClMaxAbovePwmMax =>
        'CL Max Duty (${_f2(v[1])}) is above PWM Max Duty (${_f2(v[3])}). The ECU stores ${_f2(v[1])} but holds '
            'closed loop to ${_f2(v[3])}, because the valve cannot be driven past its PWM Max Duty.',
      SettingProblem.idleClMinBelowPwmMin =>
        'CL Min Duty (${_f2(v[0])}) is below PWM Min Duty (${_f2(v[2])}). The ECU stores ${_f2(v[0])} but holds '
            'closed loop to ${_f2(v[2])}, because the valve cannot be driven below its PWM Min Duty.',
      SettingProblem.nissanSrCamSyncAfterRpm =>
        'Cam Sync After RPM must be 0 while Trigger Pattern is Nissan SR. It gates the cam handler off until the ECU '
            'already has an RPM reading, and this pattern has no crank-only sync to produce one, so the engine would '
            'never sync.',
      SettingProblem.nissanSrPatternsTogether =>
        'Trigger Pattern and Cam A Pattern have to be set to Nissan SR together - the crank track alone carries no '
            'position information, so the ECU never reaches sync on any other combination.${nl}Set this one now and '
            'the other one next?',
      SettingProblem.nissanSrPhasing =>
        '[${c.phasedDriver}] is set to ${c.phasedOption}, but the Nissan SR pattern resolves engine position to 180 '
            'crank degrees only. The firmware syncs on the cam window pitch and does not measure their widths, so the '
            'ECU knows it is on a 180 degree boundary but not which one, and the phase is re-thrown on every sync '
            'acquisition.$nl${nl}That is enough for distributor ignition and paired or batch injection. A mode that '
            'needs the 0 against 360 degree distinction will run a cycle out of phase about half the time it syncs.',
    };
  }

  static const doesNotApply = 'Does not apply with the current settings';
  static const links = 'Links';
  static String driver(int id) => 'Settings $id';
  static String unset(int id) => id == 0 ? 'None' : 'Link $id';
}
