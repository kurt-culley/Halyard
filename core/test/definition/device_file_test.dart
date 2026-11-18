@TestOn('vm')
library;

import 'dart:io';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

void main() {
  final vectors = loadVectors('device_files.json').cast<Map<String, dynamic>>();

  test('loads synthetic definitions as the TypeScript engine does: items kept, wire blobs and hashes', () {
    for (final (i, v) in vectors.indexed) {
      final xml = v['xml'] as String;
      if (v['error'] == true) {
        expect(() => readDeviceFile(xml), throwsA(anything), reason: 'file $i should be rejected');
        continue;
      }
      final (:definition, :calibration) = readDeviceFile(xml);
      final why = 'file $i';
      final info = v['info'] as Map<String, dynamic>;
      expect(definition.info.productName, info['productName'], reason: why);
      expect(definition.info.modelName, info['modelName'], reason: why);
      expect(definition.info.version, info['version'], reason: why);
      expect(definition.info.fwVersion, info['fwVersion'], reason: why);
      expect(calibration.notes, v['notes'], reason: why);
      expect(definition.links.keys.toList(), v['links'], reason: why);

      final tables = (v['tables'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(definition.tables.keys.toList(), [for (final t in tables) t['id']], reason: '$why table ids');
      for (final t in tables) {
        final id = t['id'] as int;
        final d = definition.tables[id]!;
        final values = calibration.tables[id]!;
        expect(toHex(tableBlob(d, values)), t['blob'], reason: '$why table $id blob');
        expect(tableHash(d, values), t['hash'], reason: '$why table $id hash');
        final back = parseTableBlob(d, fromHex(t['blob'] as String));
        expect(toHex(tableBlob(d, back)), t['blob'], reason: '$why table $id round trip');
      }

      final drivers = (v['drivers'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(definition.drivers.keys.toList(), [for (final d in drivers) d['id']], reason: '$why driver ids');
      for (final dv in drivers) {
        final id = dv['id'] as int;
        final d = definition.drivers[id]!;
        final values = calibration.drivers[id]!;
        expect(toHex(driverBlob(d, values)), dv['blob'], reason: '$why driver $id blob');
        expect(driverHash(d, values), dv['hash'], reason: '$why driver $id hash');
        final back = parseDriverBlob(d, fromHex(dv['blob'] as String));
        expect(toHex(driverBlob(d, back)), dv['blob'], reason: '$why driver $id round trip');
      }

      expect(calibration.overallHash, v['overall'], reason: '$why overall hash');
    }
  });

  test('a blob of the wrong shape is refused', () {
    final v = vectors.firstWhere((v) => v['error'] != true && (v['tables'] as List<dynamic>).isNotEmpty);
    final (:definition, :calibration) = readDeviceFile(v['xml'] as String);
    final d = definition.tables.values.first;
    final blob = tableBlob(d, calibration.tables[d.id]!);
    expect(() => parseTableBlob(d, blob.sublist(0, blob.length - 1)), throwsA(isA<BlobError>()));
    expect(() => parseTableBlob(d, (blob.sublist(0)..[3] = d.cols + 1)), throwsA(isA<BlobError>()));
  });

  test('a copy is independent of the original', () {
    final v = vectors.firstWhere((v) => v['error'] != true && (v['tables'] as List<dynamic>).isNotEmpty);
    final (:definition, :calibration) = readDeviceFile(v['xml'] as String);
    final id = definition.tables.keys.first;
    final copy = calibration.copy();
    copy.tables[id]!.z[0] += 1;
    expect(copy.tables[id]!.z[0], isNot(calibration.tables[id]!.z[0]));
  });

  // Real definitions are never committed. Point HALYARD_DEFS at a folder of .medef files to check they all load.
  final defs = Platform.environment['HALYARD_DEFS'];
  test('loads every definition in HALYARD_DEFS', () {
    final files = Directory(defs!).listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.medef'));
    expect(files, isNotEmpty);
    for (final f in files) {
      final (:definition, calibration: _) = readDeviceFile(f.readAsStringSync());
      expect(definition.tables, isNotEmpty, reason: f.path);
      expect(definition.drivers, isNotEmpty, reason: f.path);
    }
  }, skip: defs == null ? 'HALYARD_DEFS not set' : false);
}
