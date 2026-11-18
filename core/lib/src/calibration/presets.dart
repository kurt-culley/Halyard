/// Table presets (U28g): `.mepres` files of table values, each marked with the table ids it fits, a library of them
/// by table id, and the import list's search. Halyard ships no presets; the library holds the user's own files.
library;

import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../definition/definition.dart';
import '../definition/xml_convert.dart';
import '../logs/number_text.dart';
import 'calibration.dart';

/// A preset file that can't be read, or a table that can't become a preset.
class PresetError implements Exception {
  const PresetError(this.message);
  final String message;
  @override
  String toString() => 'PresetError: $message';
}

/// The axis sizes a table preset may have: curves of 2, 16 or 32 and square maps of 8, 16 or 32.
bool validPresetSizes(int n0, int n1) => switch ((n0, n1)) {
  (2, 0) || (16, 0) || (32, 0) || (8, 8) || (16, 16) || (32, 32) => true,
  _ => false,
};

final class TablePreset {
  TablePreset({
    this.name = '',
    this.description = '',
    this.compatibleIds = const [],
    required this.input0,
    required this.input1,
    required this.output,
  });

  /// A table's current values as a preset for that table; its name is also the description. A curve has no row axis.
  factory TablePreset.fromTable(TableDef d, TableValues v) {
    final i1 = v.y.length == 1 ? Float32List(0) : Float32List.fromList(v.y);
    if (!validPresetSizes(v.x.length, i1.length)) throw const PresetError('Invalid table');
    return TablePreset(
      name: d.name ?? '',
      description: d.name ?? '',
      compatibleIds: [d.id],
      input0: Float32List.fromList(v.x),
      input1: i1,
      output: Float32List.fromList(v.z),
    );
  }

  final String name, description;
  final List<int> compatibleIds;
  final Float32List input0, input1, output;
}

/// Kept so a file the user saves again loses nothing; drivers have no values in the file.
final class DriverPreset {
  const DriverPreset({this.name = '', this.description = '', this.compatibleIds = const []});
  final String name, description;
  final List<int> compatibleIds;
}

final class PresetFile {
  PresetFile({this.path, this.tables = const [], this.drivers = const []});

  /// Reads a `.mepres` file. Any table whose axes aren't a preset size fails the whole file, as in the original.
  factory PresetFile.read(String xml, {String? path}) {
    final XmlElement root;
    try {
      root = XmlDocument.parse(normaliseXmlSource(xml.startsWith('﻿') ? xml.substring(1) : xml)).rootElement;
    } on XmlException catch (e) {
      throw PresetError('not well-formed XML: ${e.message}');
    }
    final ns = root.getAttribute('xmlns');
    if (root.name.qualified != 'Presets' || (ns != null && ns.isNotEmpty)) {
      throw PresetError('<${root.name.qualified}> is not a presets file');
    }
    final tables = <TablePreset>[], drivers = <DriverPreset>[];
    try {
      readMembers(root, {
        'Tables': (x) => tables.addAll(readArray(x, {'TablePreset': _table})),
        'Drivers': (x) => drivers.addAll(readArray(x, {'DriverPreset': _driver})),
      });
    } on XmlValueError catch (e) {
      throw PresetError(e.toString());
    }
    return PresetFile(path: path, tables: tables, drivers: drivers);
  }

  final String? path;
  final List<TablePreset> tables;
  final List<DriverPreset> drivers;

  /// The file name without folder or extension, shown as the preset's source.
  String get sourceName {
    final p = path;
    if (p == null) return '';
    final name = p.substring(p.lastIndexOf(RegExp(r'[/\\]')) + 1);
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(0, dot) : name;
  }

