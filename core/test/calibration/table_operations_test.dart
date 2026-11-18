import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:halyard_core/src/wire/bytes.dart' show fround;
import 'package:test/test.dart';

import '../support/vectors.dart';

Float32List _floats(String hex) => Float32List.fromList(fromHex(hex).buffer.asFloat32List());
double _f(String hex) => _floats(hex)[0];

/// As float bits, every NaN as one pattern (the sign of a NaN differs between platforms).
String _hex(Float32List a) =>
    [for (final v in a) v.isNaN ? '0000c07f' : toHex((Float32List(1)..[0] = v).buffer.asUint8List())].join();
String _norm(String hex) => _hex(_floats(hex));

List<(int, int)> _cells(dynamic list) => [
  for (final c in (list as List<dynamic>).cast<List<dynamic>>()) ((c[0] as int) - 1, (c[1] as int) - 1),
];

Future<void> main() async {
  final cases = (await loadVectors('table_operations.json')).cast<Map<String, dynamic>>();

  test('interpolation, live position and smoothing follow the TypeScript engine (${cases.length} tables)', () {
    for (final (n, c) in cases.indexed) {
      final start = c['start'] as Map<String, dynamic>;
      final v = TableValues(
        enabled: true,
        x: _floats(start['x'] as String),
        y: _floats(start['y'] as String),
        z: _floats(start['z'] as String),
      );
      final inc = _f(c['increment'] as String);
      final tuned = <int>{};
      for (final (k, s) in (c['steps'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
        final why = 'table $n step $k (${s['op']})';
        switch (s['op']) {
          case 'tune':
            tuned.add(s['cell'] as int);
          case 'row':
            interpolateRow(v, s['row'] as int, s['from'] as int, s['to'] as int, tuned: tuned);
          case 'col':
            interpolateColumn(v, s['col'] as int, s['from'] as int, s['to'] as int, tuned: tuned);
          case 'axis':
            interpolateAxis(s['axis'] == 1 ? v.y : v.x, s['from'] as int, s['to'] as int);
          case 'position':
            final p = tablePosition(v, _f(s['in0'] as String), _f(s['in1'] as String));
            final want = s['pos'] as List<dynamic>;
            expect(
              [
                _hex(Float32List.fromList([p.x])),
                _hex(Float32List.fromList([p.y])),
                p.col,
                p.row,
              ],
              [_norm(want[0] as String), _norm(want[1] as String), want[2], want[3]],
              reason: why,
            );
            expect(_hex(Float32List.fromList([offsetFromCellCentre(p)])), _norm(s['offset'] as String), reason: why);
          case 'smooth':
            smoothCells(v, _cells(s['cells']));
          case 'drag':
            final delta = switch (s['key']) {
              'Q' => -inc,
              'W' => inc,
              'A' => -fround(inc / 10),
              _ => fround(inc / 10),
            };
            dragAround(v, _cells(s['cells']), delta, s['radius'] as int);
        }
        final after = s['after'] as Map<String, dynamic>;
        expect(
          [_hex(v.x), _hex(v.y), _hex(v.z)],
          [_norm(after['x'] as String), _norm(after['y'] as String), _norm(after['z'] as String)],
          reason: why,
        );
      }
    }
  });
}
