/// Editing table values (U28b): how many decimals a table shows, the formula box ("+20", "*1.6", "-15%", "=35"),
/// blocks of cells pasted as text, and the operations on values: interpolation, the live position and smoothing.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../definition/definition.dart';
import '../logs/number_text.dart';
import '../wire/bytes.dart' show fround;
import 'calibration.dart';

/// Decimals shown: at least [min], at most [max], trailing zeros dropped in between.
typedef DecimalsFormat = ({int min, int max});

/// The decimals of an increment (written with up to 8), at most 4; 3 for 0, NaN or infinite.
int incrementDecimals(double increment) {
  final a = increment.abs();
  if (!a.isFinite || !(a > 0)) return 3;
  final s = formatDecimals(fround(increment), 0, 8);
  final i = s.indexOf('.');
  return i < 0 ? 0 : (s.length - i - 1).clamp(0, 4);
}

final _veToken = RegExp(r'\bVE\b');
final _letterOrDigit = RegExp(r'[\p{L}\p{Nd}]', unicode: true);

String _lettersAndDigits(String? v) =>
    String.fromCharCodes((v ?? '').toLowerCase().runes.where((r) => _letterOrDigit.hasMatch(String.fromCharCode(r))));

/// A name or unit that reads as an air-fuel ratio (AFR trims and deadbands don't count).
bool isAfrLike(String? name, String? unit) {
  final n = _lettersAndDigits(name), u = _lettersAndDigits(unit);
  if (n.contains('afr') && (n.contains('trim') || n.contains('deadband'))) return false;
  return u.contains('afr') || n.contains('afr');
}

/// A table whose values are AFR or lambda: by its output link, names or category.
bool isLambdaRelated(TableDef t, LinkDef? outputLink) {
  final afr =
      (outputLink != null && isAfrLike(outputLink.name, outputLink.measureUnit)) ||
      isAfrLike(t.outputName, null) ||
      isAfrLike(t.name, null);
  bool lambda(String? v) => _lettersAndDigits(v).contains('lambda');
  return afr || lambda(t.name) || lambda(t.outputName) || lambda(outputLink?.name) || lambda(t.category);
}

bool isVeTable(TableDef t, LinkDef? outputLink) =>
    [t.name, t.outputName, outputLink?.name].any((n) => n != null && _veToken.hasMatch(n));

/// The decimals a table's values show: the user's choice for the table ([decimals], 0 to 4) when there is one;
/// otherwise at least 2 for AFR or lambda and 1 for VE tables, and as many as the increment has.
DecimalsFormat tableDecimals(TableDef t, LinkDef? outputLink, {int? decimals}) {
  if (decimals != null) {
    final d = decimals.clamp(0, 4);
    return (min: d, max: d);
  }
  final inc = incrementDecimals(t.increment);
  if (isLambdaRelated(t, outputLink)) return (min: 2, max: inc < 2 ? 2 : inc);
  if (isVeTable(t, outputLink)) return (min: 1, max: inc < 1 ? 1 : inc);
  return (min: 0, max: inc);
}

enum FormulaOperation { add, subtract, multiply, divide, set }

/// The formula box: "+n", "-n", "*n", "/n", "=n", and "+n%" or "-n%" (as a multiplication). Anything else is invalid.
final class TableFormula {
  const TableFormula._(this.operation, this.operand);

  factory TableFormula.parse(String text) {
    final raw = text.trim();
    if (raw.length <= 1) return const TableFormula._(null, 0);
    final op = switch (raw[0]) {
      '+' => FormulaOperation.add,
      '-' => FormulaOperation.subtract,
      '*' => FormulaOperation.multiply,
      '/' => FormulaOperation.divide,
      '=' => FormulaOperation.set,
      _ => null,
    };
    if (op == null) return const TableFormula._(null, 0);
    final rest = raw.substring(1);
    if (rest.contains('%')) {
      final v = _tryParseSingle(rest.replaceAll('%', ''));
      return switch ((op, v)) {
        (FormulaOperation.add, final v?) => TableFormula._(FormulaOperation.multiply, fround(1 + fround(v / 100))),
        (FormulaOperation.subtract, final v?) => TableFormula._(FormulaOperation.multiply, fround(1 - fround(v / 100))),
        _ => TableFormula._(null, v ?? 0),
      };
    }
    final v = _tryParseSingle(rest);
    return v == null ? const TableFormula._(null, 0) : TableFormula._(op, v);
  }

  /// Null when the text isn't a formula.
  final FormulaOperation? operation;
  final double operand;

