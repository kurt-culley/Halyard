@TestOn('vm')
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

void main() {
  test('encodes frames exactly as captured from the original tool', () {
    expect(toHex(encodeFrame(getEcuInfoRequest())), '4d4500000004000408');
    expect(toHex(encodeFrame(getTableRequest(4100))), '4d4502000001010410161f');
    expect(toHex(encodeFrame(storeTableRequest(4100))), '4d45020000010604101b2e');
  });

  test('decodes 5,000 fuzzed streams exactly as the original readers did, whatever the chunking', () {
    final cases = loadVectors('framing_fuzz.json');
    final rnd = Random(12345);
    for (final (i, c as Map<String, dynamic>) in cases.indexed) {
      final stream = fromHex(c['stream'] as String);
      final d = FrameDecoder();
      final frames = <String>[], ok = <bool>[];
      for (var p = 0; p < stream.length;) {
        final n = 1 + rnd.nextInt(16);
        for (final r in d.pushRaw(Uint8List.sublistView(stream, p, min(p + n, stream.length)))) {
          frames.add(r.frame.hex);
          ok.add(r.ok);
        }
        p += n;
      }
      expect(frames, c['frames'], reason: 'case $i');
      expect(ok, c['ok'], reason: 'case $i');
    }
  });

  test('a decoded frame re-encodes to the same bytes', () {
    final cases = loadVectors('framing_fuzz.json');
    for (final c in cases.take(500).cast<Map<String, dynamic>>()) {
      final d = FrameDecoder();
      for (final f in d.push(fromHex(c['stream'] as String))) {
        final again = FrameDecoder().pushRaw(encodeFrame(f));
        expect(again, hasLength(1));
        expect(again.single.ok, isTrue);
        expect(again.single.frame.hex, f.hex);
      }
    }
  });

  test('push hands bad checksums to onCrcError and keeps good frames', () {
    final good = encodeFrame(getEcuInfoRequest());
    final bad = Uint8List.fromList(good)..[good.length - 1] ^= 0xff;
    final errors = <RawFrame>[];
    final d = FrameDecoder()..onCrcError = errors.add;
    final frames = d.push([...bad, ...good]);
    expect(frames.map((f) => f.hex).toList(), ['000400']);
    expect(errors, hasLength(1));
    expect(errors.single.ok, isFalse);
  });

  test('the length field keeps only 16 bits', () {
    final f = Frame.request(1, 0, Uint8List(0x10003));
    final b = encodeFrame(f);
    expect(b[2], 0x03);
    expect(b[3], 0x00);
  });
}
