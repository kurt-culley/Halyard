/// Bringing a calibration file onto the connected ECU's definition: applying the file's values to a definition
/// (U10a F01), comparing it with the ECU's calibration item by item (U10b analysis), and applying the items the user
/// keeps. Candidates carry typed reasons; the app words them and decides their order.
library;

import '../definition/definition.dart';
import '../wire/bytes.dart' show fround;
import 'calibration.dart';

/// [file]'s values applied onto [fresh] (a calibration of the target definition with its defaults), item by item by
/// id. An item whose shape differs keeps the definition's values; the original read a driver of another shape anyway
/// and stored misaligned values (docs/behaviour-changes.md). The file's notes come along.
Calibration applyCalibrationFile(Calibration fresh, Calibration file) {
  final out = fresh.copy()..notes = file.notes;
  final d = out.definition, fd = file.definition;
  for (final e in file.tables.entries) {
    final t = d.tables[e.key];
    if (t == null) continue;
    try {
      out.tables[e.key] = parseTableBlob(t, tableBlob(fd.tables[e.key]!, e.value), out.tables[e.key]);
    } on BlobError {
      // keeps the definition's values
    }
  }
  for (final e in file.drivers.entries) {
    final dr = d.drivers[e.key];
    if (dr == null) continue;
    try {
      out.drivers[e.key] = parseDriverBlob(dr, driverBlob(fd.drivers[e.key]!, e.value), out.drivers[e.key]);
    } on BlobError {
      // keeps the definition's values
    }
  }
  return out;
}

enum CandidateKind { driverParameter, driverInput, driverOutput, table, warning }

enum MatchType { exact, nameMatch, reordered, missing, incompatible, manualMap, converted, derived }

enum CandidateReason {
  /// The target or the source calibration is missing.
  calibrationMissing,
  missingDriver,
  exactParameter,
  reorderedParameter,

  /// Seeded from the source parameter it was split out of ([ImportCandidate.sourceIndex]).
  seededParameter,
  parameterNotInFile,

  /// A link the target can't change differs in the file.
  fixedLinkDiffers,
  linkImportable,
  linkUnavailable,
  missingTable,

  /// A 16-point curve reduced to its first and last points.
  condensed,

  /// A 2-point line spread over 16 points.
  expanded,

  /// A 16x16 map interpolated to 8x8.
  rescaled,

  /// Same shape: copied directly (identical when nothing changed).
  sameShape,
  differentSize,
}

final class ImportCandidate {
  ImportCandidate(
    this.kind,
    this.matchType,
    this.reason, {
    required this.importable,
    required this.isChanged,
    this.targetId = 0,
    this.sourceId = 0,
    this.targetIndex = -1,
    this.sourceIndex = -1,
    this.valueDelta,
    this.changedCells = 0,
    this.changedAxis = 0,
    this.minCellDelta = 0,
    this.maxCellDelta = 0,
    this.enabledChanged = false,
  }) : safeDefault = importable && isChanged,
       selected = importable && isChanged;

  final CandidateKind kind;
  final MatchType matchType;
  final CandidateReason reason;
  final bool importable, isChanged, safeDefault;

  /// Whether the user keeps it; starts as [safeDefault].
  bool selected;
  final int targetId, sourceId, targetIndex, sourceIndex;

  /// Source minus target, for changed number parameters.
  final double? valueDelta;
  final int changedCells, changedAxis;
  final double minCellDelta, maxCellDelta;
  final bool enabledChanged;
}

final class ImportAnalysis {
  ImportAnalysis(this.sourceInfo, this.targetInfo);
  final DeviceInfo? sourceInfo, targetInfo;
  final candidates = <ImportCandidate>[];

  /// The file was made for another product, model or definition version.
  bool get hasDefinitionMismatch {
    bool same(String? a, String? b) => (a ?? '').toUpperCase() == (b ?? '').toUpperCase();
    final s = sourceInfo, t = targetInfo;
    return !(same(s?.productName, t?.productName) && same(s?.modelName, t?.modelName) && same(s?.version, t?.version));
  }

