/// Keeping the user's definitions between runs: each is saved once by content hash in the app's storage, with an
/// index of where it came from, and loaded back into the [DefinitionLibrary] at start.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../session/host_files.dart';
import 'definition_library.dart';
import 'device_file.dart';

final class SavedDefinitions {
  SavedDefinitions(this._storage, this.library);

  final AppStorage _storage;
  final DefinitionLibrary library;

  /// Source → file name in storage.
  final _index = <String, String>{};

  static const _folder = 'definitions';
  static const _indexName = '$_folder/index.json';

  /// Loads the saved definitions; returns the sources that could not be read back.
  Future<List<String>> restore() async {
    final failed = <String>[];
    final raw = await _storage.read(_indexName);
    if (raw == null) return failed;
    final Map<String, dynamic> index;
    try {
      index = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    } on FormatException {
      return failed;
    }
    for (final MapEntry(key: source, value: name) in index.entries) {
      if (name is! String) continue;
      final bytes = await _storage.read(name);
      try {
        if (bytes == null) throw const FormatException('missing');
        library.add(source, utf8.decode(bytes));
        _index[source] = name;
      } on Object {
        failed.add(source);
      }
    }
    return failed;
  }

  /// Reads a definition into the library and saves it. Throws [DeviceFileError] for a file that isn't one.
  Future<DeviceFile> add(String source, String xml) async {
    final file = library.add(source, xml);
    final bytes = Uint8List.fromList(utf8.encode(xml));
    final name = '$_folder/${sha256.convert(bytes)}.medef';
    final old = _index[source];
    await _storage.write(name, bytes);
    _index[source] = name;
    await _saveIndex();
    if (old != null && old != name && !_index.containsValue(old)) await _storage.delete(old);
    return file;
  }

  Future<void> remove(String source) async {
    library.remove(source);
    final name = _index.remove(source);
    await _saveIndex();
    if (name != null && !_index.containsValue(name)) await _storage.delete(name);
  }

  Future<void> _saveIndex() => _storage.write(_indexName, Uint8List.fromList(utf8.encode(jsonEncode(_index))));
}
