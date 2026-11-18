import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

String _bits(double v) => toHex((ByteData(4)..setFloat32(0, v, Endian.little)).buffer.asUint8List());
double _value(String hex) => ByteData.sublistView(fromHex(hex)).getFloat32(0, Endian.little);

Future<void> main() async {
  final cases = (await loadVectors('units.json')).cast<Map<String, dynamic>>();

  test('conversions match the TypeScript module (${cases.length} cases)', () {
    for (final c in cases) {
      final unit = MeasurementUnit.fromKey(c['unit'] as String)!;
      final v = _value(c['v'] as String);
      final check = c['check'] as bool;
      final why = '${unit.key} $v check $check';
      expect(_bits(fromRaw(unit, v, checkBoundaries: check)), c['from'], reason: 'from $why');
      if (unit != MeasurementUnit.fahrenheit) {
        expect(_bits(toRaw(unit, v, checkBoundaries: check)), c['to'], reason: 'to $why');
      }
    }
  });

  test('Fahrenheit converts back as (F - 32) / 1.8 (docs/behaviour-changes.md)', () {
    for (final c in [-40.0, 0.0, 32.0, 98.6, 212.0]) {
      final f = fromRaw(MeasurementUnit.fahrenheit, c);
      expect(toRaw(MeasurementUnit.fahrenheit, f), closeTo(c, 1e-4));
    }
    expect(toRaw(MeasurementUnit.fahrenheit, 212), closeTo(100, 1e-4));
  });
}
