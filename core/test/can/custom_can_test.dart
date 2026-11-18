import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

/// The TypeScript project's wording, to compare typed issues with its vectors.
String _english(CanIssue i) {
  String hex(int v) => v.toRadixString(16).toUpperCase();
  final n = (i.signal ?? 0) + 1;
  return switch (i.kind) {
    CanIssueKind.idOutOfRange =>
      'CAN ID 0x${hex(i.a)} is outside the ${i.extended ? 'extended' : 'standard'} range (max 0x${hex(i.b)}).',
    CanIssueKind.idReserved => 'CAN ID 0x${hex(i.a)} is used by the selected OEM CAN stream.',
    CanIssueKind.muxLength => 'Mux selector length ${i.a} is outside 1-32.',
    CanIssueKind.muxSpan => 'Mux selector at bit ${i.a} length ${i.b} does not fit the frame.',
    CanIssueKind.signalSpan => 'Signal $n at bit ${i.a} length ${i.b} does not fit the frame.',
    CanIssueKind.signalMultiplier => 'Signal $n multiplier must be non-zero and finite.',
    CanIssueKind.signalFloatLength => 'Signal $n is float32 and must be exactly 32 bits, not ${i.a}.',
    CanIssueKind.signalNoTarget => 'Signal $n has no target channel.',
    CanIssueKind.signalTargetMissing => 'Signal $n target channel ${i.a} does not exist.',
    CanIssueKind.rate => 'Rate ${i.a} Hz is outside 1-1000.',
    CanIssueKind.unknownMode => 'Unknown transmit mode.',
    CanIssueKind.noTrigger => 'Event-driven mode needs a trigger channel.',
    CanIssueKind.triggerMissing => 'Trigger channel ${i.a} does not exist.',
    CanIssueKind.sourceMissing =>
      'Signal $n source channel ${i.a} does not exist; its constant value is transmitted instead.',
  };
}

Future<void> main() async {
  simulatorReservedIds((await loadVectors('sim_can.json')).cast<Map<String, dynamic>>());
  final v = (await loadVectors('custom_can.json')).first as Map<String, dynamic>;
  List<Map<String, dynamic>> part(String k) => (v[k] as List<dynamic>).cast<Map<String, dynamic>>();

  test('bit packing in both orders', () {
    for (final (i, b) in part('bits').indexed) {
      final frame = fromHex(b['frame'] as String);
      final (start, len, be) = (b['start'] as int, b['len'] as int, b['be'] as bool);
      final why = 'case $i start $start len $len be $be';
      expect(spanValid(start, len, bigEndian: be), b['valid'], reason: why);
      final x = extractBits(frame, start, len, bigEndian: be);
      expect(x.toRadixString(16), b['extract'], reason: why);
      expect(signExtend(x, len).toRadixString(16), b['signed'], reason: why);
      final packed = Uint8List.fromList(frame);
      packBits(packed, start, len, BigInt.parse(b['value'] as String, radix: 16), bigEndian: be);
      expect(toHex(packed), b['packed'], reason: why);
    }
  });

  test('CAN id text', () {
    for (final c in part('ids')) {
      final id = tryParseCanId(c['text'] as String);
      expect(id, c['id'], reason: '"${c['text']}"');
      if (id != null) {
        expect(isExtendedCanId(id), c['ext']);
        expect(formatCanId(id), c['fmt']);
      }
    }
  });

  test('the configuration blob and the checks match the TypeScript module', () {
    final links = {1, 2, 3};
    for (final (i, c) in part('configs').indexed) {
      final blob = fromHex(c['blob'] as String);
      final config = CustomCanConfig.decode(blob);
      // Decoding clamps rates to 1-1000 Hz; the vectors' configurations weren't clamped, so restore what was sent.
      const rxSize = 12 + 8 * 19, txSize = 12 + 8 * 17;
      for (final (k, m) in config.tx.indexed) {
        final o = 4 + 12 * rxSize + k * txSize + 6;
        m.freqHz = blob[o] | (blob[o + 1] << 8);
      }
      expect(toHex(config.encode()), c['blob'], reason: 'config $i round trip');
      final reservedUsed =
          c['rx'].toString().contains('OEM CAN stream') || c['tx'].toString().contains('OEM CAN stream');
      // The vectors don't record whether the reserved set was passed; try both and require one to match exactly.
      bool matches(Set<int>? reserved) {
        final r = checkCustomCan(config, links.contains, reserved);
        List<Map<String, List<String>>> words(List<CanCheck> l) => [
          for (final x in l)
            {
              'errors': [for (final e in x.errors) _english(e)],
              'warnings': [for (final w in x.warnings) _english(w)],
            },
        ];
        return words(r.rx).toString() == (c['rx'] as List<dynamic>).toString() &&
            words(r.tx).toString() == (c['tx'] as List<dynamic>).toString();
      }

      expect(matches({0x700, 0x340, 0x1ba}) || (!reservedUsed && matches(null)), isTrue, reason: 'config $i checks');
      final mutated = CustomCanConfig.decode(fromHex(c['mutated'] as String));
      expect(mutated.wasReset, c['wasReset'], reason: 'config $i');
      expect(toHex(mutated.encode()), c['reencoded'], reason: 'config $i decoded');
    }
  });

  test('ids reserved by the OEM streams', () {
    for (final (i, r) in part('reservedIds').indexed) {
      final params = (r['params'] as List<dynamic>).cast<List<dynamic>>();
      final d = DriverDef(
        id: 8224,
        params: [for (final p in params) ParamDef(name: p[0] as String)],
        configCount: params.length,
      );
      final config = Float32List.fromList([
        for (final p in params) ByteData.sublistView(fromHex(p[1] as String)).getFloat32(0, Endian.little),
      ]);
      expect(
        [
          for (final e in reservedCanIds(d, config))
            {
              'messageId': e.messageId,
              'streamReceives': e.receives,
              'streamTransmits': e.transmits,
              'secondaryStream': e.secondary,
            },
        ],
        r['ids'],
        reason: 'case $i',
      );
    }
  });
}

/// Kept separate so the simulator's reply is checked against the TypeScript one.
void simulatorReservedIds(List<Map<String, dynamic>> cases) {
  test('the simulator answers 2/3 with the ids its CAN settings reserve', () {
    for (final (i, c) in cases.indexed) {
      final out = <String>[];
      final decoder = FrameDecoder();
      final ecu = SimEcu(readDeviceFile(c['xml'] as String).calibration)
        ..attach((b) => out.addAll([for (final r in decoder.pushRaw(b)) r.frame.hex]));
      ecu.handle(getCanReservedIdsRequest());
      expect(out, c['replies'], reason: 'case $i');
    }
  });
}
