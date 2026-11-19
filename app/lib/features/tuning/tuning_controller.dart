import 'dart:async';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'strings.dart';

typedef Choice = ({int id, String name});

/// The fuel tuning assistant over the ECU's tables and live history (or a CSV log). Analysis only suggests;
/// applying writes the chosen cells through the write gate and sends the table, as the original saved it.
class TuningController extends ChangeNotifier {
  TuningController(this._session, this._gate, this._policy) {
    _sub = _session.states.listen((_) {
      if (ve == null) _defaults();
      notifyListeners();
    });
    _defaults();
  }

  final Session _session;
  final WriteGate _gate;
  final SwitchablePolicy _policy;
  late final StreamSubscription<SessionState> _sub;

  int? ve, target, rpm, load, measured;
  MeasurementMode mode = MeasurementMode.afr;
  double stoich = 14.7, confidence = 55, stability = 20, maxChange = 10;
  int minHits = 4;

  CsvLog? csvLog;
  String? csvName;
  int csvRpm = -1, csvLoad = -1, csvMeasured = -1;
  bool useCsv = false;

  TuningResult? result;
  (int, int)? cell;
  String status = TuningStrings.intro;

  bool get isOnline => _session.calibration != null && _session.state.phase == SessionPhase.online;
  bool get canApply => isOnline && !_policy.readOnly;

  Definition? get _def => _session.calibration?.definition;

  /// Maps only: the assistant needs two axes.
  List<Choice> get maps => [
    for (final t in _def?.tables.values ?? const <TableDef>[])
      if (t.isMap) (id: t.id, name: t.name ?? 'Table ${t.id}'),
  ];

  List<Choice> get links => [
    for (final l in _def?.links.values ?? const <LinkDef>[]) (id: l.id, name: l.name ?? 'Link ${l.id}'),
  ];

  List<String> get columns => csvLog?.headers ?? const [];

  static bool _has(String? v, List<String> needles) {
    final t = (v ?? '').toLowerCase();
    return needles.any(t.contains);
  }

  static bool _is(String? v, String e) => (v ?? '').trim().toLowerCase() == e.toLowerCase();

  /// The original's guesses: its own table and channel names first, then by what the names contain.
  void _defaults() {
    final d = _def;
    if (d == null) return;
    final tables = d.tables.values.where((t) => t.isMap).toList();
    final links = d.links.values.toList();
    final veT =
        tables.where((t) => _is(t.name, 'Inj. Base VE (1)') || _is(t.name, 'Inj. Base VE')).firstOrNull ??
        tables.where((t) => isVeTable(t, d.links[t.outputLinkId])).firstOrNull ??
        tables.where((t) => _has(t.name, ['base ve', 've', 'fuel'])).firstOrNull ??
        tables.firstOrNull;
    ve = veT?.id;
    target =
        (d.tables.values.where((t) => _is(t.name, 'Inj. Target AFR')).firstOrNull ??
                d.tables.values.where((t) => _has(t.name, ['target afr', 'afr target', 'lambda target'])).firstOrNull ??
                d.tables.values
                    .where((t) => _has(t.name, ['afr', 'lambda']) && !_has(t.name, ['error', 'err']))
                    .firstOrNull)
            ?.id;
    rpm =
        (links.where((l) => _is(l.name, 'RPM')).firstOrNull ??
                links.where((l) => l.dataKey == 'RPM').firstOrNull ??
                links.where((l) => _has(l.name, ['rpm', 'engine speed'])).firstOrNull)
            ?.id;
    load =
        (links.where((l) => _is(l.name, 'Primary Load (%)') || _is(l.name, 'Primary Load')).firstOrNull ??
                (veT == null ? null : d.links[veT.input1LinkId]) ??
                links.where((l) => _has(l.name, ['primary load'])).firstOrNull ??
                links.where((l) => l.dataKey == 'MAP' || l.dataKey == 'TPS').firstOrNull ??
                links.where((l) => _has(l.name, ['map', 'tps', 'load'])).firstOrNull)
            ?.id;
    final m =
        links.where((l) => _is(l.name, 'Lambda Curr AFR 1')).firstOrNull ??
        links.where((l) => _has(l.name, ['actual afr', 'wideband afr'])).firstOrNull ??
        links.where((l) => _has(l.name, ['afr']) && !_has(l.name, ['err', 'error', 'target'])).firstOrNull ??
        links
            .where((l) => _has(l.name, ['wideband lambda', 'lambda']) && !_has(l.name, ['target', 'err', 'error']))
            .firstOrNull;
    measured = m?.id;
    if (m != null && _has(m.name, ['lambda']) && !_has(m.name, ['afr'])) mode = MeasurementMode.lambda;
  }

