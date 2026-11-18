import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:halyard_core/src/definition/xml_convert.dart' show XmlConvert;
import 'package:halyard_core/src/wire/bytes.dart' show fround;
import 'package:test/test.dart';

import '../support/vectors.dart';

Future<void> main() async {
  final files = (await loadVectors('calibration_files.json')).cast<Map<String, dynamic>>();

  test('saves loaded files exactly as the TypeScript writer does (${files.length} files)', () {
    for (final (i, v) in files.indexed) {
      final (definition: _, :calibration) = readDeviceFile(v['xml'] as String);
      expect(writeCalibrationFile(calibration), v['saved'], reason: 'file $i');
    }
  });

  test('saves the same after values arrive from the ECU and the notes change', () {
    for (final (i, v) in files.indexed) {
      final (:definition, :calibration) = readDeviceFile(v['xml'] as String);
      for (final e in (v['tableEdits'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final id = e['id'] as int;
        calibration.tables[id] = parseTableBlob(
          definition.tables[id]!,
          fromHex(e['blob'] as String),
          calibration.tables[id],
        );
      }
      for (final e in (v['driverEdits'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final id = e['id'] as int;
        calibration.drivers[id] = parseDriverBlob(
          definition.drivers[id]!,
          fromHex(e['blob'] as String),
          calibration.drivers[id],
        );
      }
      calibration.notes = v['notes'] as String?;
      expect(writeCalibrationFile(calibration), v['savedAfterEdits'], reason: 'file $i');
    }
  });

  test('a saved file reads back to the same calibration', () {
    for (final (i, v) in files.indexed) {
      final (definition: _, :calibration) = readDeviceFile(v['xml'] as String);
      final saved = writeCalibrationFile(calibration);
      final again = readDeviceFile(saved);
      expect(writeCalibrationFile(again.calibration), saved, reason: 'file $i');
      expect(again.calibration.overallHash, calibration.overallHash, reason: 'file $i');
    }
  });

  test('a curve keeps its row axis when its values arrive from the ECU', () {
    final v = files.firstWhere((v) {
      final (:definition, calibration: _) = readDeviceFile(v['xml'] as String);
      return definition.tables.values.any((t) => !t.isMap);
    });
    final (:definition, :calibration) = readDeviceFile(v['xml'] as String);
    final t = definition.tables.values.firstWhere((t) => !t.isMap);
    final before = calibration.tables[t.id]!..y[0] = 42;
    final after = parseTableBlob(t, tableBlob(t, before), before);
    expect(after.y, before.y);
    expect(identical(after.y, before.y), isFalse);
  });

  test('a stored zero keeps its sign when an equal value arrives, as the original stored values', () {
    final a = Float32List.fromList([0, -0.0, 1]);
    assignFloats(a, [-0.0, 0, 2]);
    expect([for (final v in a) v.isNegative], [false, true, false]);
    expect(a[2], 2);
  });

  test('backup file name', () {
    const info = DeviceInfo(productName: 'P', modelName: 'M', version: '7');
    expect(backupCalibrationFileName(info, DateTime(2026, 3, 4, 5, 6)), 'P_M_7_2026_03_04_05_06.mecal');
  });

  test('floats are written as the original wrote them', () {
    const cases = [
      (0.0, '0'),
      (-0.0, '-0'),
      (1.0, '1'),
      (0.10000000149011612, '0.1'),
      (0.3333333432674408, '0.333333343'),
      (1e7, '1E+07'),
      (100000.0, '100000'),
      (1234567.5, '1234567.5'),
      (123456792.0, '123456792'),
      (1e-5, '1E-05'),
      (0.0001, '0.0001'),
      (3.4028234663852886e38, '3.40282347E+38'),
      (1e-45, '1.401298E-45'),
      (double.nan, 'NaN'),
      (double.infinity, 'INF'),
      (double.negativeInfinity, '-INF'),
    ];
    for (final (v, text) in cases) {
      expect(XmlConvert.fromF32(fround(v)), text, reason: '$v');
    }
  });
}