  bool get hasAnythingToReview => candidates.any((c) => c.isChanged || !c.importable);
}

// ---------------------------------------------------------------- names

/// Trimmed, lower-cased, runs of white space as one space.
String normalizeName(String? s) =>
    (s ?? '').trim().toLowerCase().split(RegExp('[ \t\r\n]')).where((x) => x.isNotEmpty).join(' ');

bool sameName(String? a, String? b) => normalizeName(a).toUpperCase() == normalizeName(b).toUpperCase();

/// A source link's id in the target: the same id when the target has it, else the target link with the same name,
/// else 0.
int resolveLinkId(Definition target, Definition source, int id) {
  if (target.link(id) != null) return id;
  final name = source.link(id)?.name;
  if (name == null || name.trim().isEmpty) return 0;
  for (final l in target.links.values) {
    if (sameName(l.name, name)) return l.id;
  }
  return 0;
}

// ---------------------------------------------------------------- table shapes

const _t1x16 = 0, _t16x16 = 2, _t1x2 = 4, _t8x8 = 5;
bool _is(TableDef t, int type, int rows, int cols) => t.type == type && t.rows == rows && t.cols == cols;
bool isSameShape(TableDef? t, TableDef? s) =>
    t != null && s != null && t.type == s.type && t.rows == s.rows && t.cols == s.cols;
bool isCondensable(TableDef? t, TableDef? s) => t != null && s != null && _is(t, _t1x2, 1, 2) && _is(s, _t1x16, 1, 16);
bool isExpandable(TableDef? t, TableDef? s) => t != null && s != null && _is(t, _t1x16, 1, 16) && _is(s, _t1x2, 1, 2);
bool isRescalable(TableDef? t, TableDef? s) => t != null && s != null && _is(t, _t8x8, 8, 8) && _is(s, _t16x16, 16, 16);

// ---------------------------------------------------------------- analysis

/// Parameters split out of an older one, by driver: new name to the name it was seeded from.
final _seeded = <int, Map<String, String>>{
  8198: {normalizeName('CL Min Duty'): 'PWM Min Duty', normalizeName('CL Max Duty'): 'PWM Max Duty'},
};

bool _paramCompatible(ParamDef a, ParamDef b) {
  bool ieq(String? x, String? y) => (x ?? '').toLowerCase() == (y ?? '').toLowerCase() && (x == null) == (y == null);
  if (!ieq(a.name, b.name) || a.type != b.type) return false;
  if (a.type == ParamType.comboBox) {
    final x = a.options ?? const [], y = b.options ?? const [];
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (!ieq(x[i].name, y[i].name) || x[i].id != y[i].id) return false;
    }
  }
  return true;
}

List<ParamDef> _params(DriverDef d) => d.params.length > d.configCount ? d.params.sublist(0, d.configCount) : d.params;

/// Compares [source] (a calibration file in its own definition) with [target] (the ECU's), driver by driver and
/// table by table, in definition order.
ImportAnalysis analyseImport(Calibration? target, Calibration? source) {
  final a = ImportAnalysis(source?.definition.info, target?.definition.info);
  if (target == null || source == null) {
    a.candidates.add(
      ImportCandidate(
        CandidateKind.warning,
        MatchType.incompatible,
        CandidateReason.calibrationMissing,
        importable: false,
        isChanged: true,
      ),
    );
    return a;
  }
  final td = target.definition, sd = source.definition;
  T? resolve<T extends Item>(Map<int, T> all, T t) {
    if (all[t.id] case final x?) return x;
    for (final x in all.values) {
      if (sameName(x.name, t.name)) return x;
    }
    return null;
  }

  for (final d in td.drivers.values) {
    _driver(a, target, source, d, resolve(sd.drivers, d));
  }
  for (final t in td.tables.values) {
    _table(a, target, source, t, resolve(sd.tables, t));
  }
  return a;
}

