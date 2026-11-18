import 'dart:math';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

void main() {
  List<double> times(int n) => [for (var i = 0; i < n; i++) i * 0.01];

  test('short traces are kept whole', () {
    expect(minMaxLttb(times(5), [1, 2, 3, 4, 5], 10), [0, 1, 2, 3, 4]);
    expect(minMaxLttb(times(5), [1, 2, 3, 4, 5], 2), [0, 1, 2, 3, 4]);
  });

  test('the result has the size asked for, increasing, with both ends', () {
    final r = Random(7);
    for (var t = 0; t < 50; t++) {
      final n = 500 + r.nextInt(20000);
      final y = [for (var i = 0; i < n; i++) sin(i / 50) * 100 + r.nextDouble() * 5];
      final out = 50 + r.nextInt(500);
      final idx = minMaxLttb(times(n), y, out);
      expect(idx.length, out);
      expect(idx.first, 0);
      expect(idx.last, n - 1);
      for (var i = 1; i < idx.length; i++) {
        expect(idx[i], greaterThan(idx[i - 1]));
      }
    }
  });

  test('a single-sample spike is never lost', () {
    final r = Random(11);
    for (var t = 0; t < 200; t++) {
      final n = 1000 + r.nextInt(50000);
      final y = [for (var i = 0; i < n; i++) 50 + r.nextDouble()];
      final at = 1 + r.nextInt(n - 2);
      y[at] = r.nextBool() ? 9000 : -9000;
      expect(minMaxLttb(times(n), y, 100 + r.nextInt(900)), contains(at), reason: 'spike at $at of $n');
    }
  });

  test('missing values are never chosen', () {
    final n = 10000;
    final y = [for (var i = 0; i < n; i++) i.isEven ? double.nan : i.toDouble()];
    final idx = minMaxLttb(times(n), y, 200);
    expect(idx.skip(1).take(idx.length - 2).every((i) => y[i].isFinite), isTrue);
  });
}
