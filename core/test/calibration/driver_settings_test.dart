import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

double _f(String hex) => fromHex(hex).buffer.asFloat32List()[0];
String _bits(double v) => toHex((Float32List(1)..[0] = v).buffer.asUint8List());

const _nl = '\r\n';
String _f2(double v) => formatDecimals(v, 0, 2);

/// The original's wording, to compare with the TypeScript vectors.
String _message(SettingCheck c, ParamDef p) {
  final v = c.values;
  return switch (c.problem) {
    SettingProblem.none || SettingProblem.duplicate => '',
    SettingProblem.tooManyDuplicates =>
      'There is a maximum of ${formatGeneral(v[0])} configuration items already set to the same value.',
    SettingProblem.outOfRange =>
      '${p.name ?? ''} value needs to be between ${formatGeneral(v[0])} and ${formatGeneral(v[1])}.',
    SettingProblem.idleClDutiesInverted =>
      'CL Min Duty (${_f2(v[0])}) must be below CL Max Duty (${_f2(v[1])}). With the pair inverted the ECU gives closed '
          'loop the whole ${_f2(v[2])} to ${_f2(v[3])} range instead.',
    SettingProblem.idleClMaxAbovePwmMax =>
      'CL Max Duty (${_f2(v[1])}) is above PWM Max Duty (${_f2(v[3])}). The ECU stores ${_f2(v[1])} but holds closed '
          'loop to ${_f2(v[3])}, because the valve cannot be driven past its PWM Max Duty.$_nl${_nl}Set it anyway?',
    SettingProblem.idleClMinBelowPwmMin =>
      'CL Min Duty (${_f2(v[0])}) is below PWM Min Duty (${_f2(v[2])}). The ECU stores ${_f2(v[0])} but holds closed '
          'loop to ${_f2(v[2])}, because the valve cannot be driven below its PWM Min Duty.$_nl${_nl}Set it anyway?',
    SettingProblem.nissanSrCamSyncAfterRpm =>
      'Cam Sync After RPM must be 0 while Trigger Pattern is Nissan SR. It gates the cam handler off until the ECU '
          'already has an RPM reading, and this pattern has no crank-only sync to produce one, so the engine would '
          'never sync.',
    SettingProblem.nissanSrPatternsTogether =>
      'Trigger Pattern and Cam A Pattern have to be set to Nissan SR together - the crank track alone carries no '
          'position information, so the ECU never reaches sync on any other combination.$_nl${_nl}Set this one now '
          'and the other one next?',
    SettingProblem.nissanSrPhasing =>
      '[${c.phasedDriver}] is set to ${c.phasedOption}, but the Nissan SR pattern resolves engine position to 180 '
          'crank degrees only. The firmware syncs on the cam window pitch and does not measure their widths, so the '
          'ECU knows it is on a 180 degree boundary but not which one, and the phase is re-thrown on every sync '
          'acquisition.$_nl${_nl}That is enough for distributor ignition and paired or batch injection. A mode that '
          'needs the 0 against 360 degree distinction will run a cycle out of phase about half the time it '
          'syncs.$_nl${_nl}Set it anyway?',
  };
}

String _rowName(ParamDef p, UnitPreferences prefs) {
  if (p.type == ParamType.comboBox) return settingName(p);
  final u = preferredUnit(p.measurementUnits, prefs);
  return settingName(p) + (u == MeasurementUnit.raw ? '' : '(${u.key})');
}

MeasurementUnit _unit(int bit) => MeasurementUnit.values.firstWhere((u) => u.bit == bit);

