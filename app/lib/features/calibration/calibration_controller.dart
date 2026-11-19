import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'strings.dart';

/// The candidates of one item of the ECU's calibration, as the original's review list grouped them.
final class ReviewItem {
  ReviewItem(this.id, this.name, this.candidates, {required this.isTable})
    : table = candidates.where((c) => c.kind == CandidateKind.table).firstOrNull;

  final int id;
  final String name;
  final List<ImportCandidate> candidates;
  final ImportCandidate? table;
  final bool isTable;

  bool get driverMissing => !isTable && candidates.every((c) => c.kind == CandidateKind.warning);
  bool get blocked => driverMissing || (table != null && !table!.importable);
  bool get needsAttention => blocked || candidates.any((c) => !c.importable);
  bool get hasChanges => candidates.any((c) => c.isChanged);
  bool get selectable => candidates.any((c) => c.importable && c.isChanged);
  bool get checked => candidates.any((c) => c.importable && c.selected);

  void setChecked(bool v) {
    for (final c in candidates) {
      c.selected = v && c.importable && c.isChanged;
    }
  }

  String get badge {
    if (driverMissing) return CalibrationStrings.notInFile;
    final t = table;
    if (t != null && !t.importable) return CalibrationStrings.sizeMismatch;
    if (t != null) return CalibrationStrings.tableBadge(t.changedCells, t.changedAxis, t.enabledChanged);
    final changed = candidates.where((c) => c.importable && c.isChanged).length;
    final kept = candidates.where((c) => !c.importable).length;
    return CalibrationStrings.itemBadge(changed, kept);
  }
}

enum ReviewFilter { all, drivers, tables, attention }

/// Saving the ECU's calibration to a file, and loading one: comparing it with the ECU's item by item, choosing what
/// to keep, and sending the result through the write gate.
class CalibrationController extends ChangeNotifier {
  CalibrationController(this._session, this._gate, this._policy, this._saver) {
    _sub = _session.states.listen((_) => notifyListeners());
  }

  final Session _session;
  final WriteGate _gate;
  final SwitchablePolicy _policy;
  final FileSaver _saver;
  late final StreamSubscription<SessionState> _sub;

  String? message;
  bool busy = false;

  String? fileName;
  Calibration? _source;
  ImportAnalysis? analysis;
  List<ReviewItem> items = const [];
  ReviewFilter filter = ReviewFilter.all;
  bool showUnchanged = false;
  final expanded = <int>{};

  bool get isOnline => _session.calibration != null && _session.state.phase == SessionPhase.online;
  bool get canSend => isOnline && !_policy.readOnly;
  String get notes => _session.calibration?.notes ?? '';

  set notes(String v) => _session.calibration?.notes = v;

  Future<void> save() async {
    final cal = _session.calibration, info = _session.ecu;
    if (cal == null) return;
    final name = backupCalibrationFileName(info ?? cal.definition.info, DateTime.now());
    final ok = await _saver.save(name, Uint8List.fromList(utf8.encode(writeCalibrationFile(cal))));
    message = ok ? CalibrationStrings.saved : null;
    notifyListeners();
  }

  /// Reads a calibration file and compares it with the ECU's calibration.
  void open(String name, String text) {
    message = null;
    try {
      _source = readDeviceFile(text).calibration;
    } on Object catch (e) {
      message = CalibrationStrings.unreadable(e is DeviceFileError ? e.message : '$e');
      _source = null;
      analysis = null;
      items = const [];
      notifyListeners();
      return;
    }
    fileName = name;
    expanded.clear();
    _analyse();
    notifyListeners();
  }

  void _analyse() {
    final a = analysis = analyseImport(_session.calibration, _source);
    items = _build(a);
  }

  void close() {
    _source = null;
    analysis = null;
    items = const [];
    fileName = null;
    notifyListeners();
  }

  /// Grouped by target item in the analysis' order; named by the ECU's definition.
  List<ReviewItem> _build(ImportAnalysis a) {
    final def = _session.calibration?.definition;
    final groups = <int, List<ImportCandidate>>{};
    for (final c in a.candidates) {
      (groups[c.targetId] ??= []).add(c);
    }
    return [
      for (final MapEntry(key: id, value: cs) in groups.entries)
        ReviewItem(
          id,
          [def?.tables[id]?.name, def?.drivers[id]?.name].nonNulls.where((n) => n.trim().isNotEmpty).firstOrNull ??
              CalibrationStrings.item(id),
          cs,
          isTable: cs.any((c) => c.kind == CandidateKind.table) || (def?.tables.containsKey(id) ?? false),
        ),
    ];
  }

