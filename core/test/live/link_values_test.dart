import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

double _f(String hex) => fromHex(hex).buffer.asFloat32List()[0];

Future<void> main() async {
  final cases = (await loadVectors('link_values.json')).cast<Map<String, dynamic>>();

  test('value text, bounds and feedbacks follow the TypeScript engine (${cases.length} definitions)', () {
    for (final (n, c) in cases.indexed) {
      final definition = readDeviceFile(c['xml'] as String).definition;
      for (final l in (c['links'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final link = definition.links[l['id'] as int]!;
        final why = 'case $n link ${link.id}';
        expect(linkNameWithUnit(link), l['nameWithUnit'], reason: why);
        final feedbacks = LinkFeedbacks(link);
        for (final (k, s) in (l['steps'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
          if (s['ack'] == true) {
            feedbacks.acknowledge();
            continue;
          }
          final v = _f(s['value'] as String);
          final at = '$why step $k value $v';
          expect(linkValueText(link, v, s['decimals'] as int), s['text'], reason: at);
          expect(listedText(link, v), s['forValue'], reason: at);
          expect(isOutOfBounds(link, v), s['out'], reason: at);
          final chosen = feedbacks.select(v);
          expect(chosen ?? -1, s['feedback'], reason: at);
          if (chosen != null && link.feedbacks![chosen].constraints != null) {
            expect(feedbacks.isAcknowledged(chosen), s['acknowledged'], reason: at);
          }
        }
      }
    }
  });

  test('rounding to one decimal is half to even', () {
    expect([0.25, 0.35, -0.25, -0.35, 2.55, double.nan].map(roundOneDecimalToInt), [0, 0, 0, 0, 2, -2147483648]);
  });
}
