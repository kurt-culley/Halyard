@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:halyard/platform/storage_web.dart';
import 'package:web/web.dart' as web;

void main() {
  test('the origin-private file system keeps files in folders', () async {
    final s = OpfsStorage(await web.window.navigator.storage.getDirectory().toDart);
    await s.delete('definitions/t.medef');
    expect(await s.read('definitions/t.medef'), isNull);
    await s.write('definitions/t.medef', Uint8List.fromList([1, 2, 3]));
    await s.write('definitions/t.medef', Uint8List.fromList([4]));
    expect(await s.read('definitions/t.medef'), [4]);
    await s.delete('definitions/t.medef');
    expect(await s.read('definitions/t.medef'), isNull);
  });
}
