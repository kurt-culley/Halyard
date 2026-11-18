@TestOn('vm')
library;

import 'dart:io';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

void main() {
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
