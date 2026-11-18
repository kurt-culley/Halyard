import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

String _bits(double v) => toHex((ByteData(4)..setFloat32(0, v, Endian.little)).buffer.asUint8List());

ReportReply _report(String hex) => MessageFactory().create(frameFromHex(hex))! as ReportReply;

const _epochFrom0001Ms = 62135596800000;

Future<void> main() async {
  final cases = (await loadVectors('playback.json')).cast<Map<String, dynamic>>();

  test('pausing, seeking back, loading and going live follow the TypeScript strip (${cases.length} cases)', () {
    for (final (i, c) in cases.indexed) {
      final store = LiveStore(readDeviceFile(c['xml'] as String).definition);
      for (final (k, s) in (c['steps'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
        switch (s['op']) {
          case 'report':
            store.apply(_report(s['frame'] as String), (s['at'] as int).toDouble());
          case 'pause':
            store.pause();
          case 'live':
            store.resume();
          case 'seek':
            store.seekBack(s['back'] as int);
          case 'load':
            store.loadRecording((
              columns: {
                for (final col in (s['columns'] as List<dynamic>).cast<List<dynamic>>())
                  col[0] as String: [
                    for (final (j, at) in (col[1] as List<dynamic>).cast<int>().indexed)
                      (
                        at + _epochFrom0001Ms,
                        fromHex(((col[2] as List<dynamic>)[j]) as String).buffer.asFloat32List()[0].toDouble(),
                      ),
                  ],
              },
              complete: true,
            ));
        }
        final why = 'case $i step $k (${s['op']})';
        expect([for (final id in store.ids) _bits(store.value(id))], s['values'], reason: why);
        expect([for (final id in store.ids) store.length(id)], s['lengths'], reason: why);
        expect(!store.isPaused, s['live'], reason: why);
        expect(
          [
            for (final b in [0, 10, 100, 1199, 1200]) store.canSeekBack(b),
          ],
          s['canSeek'],
          reason: why,
        );
      }
      for (final h in (c['histories'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final id = h['id'] as int;
        final samples = [for (var k = 0; k < store.length(id); k++) store.sample(id, k)];
        expect([for (final (at, _) in samples) at.toInt()], h['at'], reason: 'case $i link $id times');
        expect([for (final (_, v) in samples) _bits(v)], h['values'], reason: 'case $i link $id values');
      }
    }
  });

  test('while paused, reports beyond the capacity keep only the newest', () {
    final definition = readDeviceFile(cases.first['xml'] as String).definition;
    final id = definition.links.keys.first;
    final store = LiveStore(definition, capacity: 4)..pause();
    for (var k = 0; k < 10; k++) {
      store.apply(ReportReply(0, [ReportedValue(id, k.toDouble())]), k.toDouble());
    }
    expect(store.length(id), 0);
    store.resume();
    expect([for (var k = 0; k < store.length(id); k++) store.sample(id, k).$2], [6, 7, 8, 9]);
    expect(store.value(id), 9);
  });
}
