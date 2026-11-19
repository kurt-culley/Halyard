import 'dart:async';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'strings.dart';

typedef ParameterRow = ({String section, String name, String? unit, String value, String? tip, bool enabled});
typedef LinkChoiceRow = ({String name, String value});

/// The ECU's settings pages, read only, in the units the user reads.
class ParametersController extends ChangeNotifier {
  ParametersController(this._session, {this.units = defaultUnitPreferences}) {
    _sub = _session.states.listen((_) => notifyListeners());
  }

  final Session _session;
  final UnitPreferences units;
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
            section: r.section,
            name: settingName(r.param),
            unit: unit == null || unit == MeasurementUnit.raw ? null : ParametersStrings.unit(unit),
            value: settingText(r.param, settingValue(d, v, r.index), units),
            tip: r.param.toolTipText,
            enabled: isSettingEnabled(d, v, r.index),
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
    unawaited(_sub.cancel());
    super.dispose();
  }
}
