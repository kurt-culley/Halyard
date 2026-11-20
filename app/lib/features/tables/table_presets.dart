import 'dart:convert';
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';

/// The user's preset files, kept in app storage as `presets/<name>` with an index, in the order they were added.
/// Halyard ships none; the original's built-in library was the vendor's.
class TablePresets {
  TablePresets(this._storage);

  final AppStorage _storage;
  final library = PresetLibrary();
  final _files = <String, PresetFile>{};
  bool _loaded = false;

  static const _index = 'presets/index.json';

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _storage.read(_index);
      final names = raw == null ? const <String>[] : (jsonDecode(utf8.decode(raw)) as List<dynamic>).cast<String>();
      for (final n in names) {
        final bytes = await _storage.read('presets/$n');
        if (bytes == null) continue;
        try {
          _add(n, PresetFile.read(utf8.decode(bytes), path: n));
        } on PresetError {
          // An unreadable file is left out of the library.
        }
      }
    } on Object {
      // A broken index leaves the library empty.
    }
  }

  void _add(String name, PresetFile f) {
    final old = _files[name];
    if (old != null) library.remove(old);
    _files[name] = f;
    library.add(f);
  }

  Future<void> _saveIndex() =>
      _storage.write(_index, Uint8List.fromList(utf8.encode(jsonEncode(_files.keys.toList()))));

  /// Adds a preset file the user picked; throws [PresetError] when it isn't one.
  Future<void> addFile(String name, String text) async {
    final f = PresetFile.read(text, path: name);
    await _storage.write('presets/$name', Uint8List.fromList(utf8.encode(text)));
    _add(name, f);
    await _saveIndex();
  }

  /// Saves [table] as a preset file named [name] (".mepres" added when it has no extension), as the original's
  /// "Save as preset" did; throws [PresetError] for a table size presets can't hold.
  Future<String> save(String name, TableDef d, TableValues v) async {
    var n = name.trim().replaceAll(RegExp(r'[\\/]'), '_');
    if (!RegExp(r'\.[^.]+$').hasMatch(n)) n += '.mepres';
    final file = PresetFile(path: n, tables: [TablePreset.fromTable(d, v)], drivers: const []);
    await addFile(n, file.write());
    return n;
  }

  List<PresetRow> rows(int tableId, String search) => presetRows(library.presetsFor(tableId), search);
}
