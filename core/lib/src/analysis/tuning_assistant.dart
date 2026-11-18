/// The fuel tuning assistant (U22 A01 to A05, C01 to C03): logged samples of RPM, load and measured AFR or lambda
/// are spread over the VE table's cells, and each cell gets a suggested correction with a confidence. Nothing here
/// writes; applying suggestions goes through the write gate.
library;

import 'dart:math' as math;

import '../calibration/calibration.dart';
import '../definition/definition.dart';
import '../live/live_store.dart';
import '../logs/log_review.dart';

enum MeasurementMode { afr, lambda }

final class LogSample {
  const LogSample(this.rpm, this.load, this.measured);
  final double rpm, load, measured;
}

/// A table's axes and values as the assistant reads them.
final class TuningTable {
  const TuningTable(this.rows, this.cols, this.x, this.y, this.values);
  TuningTable.of(TableDef d, TableValues v) : this(d.rows, d.cols, v.x, v.y, v.z);
  final int rows, cols;
  final List<double> x, y, values;
  double at(int r, int c) => values[r * cols + c];
}

final class TuningSettings {
  const TuningSettings({
    required this.ve,
    required this.target,
    this.mode = MeasurementMode.afr,
    this.stoichAfr = 14.7,
    this.minimumHits = 4,
    this.confidenceThreshold = 0.55,
    this.stabilityTolerancePercent = 20,
    this.maxCorrectionPercent = 10,
  });
  final TuningTable? ve, target;
  final MeasurementMode mode;
  final double stoichAfr, confidenceThreshold, stabilityTolerancePercent, maxCorrectionPercent;
  final int minimumHits;
}

/// Why a cell is or isn't ready.
enum SuggestionNote { needsMoreHits, lowConfidence, ready }

final class TuningSuggestion {
  const TuningSuggestion({
    required this.row,
    required this.col,
    required this.hitCount,
    required this.weightedHits,
    required this.averageFactor,
    required this.standardDeviation,
    required this.stability,
    required this.confidence,
    required this.currentValue,
    required this.suggestedValue,
    required this.unclampedSuggestedValue,
    required this.percentChange,
    required this.averageMeasured,
    required this.averageTarget,
    required this.eligible,
    required this.note,
  });
  final int row, col, hitCount;
  final double weightedHits, averageFactor, standardDeviation, stability, confidence;
  final double currentValue, suggestedValue, unclampedSuggestedValue, percentChange, averageMeasured, averageTarget;
  final bool eligible;
  final SuggestionNote note;
}

enum TuningProblem { veNotAMap, noTarget, stoichOutOfRange, noSamples }

final class TuningResult {
  TuningResult({this.problem});
  final TuningProblem? problem;
  int considered = 0, used = 0, rejected = 0;

  /// Row by row; empty when there was a problem.
  List<List<TuningSuggestion>> suggestions = const [];
  List<TuningSuggestion> get eligible => [
    for (final row in suggestions)
      for (final s in row)
        if (s.eligible) s,
  ];
}

double _clamp(double v, double a, double b) => math.max(a, math.min(b, v));
double _clamp01(double v) => _clamp(v, 0, 1);
int _toInt(double v) => v.isNaN || v >= 2147483648 || v < -2147483648 ? -2147483648 : v.truncate();
int _clampI(int v, int a, int b) => v < a ? a : (v > b ? b : v);
double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Where [v] falls on [axis] (ascending or descending), as a fractional index, clamped to the axis.
double axisPosition(List<double> axis, double v) {
  if (axis.length <= 1) return 0;
  final asc = !(axis.first > axis.last);
  for (var i = 1; i < axis.length; i++) {
    if (asc ? !(v > axis[i]) : !(v < axis[i])) {
      final d = axis[i] - axis[i - 1];
      if (!(d.abs() >= 1e-6)) return (i - 1).toDouble();
      return _clamp(i - 1 + (v - axis[i - 1]) / d, 0, axis.length - 1.0);
    }
  }
  return asc ? (v < axis.first ? 0 : axis.length - 1.0) : (v > axis.first ? 0 : axis.length - 1.0);
}

