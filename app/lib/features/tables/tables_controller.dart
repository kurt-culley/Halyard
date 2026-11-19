import 'dart:async';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'strings.dart';

typedef TableEntry = ({int id, String name, String category});

typedef TableView = ({
  String name,
  bool enabled,
  String? across,
  String? down,
  List<String> columns,
  List<String> rows,
  List<String> cells,
  List<double> shades,
  (int, int)? live,
});

/// The ECU's tables by category, and the chosen one as text and shades with its live cell.
class TablesController extends ChangeNotifier {
  TablesController(this._session, this._gate, this._policy) {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  final Session _session;
  final WriteGate _gate;
  final SwitchablePolicy _policy;
  late final Timer _timer;
  (int, int)? cell;
  String? message;

  bool get canEdit => !_policy.readOnly;

  void choose(int row, int col) {
    cell = (row, col);
    message = null;
    notifyListeners();
  }

  /// Applies a value or formula to the chosen cell and sends it, as the original did after each edit.
  Future<void> edit(String text) async {
    final id = selected, at = cell, cal = _session.calibration;
    if (id == null || at == null || cal == null || !canEdit) return;
    final v = cal.tables[id]!;
    final i = at.$1 * v.x.length + at.$2;
    final t = text.trim();
    double? value;
    if (t.isNotEmpty && '+-*/='.contains(t[0]) && t.length > 1) {
      final f = TableFormula.parse(t);
      if (f.isValid) value = f.apply(v.z[i]);
    }
    if (value == null) {
      try {
        value = parseNetSingle(t);
      } on Object {
        value = null;
      }
    }
    if (value == null) {
      message = TablesStrings.notNumber;
      notifyListeners();
      return;
    }
    _gate.setTableCell(id, TableElement.values, i, value);
    await _report(_gate.saveTable(id));
  }

  Future<void> store() async {
    final id = selected;
    if (id == null || !canEdit) return;
    await _report(_gate.saveTable(id, store: true), done: TablesStrings.stored);
  }

  Future<void> _report(Future<WriteResult> f, {String? done}) async {
    final r = await f;
    final failed = r.failed;
    message = failed == null ? done : TablesStrings.failed(failed.failure.name);
    notifyListeners();
  }

  int? selected;
  Object? _seen;

  bool get isOnline => _session.calibration != null && _session.state.phase == SessionPhase.online;

  List<TableEntry> get tables {
    final cal = _session.calibration;
    if (cal == null) return const [];
    final list = [
      for (final t in cal.definition.tables.values)
        (id: t.id, name: t.name ?? TablesStrings.table(t.id), category: t.category ?? TablesStrings.other),
    ]..sort((a, b) => a.category == b.category ? a.name.compareTo(b.name) : a.category.compareTo(b.category));
    return list;
  }

  void select(int id) {
    selected = id;
    cell = null;
    message = null;
    notifyListeners();
  }

  TableView? get view {
    final cal = _session.calibration;
    final id = selected;
    if (cal == null || id == null) return null;
    final d = cal.definition.tables[id];
    final v = cal.tables[id];
    if (d == null || v == null) return null;
    final links = cal.definition.links;
    final out = links[d.outputLinkId];
    final f = tableDecimals(d, out);
    String axis(double x) => formatDecimals(x, 0, 2);
    final finite = v.z.where((z) => z.isFinite);
    final lo = finite.isEmpty ? 0.0 : finite.reduce((a, b) => a < b ? a : b);
    final hi = finite.isEmpty ? 1.0 : finite.reduce((a, b) => a > b ? a : b);
    (int, int)? live;
    final store = _session.live;
    final in0 = links[d.input0LinkId];
    if (store != null && in0 != null && v.x.length > 1) {
      final in1 = links[d.input1LinkId];
      if (d.isMap && in1 != null) {
        final p = tablePosition(v, store.value(in0.id), store.value(in1.id));
        live = (p.row, p.col);
      } else if (!d.isMap) {
        final p = tablePosition(
          TableValues(enabled: v.enabled, x: v.x, y: v.x.sublist(0, 2), z: v.z),
          store.value(in0.id),
          v.x.first,
        );
        live = (0, p.col);
      }
    }
    return (
      name: d.name ?? TablesStrings.table(id),
      enabled: v.enabled,
      across: d.input0Name ?? in0?.name,
      down: d.isMap ? (d.input1Name ?? links[d.input1LinkId]?.name) : null,
      columns: [for (final x in v.x) axis(x)],
      rows: d.isMap ? [for (final y in v.y) axis(y)] : const [],
      cells: [for (final z in v.z) formatDecimals(z, f.min, f.max)],
      shades: [for (final z in v.z) z.isFinite ? (hi > lo ? (z - lo) / (hi - lo) : 0.5) : double.nan],
      live: live,
    );
  }

  void _tick() {
    final key = (_session.calibration, _session.live?.version, _session.state.phase);
    if (key != _seen) {
      _seen = key;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}
