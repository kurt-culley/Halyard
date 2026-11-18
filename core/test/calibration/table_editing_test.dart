import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

double _f(String hex) => fromHex(hex).buffer.asFloat32List()[0];

/// As float bits, NaN as one pattern (its sign differs between platforms).
String _bits(double v) => v.isNaN ? 'nan' : toHex((Float32List(1)..[0] = v).buffer.asUint8List());
String _norm(String hex) => _f(hex).isNaN ? 'nan' : hex;

Future<void> main() async {
  final v = (await loadVectors('table_editing.json')).first as Map<String, dynamic>;
  List<List<dynamic>> rows(String k) => (v[k] as List<dynamic>).cast<List<dynamic>>();

  test('custom decimal formats', () {
    for (final r in rows('formats')) {
      expect(formatDecimals(_f(r[0] as String), r[1] as int, r[2] as int), r[3], reason: '$r');
    }
  });

  test('decimals of an increment', () {
    for (final r in rows('incs')) {
      expect(incrementDecimals(_f(r[0] as String)), r[1], reason: '$r');
    }
  });

  test("a table's decimals", () {
    for (final (i, c) in (v['tables'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
      final t = c['table'] as List<dynamic>;
      final link = t[5] as List<dynamic>?;
      final table = TableDef(
        id: t[0] as int,
        name: t[1] as String?,
        outputName: t[2] as String?,
        increment: _f(t[3] as String),
        category: t[4] as String?,
        cols: 16,
        rows: 1,
      );
      final out = link == null ? null : LinkDef(id: 1, name: link[0] as String?, measureUnit: link[1] as String?);
      final f = tableDecimals(table, out, decimals: c['decimals'] as int?);
      expect([f.min, f.max], c['format'], reason: 'table $i');
      expect(isLambdaRelated(table, out), c['lambda'], reason: 'table $i');
      expect(isVeTable(table, out), c['ve'], reason: 'table $i');
    }
  });

  test('formulas', () {
    const ops = [
      null,
      FormulaOperation.add,
      FormulaOperation.subtract,
      FormulaOperation.multiply,
      FormulaOperation.divide,
    ];
    for (final (i, c) in (v['formulas'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
      final m = TableFormula.parse(c['text'] as String);
      final why = 'formula $i "${c['text']}"';
      expect(m.isValid, c['valid'], reason: why);
      final op = c['operation'] as int;
      expect(m.operation, op == 5 ? FormulaOperation.set : ops[op], reason: why);
      expect(_bits(m.operand), _norm(c['operand'] as String), reason: why);
      for (final a in (c['applied'] as List<dynamic>).cast<List<dynamic>>()) {
        expect(_bits(m.apply(_f(a[0] as String))), _norm(a[1] as String), reason: why);
      }
    }
  });

  test('pasted cells', () {
    for (final (i, c) in (v['clipboard'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
      final b = parseCellBlock(c['text'] as String?);
      expect(b, c['block'], reason: 'paste $i');
      expect(isSingleCell(b), c['single'], reason: 'paste $i');
    }
  });
}