  void update(void Function(TuningController c) f) {
    f(this);
    notifyListeners();
  }

  void openCsv(String name, String text) {
    try {
      final log = readCsvLog(text);
      if (log.headers.isEmpty || log.rows.isEmpty) {
        status = TuningStrings.noRows;
        notifyListeners();
        return;
      }
      csvLog = log;
      csvName = name;
      useCsv = true;
      String? n(int? id) => id == null ? null : _def?.links[id]?.name;
      csvRpm = findTuningColumn(log.headers, ['RPM', 'Engine Speed', n(rpm)]);
      csvLoad = findTuningColumn(log.headers, ['Primary Load (%)', 'Primary Load', 'Load', 'MAP', n(load)]);
      csvMeasured = findTuningColumn(log.headers, ['Lambda Curr AFR 1', 'Actual AFR', 'AFR', 'Lambda', n(measured)]);
    } on FormatException catch (e) {
      status = TuningStrings.unreadable(e.message);
    }
    notifyListeners();
  }

  void analyse() {
    final cal = _session.calibration;
    if (cal == null) return;
    TuningTable? table(int? id) {
      final d = id == null ? null : cal.definition.tables[id];
      final v = id == null ? null : cal.tables[id];
      return d == null || v == null ? null : TuningTable.of(d, v);
    }

    final settings = TuningSettings(
      ve: table(ve),
      target: table(target),
      mode: mode,
      stoichAfr: stoich,
      minimumHits: minHits,
      confidenceThreshold: confidence / 100,
      stabilityTolerancePercent: stability,
      maxCorrectionPercent: maxChange,
    );
    final List<LogSample> samples;
    if (useCsv && csvLog != null) {
      samples = csvTuningSamples(csvLog!, csvRpm, csvLoad, csvMeasured);
    } else {
      final live = _session.live;
      if (rpm == null || load == null || measured == null || live == null) {
        status = TuningStrings.chooseChannels;
        notifyListeners();
        return;
      }
      samples = liveTuningSamples(live, rpm!, load!, measured!);
    }
    final r = result = analyseTuning(settings, samples);
    final p = r.problem;
    status = p != null
        ? TuningStrings.problem(p, csv: useCsv)
        : TuningStrings.done(r.used, r.eligible.length, useCsv ? csvName : null);
    if (p != null) result = null;
    notifyListeners();
  }

  void select(int row, int col) {
    cell = (row, col);
    notifyListeners();
  }

  TuningSuggestion? get selected {
    final r = result, c = cell;
    if (r == null || c == null || c.$1 >= r.suggestions.length || c.$2 >= r.suggestions[c.$1].length) return null;
    return r.suggestions[c.$1][c.$2];
  }

  List<TuningSuggestion> get selectedForApply {
    final s = selected;
    return s != null && s.weightedHits > 0 ? [s] : const [];
  }

  /// Rounded to a tenth (half away from zero), set through the gate, the table sent, then analysed again.
  Future<void> apply(List<TuningSuggestion> items) async {
    final id = ve, v = id == null ? null : _session.calibration?.tables[id];
    if (id == null || v == null || items.isEmpty || !canApply) return;
    for (final s in items) {
      final r = (s.suggestedValue.abs() * 10 + 0.5).floorToDouble() / 10 * s.suggestedValue.sign;
      _gate.setTableCell(id, TableElement.values, s.row * v.x.length + s.col, r);
    }
    final w = await _gate.saveTable(id);
    analyse();
    final failed = w.failed;
    status = failed == null
        ? TuningStrings.applied(items.length)
        : 'The ECU did not accept the change (${failed.failure.name}).';
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}
