import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

Float32List _floats(String hex) => fromHex(hex).buffer.asFloat32List();

/// Same floats, NaN as NaN (its sign bit differs between platforms) and zeros by sign.
void _expectFloats(List<double> got, String want, String reason) {
  final w = _floats(want);
  expect(got.length, w.length, reason: reason);
  for (var i = 0; i < w.length; i++) {
    if (w[i].isNaN) {
      expect(got[i].isNaN, isTrue, reason: '$reason [$i]');
    } else {
      expect(got[i], w[i], reason: '$reason [$i]');
      expect(got[i].isNegative, w[i].isNegative, reason: '$reason [$i] sign');
    }
  }
}

Future<void> main() async {
  final v = (await loadVectors('presets.json')).first as Map<String, dynamic>;

  test('.mepres files read and save as the original did', () {
    for (final (i, f) in (v['files'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
      final text = f['text'] as String;
      final read = f['read'] as Map<String, dynamic>;
      if (read['error'] == true) {
        expect(() => PresetFile.read(text), throwsA(isA<PresetError>()), reason: 'file $i should fail');
        continue;
      }
      final p = PresetFile.read(text, path: r'C:\presets\x.mepres');
      final ok = read['ok'] as Map<String, dynamic>;
      final tables = (ok['tables'] as List<dynamic>).cast<List<dynamic>>();
      expect(p.tables.length, tables.length, reason: 'file $i');
      for (final (k, t) in tables.indexed) {
        final got = p.tables[k];
        expect(
          [got.name, got.description, got.compatibleIds],
          [t[0] ?? '', t[1] ?? '', t[2] ?? <int>[]],
          reason: 'file $i',
        );
        _expectFloats(got.input0, t[3] as String, 'file $i table $k input0');
        _expectFloats(got.input1, t[4] as String, 'file $i table $k input1');
        _expectFloats(got.output, t[5] as String, 'file $i table $k output');
      }
      expect(
        [
          for (final d in p.drivers) [d.name, d.description, d.compatibleIds],
        ],
        ok['drivers'],
        reason: 'file $i',
      );
      expect(p.write(), read['saved'], reason: 'file $i saved');
    }
  });

  test('a table saved as a preset', () {
    for (final (i, c) in (v['fromTables'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
      final x = _floats(c['x'] as String), y = _floats(c['y'] as String), z = _floats(c['z'] as String);
      final d = TableDef(
        id: c['id'] as int,
        name: c['name'] as String?,
        cols: x.length,
        rows: y.isEmpty ? 1 : y.length,
      );
      final values = TableValues(enabled: true, x: x, y: y, z: z);
      if (c['error'] == true) {
        expect(() => TablePreset.fromTable(d, values), throwsA(isA<PresetError>()), reason: 'table $i should fail');
        continue;
      }
      final preset = TablePreset.fromTable(d, values);
      expect(preset.name, c['name'] ?? '', reason: 'table $i');
      expect(PresetFile(tables: [preset]).write(), c['ok'], reason: 'table $i');
    }
  });

  test('the import list and its search', () {
    final library = PresetLibrary();
    for (final f in (v['files'] as List<dynamic>).take(40).cast<Map<String, dynamic>>()) {
      if ((f['read'] as Map<String, dynamic>)['error'] == true) continue;
      final text = f['text'] as String;
      library.add(PresetFile.read(text, path: 'C:\\p\\${text.length}.mepres'));
    }
    for (final (i, s) in (v['searches'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
      final rows = presetRows(library.presetsFor(s['id'] as int), s['search'] as String?);
      expect(
        [
          for (final r in rows) [r.source, r.name, r.details],
        ],
        s['items'],
        reason: 'search $i',
      );
    }
  });

  test('removing a file takes its presets out of the library', () {
    final f = PresetFile(
      tables: [
        TablePreset(compatibleIds: [7], input0: Float32List(2), input1: Float32List(0), output: Float32List(2)),
      ],
    );
    final library = PresetLibrary()..add(f);
    expect(library.presetsFor(7), hasLength(1));
    library.remove(f);
    expect(library.presetsFor(7), isEmpty);
  });
}