void _driver(ImportAnalysis a, Calibration target, Calibration source, DriverDef td, DriverDef? sd) {
  if (sd == null) {
    a.candidates.add(
      ImportCandidate(
        CandidateKind.warning,
        MatchType.missing,
        CandidateReason.missingDriver,
        importable: false,
        isChanged: true,
        targetId: td.id,
      ),
    );
    return;
  }
  final tps = _params(td), sps = _params(sd);
  final tv = target.drivers[td.id]!.config, sv = source.drivers[sd.id]!.config;
  final index = <String, List<int>>{};
  for (final (i, p) in sps.indexed) {
    index.putIfAbsent(normalizeName(p.name), () => []).add(i);
  }
  int compatible(ParamDef tp) {
    for (final i in index[normalizeName(tp.name)] ?? const <int>[]) {
      if (_paramCompatible(tp, sps[i])) return i;
    }
    return -1;
  }

  int seed(ParamDef tp) {
    final from = _seeded[td.id]?[normalizeName(tp.name)];
    if (from == null) return -1;
    for (final i in index[normalizeName(from)] ?? const <int>[]) {
      if (sps[i].type == tp.type && tp.type == ParamType.inputBox) return i;
    }
    return -1;
  }

  for (final (i, tp) in tps.indexed) {
    var j = compatible(tp);
    final seeded = j < 0;
    if (seeded) j = seed(tp);
    if (j < 0) {
      a.candidates.add(
        ImportCandidate(
          CandidateKind.driverParameter,
          MatchType.missing,
          CandidateReason.parameterNotInFile,
          importable: false,
          isChanged: true,
          targetId: td.id,
          sourceId: sd.id,
          targetIndex: i,
        ),
      );
      continue;
    }
    final changed = tv[i] != sv[j];
    a.candidates.add(
      ImportCandidate(
        CandidateKind.driverParameter,
        seeded ? MatchType.derived : (j != i ? MatchType.reordered : MatchType.exact),
        seeded
            ? CandidateReason.seededParameter
            : (j != i ? CandidateReason.reorderedParameter : CandidateReason.exactParameter),
        importable: true,
        isChanged: changed,
        targetId: td.id,
        sourceId: sd.id,
        targetIndex: i,
        sourceIndex: j,
        valueDelta: tp.type == ParamType.inputBox && changed ? fround(sv[j] - tv[i]) : null,
      ),
    );
  }
  _links(a, target, source, td, sd, input: true);
  _links(a, target, source, td, sd, input: false);
}

void _links(
  ImportAnalysis a,
  Calibration target,
  Calibration source,
  DriverDef td,
  DriverDef sd, {
  required bool input,
}) {
  final editable = input ? td.editableInputs : td.editableOutputs;
  final tIds = input ? target.drivers[td.id]!.inputs : target.drivers[td.id]!.outputs;
  final sIds = input ? source.drivers[sd.id]!.inputs : source.drivers[sd.id]!.outputs;
  final kind = input ? CandidateKind.driverInput : CandidateKind.driverOutput;
  final tDef = target.definition, sDef = source.definition;
  final n = tIds.length < sIds.length ? tIds.length : sIds.length;
  for (var i = 0; i < n; i++) {
    final t = tIds[i], s = sIds[i];
    if (!editable) {
      if (t == s || tDef.link(t) == null || sDef.link(s) == null || resolveLinkId(tDef, sDef, s) == t) continue;
      a.candidates.add(
        ImportCandidate(
          kind,
          MatchType.missing,
          CandidateReason.fixedLinkDiffers,
          importable: false,
          isChanged: true,
          targetId: td.id,
          sourceId: sd.id,
          targetIndex: i,
          sourceIndex: i,
        ),
      );
      continue;
    }
    final r = resolveLinkId(tDef, sDef, s);
    final ok = r > 0;
    a.candidates.add(
      ImportCandidate(
        kind,
        ok ? MatchType.exact : MatchType.missing,
        ok ? CandidateReason.linkImportable : CandidateReason.linkUnavailable,
        importable: ok,
        isChanged: ok ? t != r : true,
        targetId: td.id,
        sourceId: sd.id,
        targetIndex: i,
        sourceIndex: i,
      ),
    );
  }
}