  /// The file text as the original wrote it.
  String write() {
    final o = <String>['<Presets>'];
    void str(String n, String v) => o.add(v.isEmpty ? '      <$n />' : '      <$n>${_escape(v)}</$n>');
    void arr(String n, String item, List<num> v, String Function(num) fmt) {
      if (v.isEmpty) {
        o.add('      <$n />');
        return;
      }
      o
        ..add('      <$n>')
        ..addAll(v.map((x) => '        <$item>${fmt(x)}</$item>'))
        ..add('      </$n>');
    }

    void list<T>(String n, String item, List<T> v, void Function(T) each) {
      if (v.isEmpty) {
        o.add('  <$n />');
        return;
      }
      o.add('  <$n>');
      for (final x in v) {
        o.add('    <$item>');
        each(x);
        o.add('    </$item>');
      }
      o.add('  </$n>');
    }

    String f(num x) => formatFloatR(x.toDouble());
    String u(num x) => '$x';
    list<TablePreset>('Tables', 'TablePreset', tables, (t) {
      str('Name', t.name);
      str('Description', t.description);
      arr('CompatibleIds', 'unsignedShort', t.compatibleIds, u);
      arr('Input0', 'float', t.input0, f);
      arr('Input1', 'float', t.input1, f);
      arr('Output', 'float', t.output, f);
    });
    list<DriverPreset>('Drivers', 'DriverPreset', drivers, (d) {
      str('Name', d.name);
      str('Description', d.description);
      arr('CompatibleIds', 'unsignedShort', d.compatibleIds, u);
    });
    o.add('</Presets>');
    return o.join('\r\n');
  }
}

String _escape(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

TablePreset _table(XmlElement e) {
  String? name, description;
  List<int>? ids;
  List<double>? i0, i1, out;
  readMembers(e, {
    'Name': (x) => name = directText(x),
    'Description': (x) => description = directText(x),
    'CompatibleIds': (x) => ids = readUShorts(x),
    'Input0': (x) => i0 = readFloats(x),
    'Input1': (x) => i1 = readFloats(x),
    'Output': (x) => out = readFloats(x),
  });
  if (!validPresetSizes(i0?.length ?? 0, i1?.length ?? 0)) throw const PresetError('Invalid table');
  return TablePreset(
    name: name ?? '',
    description: description ?? '',
    compatibleIds: ids ?? const [],
    input0: Float32List.fromList(i0 ?? const []),
    input1: Float32List.fromList(i1 ?? const []),
    output: Float32List.fromList(out ?? const []),
  );
}

DriverPreset _driver(XmlElement e) {
  String? name, description;
  List<int>? ids;
  readMembers(e, {
    'Name': (x) => name = directText(x),
    'Description': (x) => description = directText(x),
    'CompatibleIds': (x) => ids = readUShorts(x),
  });
  return DriverPreset(name: name ?? '', description: description ?? '', compatibleIds: ids ?? const []);
}

typedef PresetEntry = ({PresetFile file, TablePreset preset});

/// The presets the user has, by the table ids they fit, in the order they were added.
final class PresetLibrary {
  final _byId = <int, List<PresetEntry>>{};

  void add(PresetFile f) {
    for (final t in f.tables) {
      for (final id in t.compatibleIds) {
        (_byId[id] ??= []).add((file: f, preset: t));
      }
    }
  }

  void remove(PresetFile f) {
    for (final l in _byId.values) {
      l.removeWhere((e) => identical(e.file, f));
    }
  }

  List<PresetEntry> presetsFor(int tableId) => List.of(_byId[tableId] ?? const []);
}

/// A row of the import list: source file, name and details, without tabs or line ends.
typedef PresetRow = ({String source, String name, String details, TablePreset preset});

final _breaks = RegExp('[\t\n\r]');

/// The import list for [entries], keeping those whose source, name or description contains [search] (any case).
List<PresetRow> presetRows(List<PresetEntry> entries, String? search) {
  final s = search?.toLowerCase() ?? '';
  return [
    for (final e in entries)
      if (s.isEmpty ||
          e.file.sourceName.toLowerCase().contains(s) ||
          e.preset.name.toLowerCase().contains(s) ||
          e.preset.description.toLowerCase().contains(s))
        (
          source: e.file.sourceName,
          name: e.preset.name.replaceAll(_breaks, ''),
          details: e.preset.description.replaceAll(_breaks, ''),
          preset: e.preset,
        ),
  ];
}
