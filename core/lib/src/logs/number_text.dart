/// Numbers in log files as the original wrote them: .NET "G" (invariant culture) with 7 significant digits for
/// floats and 15 for doubles. Kept only where text goes into files other tools read.
library;

import 'dart:typed_data';

/// `ToString()` of a float ([isFloat]) or a double.
String formatGeneral(double v, {bool isFloat = true}) => _formatG(v, isFloat ? 7 : 15);

/// `float.ToString("R")` on .NET Framework: "G7" when that reads back to the same float, otherwise "G9".
String formatFloatR(double v) {
  final g7 = _formatG(v, 7);
  if (!v.isFinite) return g7;
  final back = Float32List.fromList([double.parse(g7.replaceFirst('E', 'e'))])[0];
  return back == Float32List.fromList([v])[0] ? g7 : _formatG(v, 9);
}

String _formatG(double v, int p) {
  if (v.isNaN) return 'NaN';
  if (v == double.infinity) return 'Infinity';
  if (v == double.negativeInfinity) return '-Infinity';
  if (v == 0) return '0';
  final parts = v.abs().toStringAsExponential(p - 1).split('e');
  final d = parts[0].replaceAll('.', '').replaceFirst(RegExp(r'0+$'), '');
  final exp = int.parse(parts[1]);
  final String s;
  if (exp >= p || exp <= -5) {
    s = '${d[0]}${d.length > 1 ? '.${d.substring(1)}' : ''}E${exp < 0 ? '-' : '+'}${exp.abs().toString().padLeft(2, '0')}';
  } else if (exp < 0) {
    s = '0.${'0' * (-exp - 1)}$d';
  } else if (d.length > exp + 1) {
    s = '${d.substring(0, exp + 1)}.${d.substring(exp + 1)}';
  } else {
    s = d + '0' * (exp + 1 - d.length);
  }
  return v < 0 ? '-$s' : s;
}

// ---------------------------------------------------------------- parsing, as .NET's Parse (invariant culture)

final _number = RegExp(r'^[\t\n\x0B\f\r ]*([+-])?(\d[\d,]*)?(?:\.(\d*))?(?:[eE]([+-]?\d+))?[\t\n\x0B\f\r ]*\x00*$');

/// `Double.Parse`: optional sign, digits with thousands commas, a fraction and an exponent, or Infinity, -Infinity
/// and NaN. Throws [FormatException] for anything else and [RangeError] when the value overflows.
double parseNetDouble(String s) {
  final m = _number.firstMatch(s);
  if (m != null && ((m[2] != null && RegExp(r'\d').hasMatch(m[2]!)) || (m[3] != null && m[3]!.isNotEmpty))) {
    final intDigits = (m[2] ?? '').replaceAll(',', '');
    final frac = m[3] ?? '';
    final text =
        '${m[1] ?? ''}${intDigits.isEmpty ? '0' : intDigits}${frac.isEmpty ? '' : '.$frac'}'
        '${m[4] == null ? '' : 'e${m[4]}'}';
    final d = double.parse(text);
    if (!d.isFinite) throw RangeError('Value was either too large or too small for a Double.');
    return d;
  }
  switch (s.trim()) {
    case 'Infinity':
      return double.infinity;
    case '-Infinity':
      return double.negativeInfinity;
    case 'NaN':
      return double.nan;
  }
  throw FormatException('Input string was not in a correct format.', s);
}

/// `Single.Parse`: parsed as a double, then narrowed; a finite input that becomes infinite overflows.
double parseNetSingle(String s) {
  final d = parseNetDouble(s);
  final f = (Float32List(1)..[0] = d)[0];
  if (!f.isFinite && d.isFinite) throw RangeError('Value was either too large or too small for a Single.');
  return f;
}

final _integer = RegExp(r'^[\t\n\x0B\f\r ]*([+-])?([0-9]+)[\t\n\x0B\f\r ]*$');

/// `Int32.Parse`, `UInt32.Parse` and the like: an optional sign and decimal digits within [min]..[max].
int parseNetInteger(String s, int min, int max) {
  final m = _integer.firstMatch(s);
  if (m == null) throw FormatException('Input string was not in a correct format.', s);
  final negative = m[1] == '-';
  final v = double.parse('${negative ? '-' : ''}${m[2]}');
  if (!(v >= min && v <= max) || (negative && min == 0 && v != 0)) {
    throw RangeError('Value was either too large or too small.');
  }
  return v.toInt();
}

int? tryNetInt32(String s) {
  try {
    return parseNetInteger(s, -2147483648, 2147483647);
  } on Object {
    return null;
  }
}

// ---------------------------------------------------------------- "F" (fixed decimals)

/// `ToString("F<decimals>")` of a float ([isFloat]) or a double: the value reduced to 7 (or 15) significant digits,
/// then rounded half away from zero at the decimal; a result of zero has no minus sign.
String formatFixed(double v, int decimals, {bool isFloat = true}) {
  if (v.isNaN) return 'NaN';
  if (v == double.infinity) return 'Infinity';
  if (v == double.negativeInfinity) return '-Infinity';
  RangeError.checkValueInInterval(decimals, 0, 99, 'decimals');
  var neg = v < 0 || (v == 0 && v.isNegative);
  var d = '';
  var scale = 0;
  if (v != 0) {
    final parts = v.abs().toStringAsExponential((isFloat ? 7 : 15) - 1).split('e');
    d = parts[0].replaceAll('.', '').replaceFirst(RegExp(r'0+$'), '');
    scale = int.parse(parts[1]) + 1;
  }
  // Round at the decimal, half away from zero on the digit string.
  final pos = scale + decimals;
  if (d.isEmpty || pos < 0) {
    (d, scale, neg) = ('', 0, false);
  } else if (pos < d.length) {
    final a = d.substring(0, pos).split('');
    if (d.codeUnitAt(pos) >= 0x35) {
      var i = a.length - 1;
      while (i >= 0 && a[i] == '9') {
        a[i--] = '0';
      }
      if (i < 0) {
        a.insert(0, '1');
        scale++;
      } else {
        a[i] = String.fromCharCode(a[i].codeUnitAt(0) + 1);
      }
    }
    d = a.join().replaceFirst(RegExp(r'0+$'), '');
    if (d.isEmpty) (scale, neg) = (0, false);
  }
  final intPart =
      d.isEmpty || scale <= 0 ? '0' : d.substring(0, scale < d.length ? scale : d.length).padRight(scale, '0');
  final frac = StringBuffer();
  for (var i = 0; i < decimals; i++) {
    final k = scale + i;
    frac.write(k >= 0 && k < d.length ? d[k] : '0');
  }
  return '${neg ? '-' : ''}$intPart${decimals > 0 ? '.$frac' : ''}';
}