void _table(ImportAnalysis a, Calibration target, Calibration source, TableDef t, TableDef? s) {
  if (s == null) {
    a.candidates.add(
      ImportCandidate(
        CandidateKind.table,
        MatchType.missing,
        CandidateReason.missingTable,
        importable: false,
        isChanged: true,
        targetId: t.id,
      ),
    );
    return;
  }
  final same = isSameShape(t, s);
  final condense = !same && isCondensable(t, s), expand = !same && isExpandable(t, s);
  final rescale = !same && isRescalable(t, s);
  final convertible = condense || expand || rescale;
  var cells = 0, axis = 0;
  double minD = 0, maxD = 0;
  var enabledChanged = false;
  if (same) {
    final tv = target.tables[t.id]!, sv = source.tables[s.id]!;
    for (var i = 0; i < t.cells; i++) {
      final d = fround(sv.z[i] - tv.z[i]);
      if (d != 0) {
        cells++;
        if (d < minD) minD = d;
        if (d > maxD) maxD = d;
      }
    }
    for (var i = 0; i < t.cols; i++) {
      if (!(sv.x[i] == tv.x[i])) axis++;
    }
    if (t.isMap) {
      for (var i = 0; i < t.rows; i++) {
        if (!(sv.y[i] == tv.y[i])) axis++;
      }
    }
    enabledChanged = sv.enabled != tv.enabled;
  }
  final changed = !same || cells > 0 || axis > 0 || enabledChanged;
  final ok = same || convertible;
  a.candidates.add(
    ImportCandidate(
      CandidateKind.table,
      same
          ? (t.id != s.id ? MatchType.nameMatch : MatchType.exact)
          : (convertible ? MatchType.converted : MatchType.incompatible),
      condense
          ? CandidateReason.condensed
          : expand
          ? CandidateReason.expanded
          : rescale
          ? CandidateReason.rescaled
          : same
          ? CandidateReason.sameShape
          : CandidateReason.differentSize,
      importable: ok,
      isChanged: changed,
      targetId: t.id,
      sourceId: s.id,
      changedCells: cells,
      changedAxis: axis,
      minCellDelta: minD,
      maxCellDelta: maxD,
      enabledChanged: enabledChanged,
    ),
  );
}

// ---------------------------------------------------------------- applying the selection

/// [target] with the selected, importable candidates applied from [source].
Calibration applyImport(Calibration target, Calibration source, List<ImportCandidate> candidates) {
  final out = target.copy();
  final groups = <int, List<ImportCandidate>>{};
  for (final c in candidates) {
    if (c.selected && c.importable) groups.putIfAbsent(c.targetId, () => []).add(c);
  }
  final td = out.definition, sd = source.definition;
  for (final MapEntry(key: id, value: group) in groups.entries) {
    if (td.drivers[id] case final d?) {
      _applyDriver(out, source, d, group);
      continue;
    }
    final t = td.tables[id];
    if (t == null) continue;
    ImportCandidate? first;
    for (final c in group) {
      if (c.kind == CandidateKind.table) {
        first = c;
        break;
      }
    }
    final s = first == null ? null : sd.tables[first.sourceId];
    final tv = out.tables[id]!;
    if (s == null) continue;
    final sv = source.tables[s.id]!;
    if (isSameShape(t, s)) {
      tv.enabled = sv.enabled;
      assignFloats(tv.x, sv.x);
      if (t.isMap) assignFloats(tv.y, sv.y);
      assignFloats(tv.z, sv.z);
    } else if (isCondensable(t, s)) {
      tv.enabled = sv.enabled;
      assignFloats(tv.x, [sv.x[0], sv.x[s.cols - 1]]);
      assignFloats(tv.z, [sv.z[0], sv.z[s.cols - 1]]);
    } else if (isExpandable(t, s)) {
      tv.enabled = sv.enabled;
      assignFloats(tv.x, spreadAxis(sv.x, t.cols));
      assignFloats(tv.z, spreadAxis(sv.z, t.cols));
    } else if (isRescalable(t, s)) {
      final xs = spreadAxis(sv.x, t.cols), ys = spreadAxis(sv.y, t.rows);
      final res = [
        for (var r = 0; r < t.rows; r++)
          for (var c = 0; c < t.cols; c++) sampleBilinear(sv.x, sv.y, sv.z, s.cols, xs[c], ys[r]),
      ];
      tv.enabled = sv.enabled;
      assignFloats(tv.x, xs);
      assignFloats(tv.y, ys);
      assignFloats(tv.z, res);
    }
  }
  return out;
}