  bool get isValid => operation != null;

  double apply(double v) => switch (operation) {
    FormulaOperation.add => fround(operand + v),
    FormulaOperation.subtract => fround(v - operand),
    FormulaOperation.multiply => fround(operand * v),
    FormulaOperation.divide => fround(v / operand),
    FormulaOperation.set => operand,
    null => v,
  };
}

/// `Single.TryParse`: null for text that isn't a number or overflows.
double? _tryParseSingle(String s) {
  try {
    return parseNetSingle(s);
  } on FormatException {
    return null;
  } on RangeError {
    return null;
  }
}

final _lineBreak = RegExp('\r\n|\n|\r');
final _space = RegExp(r'\s+');

/// Pasted text as rows of cells, up to the last row that isn't blank: cells split on tabs, or on white space when a
/// row has none. Null when the text is blank.
List<List<String>>? parseCellBlock(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final rows = text.split(_lineBreak);
  final last = rows.lastIndexWhere((r) => r.trim().isNotEmpty);
  if (last < 0) return null;
  return [for (final r in rows.take(last + 1)) _cells(r)];
}

List<String> _cells(String line) {
  if (line.trim().isEmpty) return const [];
  if (!line.contains('\t')) return line.split(_space).where((x) => x.isNotEmpty).toList();
  return line.split('\t');
}

bool isSingleCell(List<List<String>>? block) => block != null && block.length == 1 && block[0].length == 1;

// ---------------------------------------------------------------- operations on a table's values (U02-I01, P03,
// I02 to I04, P01 to P05; U28b C05, C06). Cells are 0-based: row, then column. Arithmetic is in floats, as the
// original's was.

void _set(Float32List a, int i, double v) {
  final old = a[i];
  if (old == v || (old.isNaN && v.isNaN)) return;
  a[i] = v;
}

/// The value at [x] of [span] between [a] and [b].
double interpolateBetween(double a, double b, double x, double span) {
  a = fround(a);
  b = fround(b);
  x = fround(x);
  span = fround(span);
  if (a < b) return fround(fround(fround(b - a) * fround(x / span)) + a);
  return fround(fround(fround(fround(a - b) * fround(span - x)) / span) + b);
}

/// Spreads an axis evenly between entries [from] and [to].
void interpolateAxis(Float32List axis, int from, int to) {
  if (from >= to || to - from == 1) return;
  final step = fround(fround(axis[to] - axis[from]) / fround((to - from).abs().toDouble()));
  for (var i = from + 1; i < to; i++) {
    _set(axis, i, fround(axis[i - 1] + step));
  }
}

/// Fills a row between columns [from] and [to] by the column axis, leaving [tuned] cells alone.
void interpolateRow(TableValues v, int row, int from, int to, {Set<int> tuned = const {}}) {
  final cols = v.x.length;
  final v1 = v.z[row * cols + from], v2 = v.z[row * cols + to];
  final span = fround(v.x[to] - v.x[from]).abs();
  if (span == 0) return;
  for (var k = 0; k < to - from; k++) {
    final i = row * cols + k + from;
    if (tuned.contains(i)) continue;
    _set(v.z, i, interpolateBetween(v1, v2, fround(v.x[k + from] - v.x[from]).abs(), span));
  }
}

/// Fills a column between rows [from] and [to] by the row axis, leaving [tuned] cells alone.
void interpolateColumn(TableValues v, int col, int from, int to, {Set<int> tuned = const {}}) {
  final cols = v.x.length;
  final v1 = v.z[from * cols + col], v2 = v.z[to * cols + col];
  final span = fround(v.y[to] - v.y[from]).abs();
  if (span == 0) return;
  for (var k = 0; k < to - from; k++) {
    final i = (from + k) * cols + col;
    if (tuned.contains(i)) continue;
    _set(v.z, i, interpolateBetween(v1, v2, fround(v.y[k + from] - v.y[from]).abs(), span));
  }
}

/// Where live inputs fall in a map: fractional column and row, and the cell they round to.
typedef TablePosition = ({double x, double y, int col, int row});

/// The position of [in0] and [in1] on a map's axes (ascending or descending), clamped to the table.
TablePosition tablePosition(TableValues v, double in0, double in1) {
  double along(Float32List a, double value) =>
      a.first < a.last ? _ascending(a, fround(value)) : _descending(a, fround(value));
  final x = along(v.x, in0), y = along(v.y, in1);
  return (x: x, y: y, col: tableCellIndex(x), row: tableCellIndex(y));
}