({int c0, int c1, int r0, int r1, double fx, double fy}) _cell(TuningTable t, double x, double y) {
  final c0 = _clampI(_toInt(x.floorToDouble()), 0, t.cols - 1), r0 = _clampI(_toInt(y.floorToDouble()), 0, t.rows - 1);
  return (
    c0: c0,
    c1: _clampI(c0 + 1, 0, t.cols - 1),
    r0: r0,
    r1: _clampI(r0 + 1, 0, t.rows - 1),
    fx: _clamp01(x - c0),
    fy: _clamp01(y - r0),
  );
}

double _interpolate2D(TuningTable t, double x, double y) {
  final k = _cell(t, x, y);
  final hi = _lerp(t.at(k.r1, k.c0), t.at(k.r1, k.c1), k.fx);
  return _lerp(_lerp(t.at(k.r0, k.c0), t.at(k.r0, k.c1), k.fx), hi, k.fy);
}

double _interpolateTarget(TuningTable t, double rpm, double load) {
  if (!(t.rows > 1)) {
    final x = axisPosition(t.x, rpm);
    final c0 = _clampI(_toInt(x.floorToDouble()), 0, t.cols - 1), c1 = _clampI(c0 + 1, 0, t.cols - 1);
    return _lerp(t.values[c0], t.values[c1], _clamp01(x - c0));
  }
  return _interpolate2D(t, axisPosition(t.x, rpm), axisPosition(t.y, load));
}

class _Acc {
  int hits = 0;
  double weight = 0, f = 0, f2 = 0, m = 0, t = 0;
  void add(double w, double factor, double measured, double target) {
    if (!(w > 0.0001)) return;
    hits++;
    weight += w;
    f += factor * w;
    f2 += factor * factor * w;
    m += measured * w;
    t += target * w;
  }
}

TuningResult analyseTuning(TuningSettings s, List<LogSample> samples) {
  final ve = s.ve, target = s.target;
  if (ve == null || !(ve.rows > 1)) return TuningResult(problem: TuningProblem.veNotAMap);
  if (target == null) return TuningResult(problem: TuningProblem.noTarget);
  if (s.stoichAfr < 5 || !(s.stoichAfr <= 25)) return TuningResult(problem: TuningProblem.stoichOutOfRange);
  if (samples.isEmpty) return TuningResult(problem: TuningProblem.noSamples);
  final r = TuningResult()..considered = samples.length;
  final acc = [
    for (var i = 0; i < ve.rows; i++) [for (var j = 0; j < ve.cols; j++) _Acc()],
  ];
  for (final smp in samples) {
    final x = axisPosition(ve.x, smp.rpm), y = axisPosition(ve.y, smp.load);
    final v = _interpolate2D(ve, x, y);
    final tg = _interpolateTarget(target, smp.rpm, smp.load);
    final m = smp.measured;
    final useful =
        v.isFinite &&
        v > 0 &&
        tg.isFinite &&
        !(tg < 5) &&
        tg <= 30 &&
        (s.mode == MeasurementMode.lambda ? !(m < 0.4) && !(m > 1.6) : !(m < 5) && !(m > 30));
    if (!useful) {
      r.rejected++;
      continue;
    }
    final factor = s.mode == MeasurementMode.lambda ? m / (tg / s.stoichAfr) : m / tg;
    if (!factor.isFinite || factor < 0.65 || !(factor <= 1.35)) {
      r.rejected++;
      continue;
    }
    final k = _cell(ve, x, y);
    acc[k.r0][k.c0].add((1 - k.fx) * (1 - k.fy), factor, m, tg);
    acc[k.r0][k.c1].add(k.fx * (1 - k.fy), factor, m, tg);
    acc[k.r1][k.c0].add((1 - k.fx) * k.fy, factor, m, tg);
    acc[k.r1][k.c1].add(k.fx * k.fy, factor, m, tg);
    r.used++;
  }
  final maxC = math.max(0.5, math.min(50.0, s.maxCorrectionPercent)) / 100;
  final tol = math.max(1, math.min(50.0, s.stabilityTolerancePercent)) / 100;
  final minHits = math.max(1, s.minimumHits);
  final thr = _clamp01(s.confidenceThreshold);
  r.suggestions = [
    for (var row = 0; row < ve.rows; row++)
      [
        for (var col = 0; col < ve.cols; col++)
          () {
            final a = acc[row][col];
            final cur = ve.at(row, col);
            final avg = a.weight > 0 ? a.f / a.weight : 1.0;
            final sd = math.sqrt(a.weight > 0 ? math.max(0, a.f2 / a.weight - avg * avg) : 0);
            final delta = avg - 1;
            final lim = math.max(-maxC, math.min(maxC, delta));
            final stab = _clamp01(1 - sd / tol);
            final mag = _clamp01(delta.abs() / 0.02);
            final conf = _clamp01(a.weight / minHits) * stab * math.max(0.35, mag);
            return TuningSuggestion(
              row: row,
              col: col,
              hitCount: a.hits,
              weightedHits: a.weight,
              averageFactor: avg,
              standardDeviation: sd,
              stability: stab,
              confidence: conf,
              currentValue: cur,
              suggestedValue: cur * (1 + lim),
              unclampedSuggestedValue: cur * avg,
              percentChange: lim * 100,
              averageMeasured: a.weight > 0 ? a.m / a.weight : 0,
              averageTarget: a.weight > 0 ? a.t / a.weight : 0,
              eligible: !(a.weight < minHits) && !(conf < thr),
              note:
                  a.weight < minHits
                      ? SuggestionNote.needsMoreHits
                      : (conf < thr ? SuggestionNote.lowConfidence : SuggestionNote.ready),
            );
          }(),
      ],
  ];
  return r;
}