Future<void> main() async {
  final cases = (await loadVectors('driver_settings.json')).cast<Map<String, dynamic>>();

  test('settings pages follow the TypeScript engine (${cases.length} cases)', () {
    for (final (n, c) in cases.indexed) {
      final cal = readDeviceFile(c['xml'] as String).calibration;
      final u = (c['units'] as List<dynamic>).cast<int>();
      final prefs = (
        analog: _unit(u[0]),
        analogTemperature: _unit(u[1]),
        pressure: _unit(u[2]),
        temperature: _unit(u[3]),
      );
      for (final (k, s) in (c['checks'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
        final id = s['driver'] as int;
        final d = cal.definition.drivers[id]!;
        final values = cal.drivers[id]!;
        final why = 'case $n check $k (${s['op']})';
        switch (s['op']) {
          case 'edit':
            values.config[s['index'] as int] = (s['value'] as num).toDouble();
          case 'validate':
            final index = s['index'] as int;
            final r = checkSetting(cal, id, index, (s['value'] as num).toDouble());
            expect(r.verdict.index, s['result'], reason: why);
            expect(_message(r, d.params[index]), s['message'], reason: why);
            expect(r.duplicates, s['duplicates'], reason: why);
            final def = s['default'] as List<dynamic>?;
            expect(r.defaultValue == null ? null : [r.defaultValue!.$1, r.defaultValue!.$2], def, reason: why);
          case 'parse':
            final param = d.params[s['index'] as int];
            final raw = parseSetting(param, s['text'] as String, prefs);
            if (param.type == ParamType.inputBox &&
                preferredUnit(param.measurementUnits, prefs) == MeasurementUnit.fahrenheit &&
                s['raw'] != null) {
              // Fahrenheit input converts correctly here (behaviour-changes.md); the original added 32.
              final typed = parseNetSingle(s['text'] as String);
              expect(raw, toRaw(MeasurementUnit.fahrenheit, typed, checkBoundaries: true), reason: why);
            } else {
              expect(raw == null ? null : _bits(raw), s['raw'], reason: why);
            }
          case 'link':
            final kind = s['kind'] == 'input' ? LinkKind.input : LinkKind.output;
            final r = checkLinkChoice(d, values, kind, s['index'] as int, s['id'] as int);
            expect(r.verdict.index, s['result'], reason: why);
            expect(r.verdict == SettingVerdict.invalid ? 'Duplicates not allowed.' : '', s['message'], reason: why);
            expect(r.duplicates, s['duplicates'], reason: why);
            final def = s['default'] as List<dynamic>?;
            expect(r.defaultValue == null ? null : [r.defaultValue!.$1, r.defaultValue!.$2], def, reason: why);
        }
      }
      for (final dv in (c['drivers'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final id = dv['id'] as int;
        final d = cal.definition.drivers[id]!;
        final values = cal.drivers[id]!;
        final why = 'case $n driver $id';
        expect(
          [
            for (final r in settingRows(d)) [r.index, r.section, _rowName(r.param, prefs), r.param.toolTipText ?? ''],
          ],
          dv['rows'],
          reason: why,
        );
        expect(
          [for (var i = 0; i < d.params.length; i++) isSettingReadOnly(d, values, i)],
          dv['readOnly'],
          reason: why,
        );
        expect(
          [for (var i = 0; i < d.params.length; i++) settingText(d.params[i], settingValue(d, values, i), prefs)],
          dv['texts'],
          reason: why,
        );
        expect(
          [
            for (final r in linkRows(d, cal.definition))
              [
                r.kind.name,
                r.index,
                '${r.name ?? ''}:',
                r.visible,
                r.choices,
                () {
                  final ids = r.kind == LinkKind.input ? values.inputs : values.outputs;
                  return r.choices.contains(ids[r.index]) ? ids[r.index] : null;
                }(),
              ],
          ],
          dv['links'],
          reason: why,
        );
      }
    }
  });

  test('raw values parse in the preferred unit', () {
    const p = ParamDef(name: 'MAP', measurementUnits: ['KPa', 'PSI']);
    final psi = (
      analog: MeasurementUnit.volt,
      analogTemperature: MeasurementUnit.volt,
      pressure: MeasurementUnit.psi,
      temperature: MeasurementUnit.celsius,
    );
    expect(preferredUnit(p.measurementUnits, psi), MeasurementUnit.psi);
    expect(preferredUnit(p.measurementUnits, defaultUnitPreferences), MeasurementUnit.kPa);
    expect(
      _f(_bits(parseSetting(p, '1', defaultUnitPreferences)!)),
      toRaw(MeasurementUnit.kPa, 1, checkBoundaries: true),
    );
  });
}