double _ascending(Float32List a, double v) {
  final n = a.length;
  var pos = fround(n - 1.0);
  for (var i = 1; i < n; i++) {
    if (v < a[i]) {
      final d = fround(a[i] - a[i - 1]);
      pos = fround(fround(i - 1.0) + fround(fround(v - a[i - 1]) / d));
      break;
    }
  }
  if (pos < 0) pos = 0;
  if (pos >= n) pos = fround(n - 1.0);
  return pos;
}

double _descending(Float32List a, double v) {
  final n = a.length;
  var pos = fround(n - 1.0);
  for (var i = 1; i < n; i++) {
    if (v > a[i]) {
      final d = fround(a[i - 1] - a[i]);
      pos = fround(fround(i - 1.0) + fround(fround(a[i - 1] - v) / d));
      break;
    }
  }
  if (pos < 0) pos = 0;
  if (pos >= n) pos = fround(n - 1.0);
  return pos;
}

/// `(int)Math.Round(pos, 1)`: half to even at one decimal, then truncated; out of range gives int.MinValue.
int tableCellIndex(double pos) {
  var v = fround(pos);
  if (v.abs() < 1e16) {
    final t = v * 10;
    final fl = t.floorToDouble(), d = t - fl;
    v = (d < 0.5 ? fl : (d > 0.5 ? fl + 1 : (fl % 2 == 0 ? fl : fl + 1))) / 10;
  }
  if (!v.isFinite || v >= 2147483648 || v < -2147483648) return -2147483648;
  return v.truncate();
}

/// How far the position is from the centre of its cell, in hundredths of a cell along each axis, summed.
double offsetFromCellCentre(TablePosition p) {
  final a = fround(p.x - fround(p.col.toDouble())).abs(), b = fround(p.y - fround(p.row.toDouble())).abs();
  return fround((a + b) * 100);
}

/// Moves each cell half way to the average of its 3×3 neighbourhood, all from the values before.
void smoothCells(TableValues v, Iterable<(int, int)> cells) {
  final cols = v.x.length, rows = v.y.length;
  final before = Float32List.fromList(v.z);
  for (final (y, x) in cells) {
    if (x < 0 || y < 0 || x >= cols || y >= rows) continue;
    var sum = 0.0;
    var n = 0;
    for (var yy = y - 1 < 0 ? 0 : y - 1; yy <= (y + 1 > rows - 1 ? rows - 1 : y + 1); yy++) {
      for (var xx = x - 1 < 0 ? 0 : x - 1; xx <= (x + 1 > cols - 1 ? cols - 1 : x + 1); xx++) {
        sum = fround(sum + before[yy * cols + xx]);
        n++;
      }
    }
    final i = y * cols + x;
    final avg = fround(sum / n);
    _set(v.z, i, fround(before[i] + fround(fround(avg - before[i]) * 0.5)));
  }
}

/// The weight of a cell [radius] or less from a centre: 1 − distance / (radius + 1).
double smoothWeight(int cx, int cy, int x, int y, int radius) {
  final d = math.sqrt(((x - cx) * (x - cx) + (y - cy) * (y - cy)).toDouble());
  return d <= radius ? fround(1 - d / (radius + 1)) : 0;
}

/// After [delta] moves the selected [cells], moves the cells around them by the same delta times their weight
/// (summed over the selected cells they are near). The selected cells themselves are left alone.
void dragAround(TableValues v, Iterable<(int, int)> cells, double delta, int radius) {
  if (radius == 0) return;
  final cols = v.x.length, rows = v.y.length;
  final selected = <int>{};
  final centres = <(int, int)>[];
  for (final (y, x) in cells) {
    if (x < 0 || y < 0 || x >= cols || y >= rows) continue;
    selected.add(y * cols + x);
    centres.add((x, y));
  }
  final add = <int, double>{};
  for (final (x, y) in centres) {
    for (var cy = y - radius < 0 ? 0 : y - radius; cy <= (y + radius > rows - 1 ? rows - 1 : y + radius); cy++) {
      for (var cx = x - radius < 0 ? 0 : x - radius; cx <= (x + radius > cols - 1 ? cols - 1 : x + radius); cx++) {
        final w = smoothWeight(x, y, cx, cy, radius);
        if (!(w > 0)) continue;
        final i = cy * cols + cx;
        if (selected.contains(i)) continue;
        final d = fround(delta * w);
        add[i] = add.containsKey(i) ? fround(add[i]! + d) : d;
      }
    }
  }
  for (final e in add.entries) {
    _set(v.z, e.key, fround(v.z[e.key] + e.value));
  }
}
