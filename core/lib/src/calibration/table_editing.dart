/// Editing table values (U28b): how many decimals a table shows, the formula box ("+20", "*1.6", "-15%", "=35") and
/// blocks of cells pasted as text.
library;

import '../definition/definition.dart';
import '../logs/number_text.dart';
import '../wire/bytes.dart' show fround;

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
