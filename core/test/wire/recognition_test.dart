import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

Future<void> main() async {
  test('recognition, reply matching and ECU requests match the TypeScript engine', () async {
    final vectors = (await loadVectors('recognition.json')).cast<Map<String, dynamic>>();
    for (final (i, v) in vectors.indexed) {
      final f = frameFromHex(v['frame'] as String);
      final factory = MessageFactory();
      final why = 'case $i ${v['frame']}';
      expect(factory.isRecognised(f), v['recognised'], reason: why);
      expect(factory.countsAsReply(f), v['countsAsReply'], reason: why);
      expect(entityId(f), v['entityId'], reason: why);
      expect(isSuccessful(f), v['successful'], reason: why);
      expect(norm(expectedReply(f)?.toJson()), v['expected'], reason: why);
      final fw = v['fwRequest'] as Map<String, dynamic>?;
      if (fw != null) {
        if (fw['error'] == true) {
          expect(() => parseFirmwareRequest(f), throwsA(isA<PayloadError>()), reason: why);
        } else {
          expect(parseFirmwareRequest(f).toJson(), fw['ok'], reason: why);
        }
      }
    }
  });

  test('a table reply matches the request for the same table only', () {
    final want = expectedReply(getTableRequest(4100))!;
    expect(want.matches(frameFromHex('0f0101000410${'0000'}')), isTrue);
    expect(want.matches(frameFromHex('0f0101000510${'0000'}')), isFalse);
    expect(want.matches(frameFromHex('0f0106000410')), isFalse);
  });
}
