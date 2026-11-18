/// Settings pages (U18): a driver's settings as rows, their units, reading typed values, and the checks before a
/// change (V01 to V05, L01 to L02): repeated values within a group, the range, and the relations between settings
/// that a value can break (idle duties, the Nissan SR trigger and phased outputs). Results are typed; the app words
/// them. Applying a change goes through the write gate.
library;

import '../definition/definition.dart';
import '../logs/number_text.dart';
import '../units/units.dart';
import '../wire/bytes.dart' show fround;
import 'calibration.dart';

/// The units the user reads values in, by kind of reading.
typedef UnitPreferences =
    ({
      MeasurementUnit analog,
      MeasurementUnit analogTemperature,
      MeasurementUnit pressure,
      MeasurementUnit temperature,
    });

const UnitPreferences defaultUnitPreferences = (
  analog: MeasurementUnit.volt,
  analogTemperature: MeasurementUnit.volt,
  pressure: MeasurementUnit.kPa,
  temperature: MeasurementUnit.celsius,
);

/// The unit a value with [units] is shown in: the preferred unit for its kind when it offers that, otherwise raw.
MeasurementUnit preferredUnit(List<String> units, UnitPreferences prefs) {
  var flags = 0;
  for (final u in units) {
    flags |= MeasurementUnit.fromKey(u)?.bit ?? 0;
  }
  bool has(MeasurementUnit u) => flags & u.bit != 0;
  final want =
      has(MeasurementUnit.ohm)
          ? prefs.analogTemperature
          : has(MeasurementUnit.volt)
          ? prefs.analog
          : has(MeasurementUnit.kPa)
          ? prefs.pressure
          : has(MeasurementUnit.celsius)
          ? prefs.temperature
          : null;
  for (final u in units) {
    final m = MeasurementUnit.fromKey(u);
    if (m != null && m == want) return m;
  }
  return MeasurementUnit.raw;
}

bool _blank(String? s) => s == null || s.trim().isEmpty;
bool _ieq(String? a, String? b) => a != null && b != null && a.toLowerCase() == b.toLowerCase();
bool _contains(String? s, String part) => s != null && s.toLowerCase().contains(part.toLowerCase());

/// The name a setting is shown by.
String settingName(ParamDef p) => (p.displayName == null || p.displayName!.isEmpty ? p.name : p.displayName) ?? '';

/// A setting's current value: from the calibration, or the definition's for a parameter past the stored ones.
double settingValue(DriverDef d, DriverValues v, int i) => i < v.config.length ? v.config[i] : d.params[i].value;

typedef SettingRow = ({int index, String section, ParamDef param});

/// The rows of a settings page in definition order, each under the last section named before it ("Settings" before
/// any); hidden settings are left out.
List<SettingRow> settingRows(DriverDef d) {
  final rows = <SettingRow>[];
  var section = 'Settings';
  for (var i = 0; i < d.configCount && i < d.params.length; i++) {
    final p = d.params[i];
    if (!_blank(p.sectionName)) section = p.sectionName!;
    if (p.hidden) continue;
    rows.add((index: i, section: section, param: p));
  }
  return rows;
}

/// The first setting named [name], ignoring case, or -1.
int settingIndex(DriverDef d, String name) => d.params.indexWhere((p) => _ieq(p.name, name));

/// Whether the setting at [index] applies: a view constraint makes it depend on another setting's value.
bool isSettingEnabled(DriverDef d, DriverValues v, int index) {
  final p = d.params[index];
  final accepted = p.viewConstraint?.acceptedValues;
  if (accepted == null || accepted.isEmpty) return true;
  final t = _constraintTarget(d, p);
  if (t == null) return false;
  final value = settingValue(d, v, t);
  return accepted.any((a) => fround(a) == value);
}

int? _constraintTarget(DriverDef d, ParamDef p) {
  final i = p.viewConstraint!.paramIndex;
  if (i < 0 || i >= d.params.length) return null;
  // The original's own correction: a default intake temperature follows whether the intake temperature is used.
  if (_contains(p.name, 'Default IAT') && !_contains(d.params[i].name, 'Use IAT in Algorithm')) {
    final use = d.params.indexWhere((x) => _contains(x.name, 'Use IAT in Algorithm'));
    if (use >= 0) return use;
  }
  return i;
}

bool isSettingReadOnly(DriverDef d, DriverValues v, int index) =>
    d.params[index].readOnly || !isSettingEnabled(d, v, index);

