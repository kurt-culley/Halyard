import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

String _f64(double v) => v.isNaN ? 'NaN' : toHex((ByteData(8)..setFloat64(0, v, Endian.little)).buffer.asUint8List());

String _try(double Function() f) {
  try {
    return _f64(f());
  } on Object {
    return 'error';
  }
}

List<List<Object?>> _props(Map<String, DbcProperty> p) => [
  for (final e in p.entries)
    [
      e.key,
      {
        'type': e.value.definition.type.index,
        'integer': e.value.integer,
        'hex': e.value.hex,
        'float': e.value.float == null ? null : _f64(e.value.float!),
        'string': e.value.string,
        'enumValue': e.value.enumValue,
      },
    ],
];

Future<void> main() async {
  final v = (await loadVectors('dbc.json')).first as Map<String, dynamic>;

  test('.NET number parsing', () {
    for (final n in (v['numbers'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final t = n['t'] as String;
      String want(String h) =>
          h != 'error' && ByteData.sublistView(fromHex(h)).getFloat64(0, Endian.little).isNaN ? 'NaN' : h;
      expect(_try(() => parseNetDouble(t)), want(n['d'] as String), reason: 'double "$t"');
      expect(_try(() => parseNetSingle(t)), want(n['f'] as String), reason: 'single "$t"');
    }
  });

  test('DBC files read as the parser the original bundled', () {
    for (final (i, f) in (v['files'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
      final text = f['text'] as String;
      if (f['error'] == true) {
        expect(() => parseDbc(text), throwsA(anything), reason: 'file $i should fail');
        continue;
      }
      final got = [
        for (final m in parseDbc(text))
          {
            'id': m.id,
            'ext': m.isExtended,
            'name': m.name,
            'dlc': m.dlc,
            'tx': m.transmitter,
            'props': _props(m.properties),
            'signals': [
              for (final s in m.signals)
                {
                  'name': s.name,
                  'mux': s.multiplexing,
                  'start': s.startBit,
                  'len': s.length,
                  'order': s.byteOrder,
                  'type': s.valueType.index,
                  'isInt': s.isInteger,
                  'factor': _f64(s.factor),
                  'offset': _f64(s.offset),
                  'min': _f64(s.minimum),
                  'max': _f64(s.maximum),
                  'unit': s.unit,
                  'rx': s.receivers,
                  'props': _props(s.properties),
                },
            ],
          },
      ];
      expect(got, f['messages'], reason: 'file $i\n$text');
    }
  });
}
