/// Numbers in log files as the original wrote them: .NET "G" (invariant culture) with 7 significant digits for
/// floats and 15 for doubles. Kept only where text goes into files other tools read.
library;

/// `ToString()` of a float ([isFloat]) or a double.
String formatGeneral(double v, {bool isFloat = true}) {
  if (v.isNaN) return 'NaN';
  if (v == double.infinity) return 'Infinity';
  if (v == double.negativeInfinity) return '-Infinity';
  if (v == 0) return '0';
  final p = isFloat ? 7 : 15;
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