  /// Settings first; hidden when unchanged unless asked; then by the filter.
  List<ReviewItem> get visible => [...items.where((i) => !i.isTable), ...items.where((i) => i.isTable)].where((i) {
    if (!showUnchanged && !i.hasChanges && !i.needsAttention) return false;
    return switch (filter) {
      ReviewFilter.all => true,
      ReviewFilter.drivers => !i.isTable,
      ReviewFilter.tables => i.isTable,
      ReviewFilter.attention => i.needsAttention,
    };
  }).toList();

  String get summary {
    final differ = items.where((i) => i.hasChanges || i.needsAttention).length;
    final cells = items
        .where((i) => i.table != null && i.table!.importable)
        .fold(0, (s, i) => s + i.table!.changedCells + i.table!.changedAxis);
    final params = (analysis?.candidates ?? const <ImportCandidate>[])
        .where((c) => c.importable && c.isChanged && c.kind != CandidateKind.table)
        .length;
    final attention = items.where((i) => i.needsAttention).length;
    return CalibrationStrings.summary(differ, cells, params, attention);
  }

  int get checkedCount => items.where((i) => i.checked).length;

  void setFilter(ReviewFilter f) {
    filter = f;
    notifyListeners();
  }

  void setShowUnchanged(bool v) {
    showUnchanged = v;
    notifyListeners();
  }

  void check(ReviewItem i, bool v) {
    i.setChecked(v);
    notifyListeners();
  }

  void checkAll(bool v) {
    for (final i in visible) {
      i.setChecked(v);
    }
    notifyListeners();
  }

  void toggleCandidate(ImportCandidate c) {
    if (!c.importable || !c.isChanged) return;
    c.selected = !c.selected;
    notifyListeners();
  }

  void toggleExpanded(int id) {
    if (!expanded.remove(id)) expanded.add(id);
    notifyListeners();
  }

  String reason(ImportCandidate c) => CalibrationStrings.reason(c, (id, index) {
    final d = _source?.definition.drivers[id];
    if (d == null || index < 0 || index >= d.params.length) return '';
    return d.params[index].displayName ?? d.params[index].name ?? '';
  });

  /// Under a table: how far its cells move, or why it can't come across.
  String tableDetail(ImportCandidate t) {
    if (t.importable && t.changedCells > 0) {
      return CalibrationStrings.cellDeltas(t.minCellDelta, t.maxCellDelta);
    }
    return reason(t);
  }

  String candidateName(ImportCandidate c) {
    final def = _session.calibration?.definition;
    final d = def?.drivers[c.targetId];
    if (d != null && c.kind == CandidateKind.driverParameter && c.targetIndex >= 0 && c.targetIndex < d.params.length) {
      return d.params[c.targetIndex].displayName ?? d.params[c.targetIndex].name ?? '';
    }
    if (d != null && c.kind == CandidateKind.driverInput) return d.inputNames?.elementAtOrNull(c.targetIndex) ?? '';
    if (d != null && c.kind == CandidateKind.driverOutput) return d.outputNames?.elementAtOrNull(c.targetIndex) ?? '';
    return '';
  }

  /// The selected items applied onto the ECU's calibration, sent and stored; the ECU's read-back becomes the
  /// calibration here.
  Future<void> send() async {
    final target = _session.calibration, source = _source, a = analysis;
    if (target == null || source == null || a == null || !canSend) return;
    final reviewed = applyImport(target, source, a.candidates);
    final ids = {
      for (final c in a.candidates)
        if (c.selected && c.importable) c.targetId,
    };
    final only = Calibration(
      reviewed.definition,
      tables: {
        for (final id in ids)
          if (reviewed.tables[id] case final v?) id: v,
      },
      drivers: {
        for (final id in ids)
          if (reviewed.drivers[id] case final v?) id: v,
      },
      notes: reviewed.notes,
    );
    busy = true;
    message = null;
    notifyListeners();
    final r = await _gate.sendCalibration(only);
    busy = false;
    final failed = r.failed;
    message = failed == null ? CalibrationStrings.sent : CalibrationStrings.failed(failed.failure.name);
    if (failed == null) _analyse();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}
