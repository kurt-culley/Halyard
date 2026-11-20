import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'grid_selection.dart';
import 'strings.dart';
import 'table_presets.dart';

typedef TableEntry = ({int id, String name, String category});

typedef TableView = ({
  String name,
  bool enabled,
  bool isMap,
  String? across,
  String? down,
  String? output,
  List<String> columns,
  List<String> rows,
  List<String> cells,
  List<double> shades,
  List<double> x,
  List<List<double>> lines,
  (double, double)? live,
  bool unstored,
});

/// What the right-click menu offers for the selection and the cell clicked, as the original's menu decided.
typedef TableMenu = ({
  List<int> columnAxis,
  List<int> rowAxis,
  Map<int, List<int>> byRow,
  Map<int, List<int>> byColumn,
  bool onAxis,
  ({bool columns, List<int> indexes})? marked,
});

/// The ECU's tables by category; the chosen one as text, shades and lines with its live place; and the
/// original's grid editing over it, each change sent through the write gate.
class TablesController extends ChangeNotifier {
  TablesController(this._session, this._gate, this._policy, [AppStorage? storage])
    : presets = storage == null ? null : TablePresets(storage) {
    presets?.load().then((_) => notifyListeners()).ignore();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  final Session _session;
  final WriteGate _gate;
  final SwitchablePolicy _policy;
  late final Timer _timer;

  int? selected;
  GridSelection? selection;
  String? message;
  String filter = '';
  bool follow = false;
  int smoothRadius = 1;

  /// The user's preset files; null without app storage.
  final TablePresets? presets;

  /// Decimal places for every table, or null for each table's own (the original's one display setting).
  static int? decimals;

  /// Value indexes marked tuned, by table: the original kept these with the table, not the ECU.
  final _tuned = <int, Set<int>>{};

  /// Axis cells marked for interpolation.
  (int, int)? markStart, markEnd;

  /// An axis copied with "Copy … to clipboard", shared between tables as the original's was.
  static Float32List? _axisClipboard;

  Object? _seen;

  bool get canEdit => !_policy.readOnly;
  bool get isOnline => _session.calibration != null && _session.state.phase == SessionPhase.online;
  bool get hasAxisClipboard => _axisClipboard != null;

  TableDef? get _def => selected == null ? null : _session.calibration?.definition.tables[selected];
  TableValues? get _values => selected == null ? null : _session.calibration?.tables[selected];

  List<TableEntry> get tables {
    final cal = _session.calibration;
    if (cal == null) return const [];
    final f = filter.toLowerCase();
    final list =
        [
            for (final t in cal.definition.tables.values)
              (id: t.id, name: t.name ?? TablesStrings.table(t.id), category: t.category ?? TablesStrings.other),
          ].where((t) => f.isEmpty || t.name.toLowerCase().contains(f) || t.category.toLowerCase().contains(f)).toList()
          ..sort((a, b) => a.category == b.category ? a.name.compareTo(b.name) : a.category.compareTo(b.category));
    return list;
  }

  void setFilter(String v) {
    filter = v;
    notifyListeners();
  }

  void select(int id) {
    selected = id;
    final d = _def!;
    selection = GridSelection(d.isMap ? d.rows : 1, d.cols)..setCurrentCell(1, 1);
    markStart = markEnd = null;
    message = null;
    notifyListeners();
  }

  void deselect() {
    selected = null;
    selection = null;
    notifyListeners();
  }

  Set<int> get tuned => _tuned[selected] ?? const {};

  // ---------------------------------------------------------------- selection

  void press((int, int) c, {bool shift = false, bool ctrl = false, bool right = false}) {
    selection?.mouseDown(c, shift: shift, ctrl: ctrl, right: right);
    notifyListeners();
  }

  void drag((int, int) c) {
    selection?.mouseDrag(c);
    notifyListeners();
  }

  void release() => selection?.mouseUp();

  void arrow(int dRow, int dCol, {bool shift = false}) {
    selection?.arrow(dRow, dCol, shift: shift);
    notifyListeners();
  }

  void selectAll() {
    selection?.selectAllValues();
    notifyListeners();
  }

  void toggleFollow() {
    follow = !follow;
    notifyListeners();
  }

  void setRadius(int r) {
    smoothRadius = r.clamp(0, 8);
    notifyListeners();
  }

  // ---------------------------------------------------------------- edits

  /// The text a single selected cell shows, for the "Set value" box.
  String? get singleText {
    final s = selection;
    if (s == null || s.count != 1) return null;
    final (r, c) = s.selected.first;
    return _cellText(r, c);
  }

  double? _get(TableValues v, int r, int c) {
    if (r == 0 && c == 0) return null;
    if (r == 0) return v.x[c - 1];
    if (c == 0) return v.y[r - 1];
    return v.z[(r - 1) * v.x.length + (c - 1)];
  }

  void _put(TableValues v, int r, int c, double value) {
    final f = fround(value);
    if (r == 0) {
      v.x[c - 1] = f;
    } else if (c == 0) {
      v.y[r - 1] = f;
    } else {
      v.z[(r - 1) * v.x.length + (c - 1)] = f;
    }
  }

  /// Runs [change] on a copy of the table, then sets and sends what changed.
  Future<void> _edit(void Function(TableValues v) change) async {
    final id = selected, v = _values;
    if (id == null || v == null || !canEdit) return;
    final copy = v.copy();
    change(copy);
    _gate.setTable(id, copy);
    notifyListeners();
    await _report(_gate.saveTable(id));
  }

  /// Moves every selected cell by [delta]; with a smooth radius, value cells drag their neighbours along.
  Future<void> step(double delta) => _edit((v) {
    final cells = selection!.selected.toList();
    for (final (r, c) in cells) {
      final old = _get(v, r, c);
      if (old != null) _put(v, r, c, fround(old + delta));
    }
    dragAround(
      v,
      [
        for (final (r, c) in cells)
          if (r > 0 && c > 0) (r - 1, c - 1),
      ],
      delta,
      smoothRadius,
    );
  });

  double get increment => fround(_def?.increment ?? 0.1);

  Future<void> stepBy(int direction, {bool fine = false}) =>
      step(direction * (fine ? fround(increment / 10) : increment));

  /// Sets every selected cell to the value in [text]; false when it isn't a number.
  Future<bool> setValue(String text) async {
    final v = _parse(text);
    if (v == null) {
      message = TablesStrings.notNumber;
      notifyListeners();
      return false;
    }
    await _edit((t) {
      for (final (r, c) in selection!.selected) {
        if (r != 0 || c != 0) _put(t, r, c, v);
      }
    });
    return true;
  }

  /// Applies a formula to every selected cell; false when it isn't one.
  Future<bool> applyFormula(String text) async {
    final f = TableFormula.parse(text);
    if (!f.isValid) {
      message = TablesStrings.notFormula;
      notifyListeners();
      return false;
    }
    await _edit((t) {
      for (final (r, c) in selection!.selected) {
        final old = _get(t, r, c);
        if (old != null) _put(t, r, c, f.apply(old));
      }
    });
    return true;
  }

  Future<void> smooth() => _edit(
    (v) => smoothCells(v, [
      for (final (r, c) in selection!.selected)
        if (r > 0 && c > 0) (r - 1, c - 1),
    ]),
  );

  /// T toggles the tuned mark of each selected value; U clears it.
  void markTuned({bool clear = false}) {
    final id = selected, v = _values, s = selection;
    if (id == null || v == null || s == null) return;
    final set = _tuned[id] ??= {};
    for (final (r, c) in s.selected) {
      if (r == 0 || c == 0) continue;
      final i = (r - 1) * v.x.length + (c - 1);
      if (clear || set.contains(i)) {
        set.remove(i);
      } else {
        set.add(i);
      }
    }
    notifyListeners();
  }

  /// Ctrl+C: the selected cells (not the corner) by row then column, tabs between, CR LF between rows.
  Future<void> copy() async {
    final cells = (selection?.selected.where((c) => c != (0, 0)).toList() ?? [])
      ..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    if (cells.isEmpty) return;
    final out = StringBuffer();
    var row = cells.first.$1;
    for (final (r, c) in cells) {
      if (out.isNotEmpty) out.write(r == row ? '\t' : '\r\n');
      row = r;
      out.write(_cellText(r, c));
    }
    await Clipboard.setData(ClipboardData(text: out.toString()));
  }

  /// Ctrl+V: one value into every selected cell, else the block from the top left of the selection.
  Future<void> paste() async {
    final block = parseCellBlock((await Clipboard.getData(Clipboard.kTextPlain))?.text);
    final s = selection;
    if (block == null || s == null || s.count == 0) return;
    await _edit((v) {
      void into(int r, int c, String text) {
        if (r < 0 || r >= s.rowCount || c < 0 || c >= s.colCount || (r == 0 && c == 0)) return;
        if (c == 0 && !_def!.isMap) return;
        final value = _parse(text);
        if (value != null) _put(v, r, c, value);
      }

      if (isSingleCell(block)) {
        for (final (r, c) in s.selected) {
          into(r, c, block[0][0]);
        }
      } else {
        final r0 = s.selected.map((c) => c.$1).reduce((a, b) => a < b ? a : b);
        final c0 = s.selected.map((c) => c.$2).reduce((a, b) => a < b ? a : b);
        for (final (i, line) in block.indexed) {
          for (final (j, text) in line.indexed) {
            into(r0 + i, c0 + j, text);
          }
        }
      }
    });
  }

  // ---------------------------------------------------------------- the right-click menu

  TableMenu menu((int, int)? clicked) {
    final x = <int>[], y = <int>[];
    final byRow = <int, List<int>>{}, byCol = <int, List<int>>{};
    for (final (r, c) in selection?.selected ?? const <(int, int)>{}) {
      if (r == 0 && c != 0) {
        x.add(c);
      } else if (c == 0 && r != 0) {
        y.add(r);
      } else if (r != 0 && c != 0) {
        (byRow[r] ??= []).add(c);
        (byCol[c] ??= []).add(r);
      }
    }
    byRow.removeWhere((_, v) => !isContinuousRegion(v));
    byCol.removeWhere((_, v) => !isContinuousRegion(v));
    return (
      columnAxis: isContinuousRegion(x) ? x : const [],
      rowAxis: isContinuousRegion(y) ? y : const [],
      byRow: byRow,
      byColumn: byCol,
      onAxis: clicked != null && clicked != (0, 0) && (clicked.$1 == 0 || clicked.$2 == 0),
      marked: _marked,
    );
  }

  ({bool columns, List<int> indexes})? get _marked {
    final a = markStart, b = markEnd;
    if (a == null || b == null) return null;
    List<int> span(int p, int q) => [for (var i = p < q ? p : q; i <= (p > q ? p : q); i++) i];
    if (a.$1 == 0 && b.$1 == 0) {
      final ix = span(a.$2, b.$2);
      return isContinuousRegion(ix) ? (columns: true, indexes: ix) : null;
    }
    if (a.$2 == 0 && b.$2 == 0) {
      final ix = span(a.$1, b.$1);
      return isContinuousRegion(ix) ? (columns: false, indexes: ix) : null;
    }
    return null;
  }

  bool _sameAxis((int, int) a, (int, int) b) => (a.$1 == 0) == (b.$1 == 0);

  void setMark((int, int) c, {required bool start}) {
    if (c == (0, 0) || (c.$1 != 0 && c.$2 != 0)) return;
    if (start) {
      if (markEnd != null && !_sameAxis(markEnd!, c)) markEnd = null;
      markStart = c;
    } else {
      if (markStart != null && !_sameAxis(markStart!, c)) markStart = null;
      markEnd = c;
    }
    notifyListeners();
  }

  void clearMarks() {
    markStart = markEnd = null;
    notifyListeners();
  }

  /// Spreads an axis evenly between the first and last of three or more [indexes] (grid positions).
  Future<void> interpolateAxisCells(bool columns, List<int> indexes) async {
    if (indexes.length < 3) return;
    final s = [...indexes]..sort();
    await _edit((v) => interpolateAxis(columns ? v.x : v.y, s.first - 1, s.last - 1));
  }

  Future<void> interpolateMarked() async {
    final m = _marked;
    if (m != null) await interpolateAxisCells(m.columns, m.indexes);
  }

  /// Each row (across) or column (down) between its first and last selected value, leaving tuned cells alone.
  Future<void> interpolateValues(Map<int, List<int>> groups, {required bool across}) async {
    if (groups.isEmpty) return;
    final keep = tuned;
    await _edit((v) {
      for (final MapEntry(key: k, value: ix) in groups.entries) {
        final s = [...ix]..sort();
        if (across) {
          interpolateRow(v, k - 1, s.first - 1, s.last - 1, tuned: keep);
        } else {
          interpolateColumn(v, k - 1, s.first - 1, s.last - 1, tuned: keep);
        }
      }
    });
  }

  void copyAxis(bool columns) {
    final v = _values;
    if (v == null) return;
    _axisClipboard = Float32List.fromList(columns ? v.x : v.y);
    notifyListeners();
  }

  /// Pastes the copied axis where it fits.
  Future<void> pasteAxis(bool columns) async {
    final a = _axisClipboard;
    if (a == null) return;
    await _edit((v) {
      final to = columns ? v.x : v.y;
      if (a.length == to.length) to.setAll(0, a);
    });
  }

  void setDecimals(int? d) {
    decimals = d;
    notifyListeners();
  }

  // ---------------------------------------------------------------- presets

  List<PresetRow> presetRows(String search) =>
      selected == null ? const [] : presets?.rows(selected!, search) ?? const [];

  /// Loads a preset's axes and values into the table and sends it, as the original did; false when it doesn't fit.
  Future<bool> loadPreset(TablePreset p) async {
    final v = _values;
    if (v == null || !canEdit) return false;
    final y = p.input1.isEmpty ? v.y : p.input1;
    if (p.input0.length != v.x.length || y.length != v.y.length || p.output.length != v.z.length) {
      message = TablesStrings.presetFailed;
      notifyListeners();
      return false;
    }
    await _edit((t) {
      t.x.setAll(0, p.input0);
      t.y.setAll(0, y);
      t.z.setAll(0, p.output);
    });
    return true;
  }

  Future<void> addPresetFile(String name, String text) async {
    try {
      await presets?.addFile(name, text);
      message = null;
    } on PresetError catch (e) {
      message = TablesStrings.presetUnreadable(e.message);
    }
    notifyListeners();
  }

  Future<void> saveAsPreset(String name) async {
    final d = _def, v = _values;
    if (d == null || v == null || presets == null || name.trim().isEmpty) return;
    try {
      await presets!.save(name, d, v);
      message = TablesStrings.presetSaved;
    } on PresetError {
      message = TablesStrings.presetSize;
    }
    notifyListeners();
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

  double? _parse(String text) {
    try {
      return parseNetSingle(text.trim());
    } on Object {
      return null;
    }
  }

  // ---------------------------------------------------------------- the view

  String _cellText(int r, int c) {
    final d = _def, v = _values;
    if (d == null || v == null || (r == 0 && c == 0)) return '';
    if (r == 0) return formatDecimals(v.x[c - 1], 0, 2);
    if (c == 0) return formatDecimals(v.y[r - 1], 0, 2);
    final f = tableDecimals(d, _session.calibration!.definition.links[d.outputLinkId], decimals: decimals);
    return formatDecimals(v.z[(r - 1) * v.x.length + (c - 1)], f.min, f.max);
  }

  TableView? get view {
    final cal = _session.calibration;
    final id = selected, d = _def, v = _values;
    if (cal == null || id == null || d == null || v == null) return null;
    final links = cal.definition.links;
    final out = links[d.outputLinkId];
    final f = tableDecimals(d, out, decimals: decimals);
    String axis(double x) => formatDecimals(x, 0, 2);
    final finite = v.z.where((z) => z.isFinite);
    final lo = finite.isEmpty ? 0.0 : finite.reduce((a, b) => a < b ? a : b);
    final hi = finite.isEmpty ? 1.0 : finite.reduce((a, b) => a > b ? a : b);
    final cols = v.x.length;
    final nRows = d.isMap ? v.y.length : 1;
    return (
      name: d.name ?? TablesStrings.table(id),
      enabled: v.enabled,
      isMap: d.isMap,
      across: d.input0Name ?? links[d.input0LinkId]?.name,
      down: d.isMap ? (d.input1Name ?? links[d.input1LinkId]?.name) : null,
      output: d.outputName ?? out?.name,
      columns: [for (final x in v.x) axis(x)],
      rows: d.isMap ? [for (final y in v.y) axis(y)] : const [],
      cells: [for (final z in v.z.take(nRows * cols)) formatDecimals(z, f.min, f.max)],
      shades: [
        for (final z in v.z.take(nRows * cols)) z.isFinite ? (hi > lo ? (z - lo) / (hi - lo) : 0.5) : double.nan,
      ],
      x: v.x.toList(),
      lines: [for (var r = 0; r < nRows; r++) v.z.sublist(r * cols, (r + 1) * cols).toList()],
      live: _live(d, v),
      unstored: _gate.isUnstored(id),
    );
  }

  (double, double)? _live(TableDef d, TableValues v) {
    final store = _session.live;
    final links = _session.calibration!.definition.links;
    final in0 = links[d.input0LinkId];
    if (store == null || in0 == null || v.x.length < 2) return null;
    if (d.isMap) {
      final in1 = links[d.input1LinkId];
      if (in1 == null || v.y.length < 2) return null;
      final p = tablePosition(v, store.value(in0.id), store.value(in1.id));
      return (p.y, p.x);
    }
    final p = tablePosition(
      TableValues(enabled: v.enabled, x: v.x, y: v.x.sublist(0, 2), z: v.z),
      store.value(in0.id),
      v.x.first,
    );
    return (0, p.x);
  }

  void _tick() {
    final key = (_session.calibration, _session.live?.version, _session.state.phase);
    if (key == _seen) return;
    _seen = key;
    if (follow && selection != null && _def != null && _values != null) {
      final l = _live(_def!, _values!);
      if (l != null) selection!.setCurrentCell(l.$1.round() + 1, l.$2.round() + 1);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}