/// A setting's value as shown: the option's name for a list (the number when no option has it), otherwise in the
/// preferred unit with up to 3 decimals.
String settingText(ParamDef p, double raw, UnitPreferences prefs) {
  if (p.type == ParamType.comboBox) {
    for (final o in p.options ?? const <ComboOption>[]) {
      if (o.id == raw) return o.name ?? formatGeneral(raw);
    }
    return formatGeneral(raw);
  }
  return formatDecimals(fromRaw(preferredUnit(p.measurementUnits, prefs), raw, checkBoundaries: true), 0, 3);
}

final _u16 = RegExp(r'^[\t\n\x0B\f\r ]*([+-]?)(\d+)[\t\n\x0B\f\r ]*$');

/// The raw value for typed text, or null: an option by name (any case) or id for a list; otherwise a number in the
/// preferred unit.
double? parseSetting(ParamDef p, String text, UnitPreferences prefs) {
  if (p.type == ParamType.comboBox) {
    final options = p.options;
    if (options == null) return null;
    for (final o in options) {
      if (o.name != null && o.name!.toLowerCase() == text.toLowerCase()) return o.id.toDouble();
    }
    final m = _u16.firstMatch(text);
    if (m == null) return null;
    final n = int.parse(m[2]!) * (m[1] == '-' ? -1 : 1);
    if (n < 0 || n > 0xffff) return null;
    return options.any((o) => o.id == n) ? n.toDouble() : null;
  }
  final double v;
  try {
    v = parseNetSingle(text);
  } on FormatException {
    return null;
  } on RangeError {
    return null;
  }
  return toRaw(preferredUnit(p.measurementUnits, prefs), v, checkBoundaries: true);
}

enum SettingVerdict { valid, invalid, needsApproval, warning }

/// Why a change was refused or needs a word with the user. The values in [SettingCheck.values] are, by problem:
/// tooManyDuplicates [allowed]; outOfRange [min, max]; the idle duties [CL min, CL max, PWM min, PWM max].
enum SettingProblem {
  none,

  /// Another setting of the group has the value; the user may let those go back to the group's default.
  duplicate,
  tooManyDuplicates,
  outOfRange,
  idleClDutiesInverted,
  idleClMaxAbovePwmMax,
  idleClMinBelowPwmMin,

  /// Cam sync after RPM must be 0 with the Nissan SR trigger pattern.
  nissanSrCamSyncAfterRpm,

  /// The trigger and cam A patterns must both be Nissan SR.
  nissanSrPatternsTogether,

  /// A phased ignition or fuel mode with the Nissan SR pattern, which resolves only 180 crank degrees.
  nissanSrPhasing,
}

final class SettingCheck {
  const SettingCheck(
    this.verdict, [
    this.problem = SettingProblem.none,
    this.values = const [],
    this.duplicates = const [],
    this.defaultValue,
    this.phasedDriver,
    this.phasedOption,
  ]);

  static const valid = SettingCheck(SettingVerdict.valid);

  final SettingVerdict verdict;
  final SettingProblem problem;
  final List<double> values;

  /// Indexes of the settings or links holding the same value.
  final List<int> duplicates;

  /// What [duplicates] go back to when the user approves.
  final (String?, double)? defaultValue;

  /// For [SettingProblem.nissanSrPhasing]: the driver and its phased mode.
  final String? phasedDriver, phasedOption;
}

bool _sameGroup(String? g, String? mine) => _blank(g) || g == mine;

