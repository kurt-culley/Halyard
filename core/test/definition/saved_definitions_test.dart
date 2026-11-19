import 'dart:convert';
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

final class _MemoryStorage implements AppStorage {
  final files = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String name) async => files[name];
  @override
  Future<void> write(String name, Uint8List bytes) async => files[name] = bytes;
  @override
  Future<void> delete(String name) async => files.remove(name);
}

String _def(String model) =>
    '<ecu><DeviceDataInformationModel><ProductName>ME360</ProductName><ModelName>$model</ModelName>'
    '<Version>12</Version></DeviceDataInformationModel><links></links><drivers></drivers><tables></tables></ecu>';

void main() {
  test('definitions come back after a restart, once per content', () async {
    final storage = _MemoryStorage();
    final saved = SavedDefinitions(storage, DefinitionLibrary());
    await saved.add('a.medef', _def('V2D'));
    await saved.add('copy of a.medef', _def('V2D'));
    await saved.add('b.medef', _def('GENERIC'));
    expect(storage.files.keys.where((k) => k.endsWith('.medef')), hasLength(2));

    await saved.remove('a.medef');
    expect(storage.files.keys.where((k) => k.endsWith('.medef')), hasLength(2), reason: 'still used by the copy');
    await saved.add('b.medef', _def('V3'));
    expect(storage.files.keys.where((k) => k.endsWith('.medef')), hasLength(2), reason: 'the old b is gone');

    final again = SavedDefinitions(storage, DefinitionLibrary());
    expect(await again.restore(), isEmpty);
    expect(again.library.sources, ['copy of a.medef', 'b.medef']);
    expect(again.library['b.medef']!.definition.info.modelName, 'V3');
  });

  test('a damaged saved file is reported and the rest still load', () async {
    final storage = _MemoryStorage();
    final saved = SavedDefinitions(storage, DefinitionLibrary());
    await saved.add('a.medef', _def('V2D'));
    await saved.add('b.medef', _def('V3'));
    final index = jsonDecode(utf8.decode(storage.files['definitions/index.json']!)) as Map<String, dynamic>;
    storage.files[index['a.medef'] as String] = Uint8List.fromList(utf8.encode('not xml'));
    final again = SavedDefinitions(storage, DefinitionLibrary());
    expect(await again.restore(), ['a.medef']);
    expect(again.library.sources, ['b.medef']);
  });

  test('nothing saved yet restores nothing', () async {
    expect(await SavedDefinitions(_MemoryStorage(), DefinitionLibrary()).restore(), isEmpty);
  });
}
