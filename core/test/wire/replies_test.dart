import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

Future<void> main() async {
  test('parses replies of classes 1–9 exactly as the TypeScript engine does', () async {
    final vectors = (await loadVectors('replies.json')).cast<Map<String, dynamic>>();
    for (final (i, v) in vectors.indexed) {
      final f = frameFromHex(v['frame'] as String);
      final got = MessageFactory().create(f);
      expect(norm(got?.toJson()), v['reply'], reason: 'case $i ${v['frame']}');
    }
  });

  test('decodes live-data sequences through one factory, keeping the layout between frames', () async {
    final vectors = (await loadVectors('reporting.json')).cast<Map<String, dynamic>>();
    for (final (i, v) in vectors.indexed) {
      final factory = MessageFactory();
      final frames = (v['frames'] as List<dynamic>).cast<String>();
      final replies = v['replies'] as List<dynamic>;
      for (var k = 0; k < frames.length; k++) {
        final got = factory.create(frameFromHex(frames[k]));
        expect(norm(got?.toJson()), replies[k], reason: 'sequence $i frame $k ${frames[k]}');
      }
    }
  });

  test('a frame is parsed once, however often it is asked about', () {
    final factory = MessageFactory();
    // SetState v2 (status, count 1, link id 1 as uint16), then a report holding 0x1234
    final layout = frameFromHex(
      '0f0002'
      '00'
      '0100'
      '0100'
      '02',
    );
    final report = frameFromHex(
      '0f0000'
      '00'
      '3412',
    );
    expect(factory.create(layout), isNotNull);
    final first = factory.create(report);
    expect(identical(factory.create(report), first), isTrue);
    expect(factory.isRecognised(report), isTrue);
    expect((first! as ReportReply).entities.single.value, 0x1234);
  });

  test('identity text decodes invalid UTF-8 the WHATWG way', () {
    String d(List<int> b) => decodeUtf8(fromHex(toHex(b)));
    expect(d([0x61, 0xff, 0x62]), 'a�b');
    expect(d([0xe2, 0x82]), '�');
    expect(d([0xe2, 0x82, 0x41]), '�A');
    expect(d([0xed, 0xa0, 0x80]), '���');
    expect(d([0xf0, 0x9f, 0x98, 0x80]), '😀');
    expect(d([0xc0, 0xaf]), '��');
  });
}