/// Checks setting [index] of driver [driverId] taking the raw value [raw], against the rest of [cal].
SettingCheck checkSetting(Calibration cal, int driverId, int index, double raw) {
  final d = cal.definition.drivers[driverId]!;
  final values = cal.drivers[driverId]!;
  final me = d.params[index];
  final v = fround(raw);
  final cv = d.configValidation;
  if (cv != null && cv.checkDuplicates) {
    final dups = [
      for (var i = 0; i < d.params.length; i++)
        if (i != index && d.params[i].validationGroup == me.validationGroup && settingValue(d, values, i) == v) i,
    ];
    if (dups.isNotEmpty) {
      for (final x in cv.exceptions) {
        switch (x.kind) {
          case ValidationExceptionKind.allowMultipleDuplicates:
            if (!_sameGroup(x.group, me.validationGroup)) continue;
            return x.value > dups.length
                ? SettingCheck.valid
                : SettingCheck(SettingVerdict.invalid, SettingProblem.tooManyDuplicates, [x.value]);
          case ValidationExceptionKind.allowIndex when x.value == index && _sameGroup(x.group, me.validationGroup):
          case ValidationExceptionKind.allowValue when x.value == v && _sameGroup(x.group, me.validationGroup):
            return SettingCheck.valid;
          default:
        }
      }
      (String?, double)? global, mine;
      for (final dv in cv.defaultValues ?? const <(String?, double)>[]) {
        if (_blank(dv.$1)) {
          global = dv;
        } else if (dv.$1 == me.validationGroup) {
          mine = dv;
        }
      }
      if ((mine != null && mine.$2 == v) || (global != null && global.$2 == v)) return SettingCheck.valid;
      final def = mine ?? global;
      if (def == null) return const SettingCheck(SettingVerdict.invalid, SettingProblem.duplicate);
      return SettingCheck(SettingVerdict.needsApproval, SettingProblem.duplicate, const [], dups, def);
    }
  }
  if (me.checkRange && (v < me.min || v > me.max)) {
    return SettingCheck(SettingVerdict.invalid, SettingProblem.outOfRange, [me.min, me.max]);
  }
  return _relations(cal, d, values, index, v) ?? SettingCheck.valid;
}

double _valueAt(DriverDef d, DriverValues values, int i, int changed, double v) =>
    i == changed ? v : settingValue(d, values, i);

String? _optionName(DriverDef d, DriverValues values, int i, int changed, double v) {
  if (i < 0 || i >= d.params.length) return null;
  final options = d.params[i].options;
  if (options == null) return null;
  final x = _valueAt(d, values, i, changed, v);
  for (final o in options) {
    if (o.id == x) return o.name;
  }
  return null;
}

const _fuel = 8192, _idle = 8198, _trigger = 8222, _ignition = 8223;
const _phasedIgnition = ['Wasted Spark', 'Wasted Spark - COPS', 'Fully Sequential'];

bool _isPhased(bool ignition, String name) =>
    ignition ? _phasedIgnition.any((o) => _ieq(name, o)) : _ieq(name, 'Fully Seq');

SettingCheck? _relations(Calibration cal, DriverDef d, DriverValues values, int changed, double v) => switch (d.id) {
  _idle => _idleDuties(d, values, changed, v),
  _trigger => _engineTrigger(cal, d, values, changed, v),
  _fuel || _ignition => _cylinderPhasing(cal, d, values, changed, v),
  _ => null,
};

SettingCheck? _idleDuties(DriverDef d, DriverValues values, int changed, double v) {
  final mode = settingIndex(d, 'Mode'), pMin = settingIndex(d, 'PWM Min Duty'), pMax = settingIndex(d, 'PWM Max Duty');
  final cMin = settingIndex(d, 'CL Min Duty'), cMax = settingIndex(d, 'CL Max Duty');
  if (mode < 0 || pMin < 0 || pMax < 0 || cMin < 0 || cMax < 0) return null;
  if (changed != pMin && changed != pMax && changed != cMin && changed != cMax) return null;
  if (_valueAt(d, values, mode, changed, v) != 1) return null;
  final duties = [
    for (final i in [cMin, cMax, pMin, pMax]) _valueAt(d, values, i, changed, v),
  ];
  final [a, b, c, e] = duties;
  if (a >= b) return SettingCheck(SettingVerdict.invalid, SettingProblem.idleClDutiesInverted, duties);
  if (b > e) return SettingCheck(SettingVerdict.warning, SettingProblem.idleClMaxAbovePwmMax, duties);
  if (a < c) return SettingCheck(SettingVerdict.warning, SettingProblem.idleClMinBelowPwmMin, duties);
  return null;
}

SettingCheck? _engineTrigger(Calibration cal, DriverDef d, DriverValues values, int changed, double v) {
  final tp = settingIndex(d, 'Trigger Pattern'), cam = settingIndex(d, 'Cam A Pattern');
  final sync = settingIndex(d, 'Cam Sync After RPM');
  if (tp < 0 || cam < 0) return null;
  if (changed != tp && changed != cam && changed != sync) return null;
  final trigSr = _ieq(_optionName(d, values, tp, changed, v), 'Nissan SR');
  final camSr = _ieq(_optionName(d, values, cam, changed, v), 'Nissan SR');
  if (!trigSr && !camSr) return null;
  if (trigSr && sync >= 0 && _valueAt(d, values, sync, changed, v) != 0) {
    return const SettingCheck(SettingVerdict.invalid, SettingProblem.nissanSrCamSyncAfterRpm);
  }
  if (trigSr != camSr) return const SettingCheck(SettingVerdict.warning, SettingProblem.nissanSrPatternsTogether);
  return _phasedOutputInUse(cal);
}

