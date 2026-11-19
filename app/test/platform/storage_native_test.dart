@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:halyard/platform/storage_native.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('halyard'));
  tearDown(() => dir.delete(recursive: true));

  test('files are written, read back and deleted under the root', () async {
    final s = FileStorage(dir);
    expect(await s.read('definitions/a.medef'), isNull);
    await s.write('definitions/a.medef', Uint8List.fromList([1, 2]));
    await s.write('definitions/a.medef', Uint8List.fromList([3]));
    expect(await s.read('definitions/a.medef'), [3]);
    expect(File('${dir.path}/definitions/a.medef.tmp').existsSync(), isFalse);
    await s.delete('definitions/a.medef');
    await s.delete('definitions/a.medef');
    expect(await s.read('definitions/a.medef'), isNull);
  });

  test('a folder gives its definition files in name order', () async {
    File('${dir.path}/b.MEDEF').writeAsStringSync('B');
    File('${dir.path}/a.medef').writeAsStringSync('A');
    File('${dir.path}/notes.txt').writeAsStringSync('x');
    expect(await readFolder(dir, '.medef'), [('a.medef', 'A'), ('b.MEDEF', 'B')]);
  });
}