/// Samples from the live store's history: the three links aligned from their newest samples.
List<LogSample> liveTuningSamples(LiveStore live, int rpmId, int loadId, int measuredId) {
  if (!live.has(rpmId) || !live.has(loadId) || !live.has(measuredId)) return const [];
  final a = live.length(rpmId), b = live.length(loadId), c = live.length(measuredId);
  final n = math.min(a, math.min(b, c));
  return [
    for (var i = 0; i < n; i++)
      LogSample(
        live.sample(rpmId, a - n + i).$2,
        live.sample(loadId, b - n + i).$2,
        live.sample(measuredId, c - n + i).$2,
      ),
  ];
}

/// Samples from a CSV log's columns: rows where all three are numbers.
List<LogSample> csvTuningSamples(CsvLog log, int rpmColumn, int loadColumn, int measuredColumn) {
  bool ok(int i) => i >= 0 && i < log.headers.length;
  if (!ok(rpmColumn) || !ok(loadColumn) || !ok(measuredColumn)) return const [];
  return [
    for (final r in log.rows)
      if (r[rpmColumn].isFinite && r[loadColumn].isFinite && r[measuredColumn].isFinite)
        LogSample(r[rpmColumn], r[loadColumn], r[measuredColumn]),
  ];
}

final _letterOrDigit = RegExp(r'[\p{L}\p{Nd}]', unicode: true);
String _normalizeColumn(String? v) =>
    [
      for (final r in (v ?? '').toLowerCase().runes)
        if (_letterOrDigit.hasMatch(String.fromCharCode(r))) String.fromCharCode(r),
    ].join();

/// The column for one of [candidates]: an exact match ignoring case and punctuation, else a header containing (or
/// contained in) a candidate; -1 when none.
int findTuningColumn(List<String> headers, List<String?> candidates) {
  final c = {
    for (final x in candidates)
      if (x != null && x.trim().isNotEmpty && _normalizeColumn(x).trim().isNotEmpty) _normalizeColumn(x),
  };
  for (var i = 0; i < headers.length; i++) {
    if (c.contains(_normalizeColumn(headers[i]))) return i;
  }
  for (var i = 0; i < headers.length; i++) {
    final h = _normalizeColumn(headers[i]);
    if (c.any((x) => h.contains(x) || x.contains(h))) return i;
  }
  return -1;
}