/// The ignition or fuel driver set to a phased mode, as a Nissan SR phasing warning.
SettingCheck? _phasedOutputInUse(Calibration cal) {
  for (final id in [_ignition, _fuel]) {
    final dr = cal.definition.drivers[id];
    if (dr == null) continue;
    final ign = id == _ignition;
    final i = settingIndex(dr, ign ? 'Mode' : 'Fueling Mode');
    if (i < 0) continue;
    final name = _optionName(dr, cal.drivers[id]!, i, -1, 0);
    if (name != null && _isPhased(ign, name)) return _phasing(dr, name);
  }
  return null;
}

SettingCheck _phasing(DriverDef d, String option) => SettingCheck(
  SettingVerdict.warning,
  SettingProblem.nissanSrPhasing,
  const [],
  const [],
  null,
  d.name ?? '',
  option,
);

SettingCheck? _cylinderPhasing(Calibration cal, DriverDef d, DriverValues values, int changed, double v) {
  final ign = d.id == _ignition;
  final i = settingIndex(d, ign ? 'Mode' : 'Fueling Mode');
  if (i < 0 || changed != i) return null;
  final name = _optionName(d, values, i, changed, v);
  if (name == null || !_isPhased(ign, name)) return null;
  final trig = cal.definition.drivers[_trigger];
  final tp = trig == null ? -1 : settingIndex(trig, 'Trigger Pattern');
  if (tp < 0 || !_ieq(_optionName(trig!, cal.drivers[_trigger]!, tp, -1, 0), 'Nissan SR')) return null;
  return _phasing(d, name);
}

// ---------------------------------------------------------------- link rows

enum LinkKind { input, output }

typedef LinkRow = ({LinkKind kind, int index, String? name, bool visible, List<int> choices});

/// The link choices of a settings page: inputs then outputs, where editable. An input of the analog inputs page
/// (8197) chooses among raw ADC links only. A row without a name is hidden.
List<LinkRow> linkRows(DriverDef d, Definition definition) {
  final rows = <LinkRow>[];
  void add(LinkKind k) {
    final input = k == LinkKind.input;
    final configs = (input ? d.inputConfigs : d.outputConfigs) ?? const <LinkConfig>[];
    final names = input ? d.inputNames : d.outputNames;
    final choices = [
      for (final l in definition.links.values)
        if (!(input && d.id == 8197) || l.dataType == LinkDataType.adcRaw) l.id,
    ];
    for (var i = 0; i < (input ? d.inputCount : d.outputCount); i++) {
      var visible = true;
      for (final c in configs) {
        if (c.index == i) visible = c.visible;
      }
      final name = names != null && i < names.length ? names[i] : null;
      rows.add((kind: k, index: i, name: name, visible: visible && !_blank(name), choices: choices));
    }
  }

  if (d.editableInputs) add(LinkKind.input);
  if (d.editableOutputs) add(LinkKind.output);
  return rows;
}

/// Checks choosing link [linkId] for row [index]: whether another row of the same kind has it.
SettingCheck checkLinkChoice(DriverDef d, DriverValues values, LinkKind kind, int index, int linkId) {
  final v = kind == LinkKind.input ? d.inputValidation : d.outputValidation;
  if (v == null || !v.checkDuplicates) return SettingCheck.valid;
  final ids = kind == LinkKind.input ? values.inputs : values.outputs;
  final dups = [
    for (var i = 0; i < ids.length; i++)
      if (i != index && ids[i] == linkId) i,
  ];
  if (dups.isEmpty) return SettingCheck.valid;
  for (final x in v.exceptions) {
    if (!_blank(x.group)) continue;
    if (x.kind == ValidationExceptionKind.allowIndex && x.value == index) return SettingCheck.valid;
    if (x.kind == ValidationExceptionKind.allowValue && x.value == linkId) return SettingCheck.valid;
  }
  (String?, double)? def;
  for (final dv in v.defaultValues ?? const <(String?, double)>[]) {
    if (_blank(dv.$1)) def = dv;
  }
  if (def != null && def.$2 == linkId) return SettingCheck.valid;
  if (def != null) return SettingCheck(SettingVerdict.needsApproval, SettingProblem.duplicate, const [], dups, def);
  return SettingCheck(SettingVerdict.invalid, SettingProblem.duplicate, const [], dups);
}
