import 'dart:async';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'strings.dart';

typedef ParameterRow = ({
  int index,
  String section,
  String name,
  String? unit,
  String value,
  String? tip,
  bool enabled,
  bool editable,
});
typedef LinkChoiceRow = ({String name, String value});

/// The ECU's settings pages, read only, in the units the user reads.
class ParametersController extends ChangeNotifier {
  ParametersController(this._session, this._gate, this._policy, {ValueNotifier<UnitPreferences>? units})
    // ignore: prefer_initializing_formals, a named parameter can't be private
    : _units = units {
    _units?.addListener(notifyListeners);
    _sub = _session.states.listen((_) => notifyListeners());
  }

  final Session _session;
  final WriteGate _gate;
  final SwitchablePolicy _policy;
  String? message;

  bool get canEdit => !_policy.readOnly;

  ParamDef? param(int index) => _session.calibration?.definition.drivers[selected]?.params[index];

  /// The options of a list setting, or null for a typed one.
  List<(double, String)>? optionsOf(int index) {
    final p = param(index);
    if (p == null || p.type != ParamType.comboBox) return null;
    return [for (final o in p.options ?? const <ComboOption>[]) (o.id.toDouble(), o.name ?? '${o.id}')];
  }

  String textOf(int index) {
    final cal = _session.calibration!;
    final d = cal.definition.drivers[selected]!;
    return settingText(d.params[index], settingValue(d, cal.drivers[selected]!, index), units);
  }

  /// Parses the typed text in the user's units; null when it isn't a value.
  double? parse(int index, String text) => param(index) == null ? null : parseSetting(param(index)!, text, units);

  /// Checks a change the original's way; a valid one is made at once.
  SettingCheck check(int index, double raw) => _gate.setSetting(selected!, index, raw);

  void approve(int index, double raw, SettingCheck c) => _gate.applyApproved(selected!, index, raw, c);

  /// Sends the page's settings, as the original did after each change.
  Future<void> send({bool store = false}) async {
    final r = await _gate.saveDriver(selected!, store: store);
    final failed = r.failed;
    message = failed == null
        ? (store ? ParametersStrings.stored : ParametersStrings.sent)
        : ParametersStrings.failed(failed.failure.name);
    notifyListeners();
  }

  String nameOf(int index) => settingName(param(index)!);
  final ValueNotifier<UnitPreferences>? _units;
  UnitPreferences get units => _units?.value ?? defaultUnitPreferences;
  late final StreamSubscription<SessionState> _sub;
  int? selected;

  bool get isOnline => _session.state.phase == SessionPhase.online && _session.calibration != null;

  List<(int, String)> get drivers {
    final cal = _session.calibration;
    if (cal == null) return const [];
    return [for (final d in cal.definition.drivers.values) (d.id, d.name ?? ParametersStrings.driver(d.id))]
      ..sort((a, b) => a.$2.compareTo(b.$2));
  }

  void select(int id) {
    selected = id;
    message = null;
    notifyListeners();
  }

  List<ParameterRow> get rows {
    final cal = _session.calibration;
    final d = cal?.definition.drivers[selected];
    final v = cal?.drivers[selected];
    if (d == null || v == null) return const [];
    return [
      for (final r in settingRows(d))
        () {
          final unit = r.param.type == ParamType.comboBox ? null : preferredUnit(r.param.measurementUnits, units);
          return (
            index: r.index,
            section: r.section,
            name: settingName(r.param),
            unit: unit == null || unit == MeasurementUnit.raw ? null : ParametersStrings.unit(unit),
            value: settingText(r.param, settingValue(d, v, r.index), units),
            tip: r.param.toolTipText,
            enabled: isSettingEnabled(d, v, r.index),
            editable: !isSettingReadOnly(d, v, r.index),
          );
        }(),
    ];
  }

  List<LinkChoiceRow> get linkChoices {
    final cal = _session.calibration;
    final d = cal?.definition.drivers[selected];
    final v = cal?.drivers[selected];
    if (cal == null || d == null || v == null) return const [];
    return [
      for (final r in linkRows(d, cal.definition))
        if (r.visible)
          () {
            final id = (r.kind == LinkKind.input ? v.inputs : v.outputs)[r.index];
            return (name: r.name ?? '', value: cal.definition.links[id]?.name ?? ParametersStrings.unset(id));
          }(),
    ];
  }

  @override
  void dispose() {
    _units?.removeListener(notifyListeners);
    unawaited(_sub.cancel());
    super.dispose();
  }
}