void _applyDriver(Calibration out, Calibration source, DriverDef td, List<ImportCandidate> group) {
  final tv = out.drivers[td.id]!;
  for (final c in group) {
    final sd = source.definition.drivers[c.sourceId];
    if (sd == null) continue;
    final sv = source.drivers[sd.id]!;
    final (ti, si) = (c.targetIndex, c.sourceIndex);
    if (c.kind == CandidateKind.driverParameter) {
      if (ti >= 0 && ti < tv.config.length && si >= 0 && si < sv.config.length && tv.config[ti] != sv.config[si]) {
        tv.config[ti] = sv.config[si];
      }
    } else if (c.kind == CandidateKind.driverInput || c.kind == CandidateKind.driverOutput) {
      final input = c.kind == CandidateKind.driverInput;
      if (!(input ? td.editableInputs : td.editableOutputs)) continue;
      final tArr = input ? tv.inputs : tv.outputs, sArr = input ? sv.inputs : sv.outputs;
      if (!(ti >= 0 && ti < tArr.length && si >= 0 && si < sArr.length)) continue;
      final r = resolveLinkId(out.definition, source.definition, sArr[si]);
      if (r != 0) tArr[ti] = r;
    }
  }
}

/// [n] points evenly between [src]'s first and last.
List<double> spreadAxis(List<double> src, int n) {
  final first = src.first, last = src.last;
  return [for (var i = 0; i < n; i++) fround(first + fround(fround(fround(last - first) * i) / (n - 1)))];
}

double _lerp(double a, double b, double t) => fround(a + fround(fround(b - a) * t));

/// The segment of [axis] (ascending or descending) holding [v], and where in it; past either end, that end.
({int lo, int hi, double t}) findSegment(List<double> axis, double v) {
  final last = axis.length - 1;
  final asc = !(axis[last] < axis[0]);
  for (var i = 0; i < last; i++) {
    final a = axis[i], b = axis[i + 1];
    final inside = asc ? (v >= a && v <= b) : (v <= a && v >= b);
    if (inside) return (lo: i, hi: i + 1, t: b == a ? 0 : fround(fround(v - a) / fround(b - a)));
  }
  final past = asc ? v > axis[last] : v < axis[last];
  final k = past ? last : 0;
  return (lo: k, hi: k, t: 0);
}

double sampleBilinear(List<double> xs, List<double> ys, List<double> data, int cols, double x, double y) {
  final sx = findSegment(xs, x), sy = findSegment(ys, y);
  final a = _lerp(data[sy.lo * cols + sx.lo], data[sy.lo * cols + sx.hi], sx.t);
  final b = _lerp(data[sy.hi * cols + sx.lo], data[sy.hi * cols + sx.hi], sx.t);
  return _lerp(a, b, sy.t);
}
