import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

double _f32(String hex) => ByteData.sublistView(fromHex(hex)).getFloat32(0, Endian.little);

Future<void> main() async {
  final v = (await loadVectors('pc_logging.json')).first as Map<String, dynamic>;

  test('"F" number text for floats and doubles', () {
    for (final f in (v['fixed'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final d = ByteData.sublistView(fromHex(f['v'] as String)).getFloat64(0, Endian.little);
      final n = f['decimals'] as int;
      expect(formatFixed(fround(d), n), f['f'], reason: '$d F$n float');
      expect(formatFixed(d, n, isFloat: false), f['d'], reason: '$d F$n double');
    }
  });

  test('header and lines as the original wrote them', () {
    for (final (i, c) in (v['lines'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
      final delimiter = c['delimiter'] as String;
      final names = (c['names'] as List<dynamic>).cast<String?>();
      final links = [for (final (k, n) in names.indexed) LinkDef(id: k + 1, name: n)];
      expect(pcLogHeader(links, delimiter: delimiter), c['header'], reason: 'case $i');
      final values = [for (final h in (c['values'] as List<dynamic>).cast<String>()) _f32(h)];
      expect(
        pcLogLine((c['elapsedMs'] as int) / 1000, values, marker: c['marker'] as bool, delimiter: delimiter),
        c['line'],
        reason: 'case $i',
      );
    }
  });

  test('the recorder samples the live store at its rate and marks one line', () {
    fakeAsync((async) {
      final d = Definition(
        info: const DeviceInfo(),
        links: {1: const LinkDef(id: 1, name: 'RPM'), 2: const LinkDef(id: 2, name: 'MAP')},
        tables: const {},
        drivers: const {},
      );
      final live = LiveStore(d)
        ..apply(ReportReply(0, [const ReportedValue(1, 1500.25), const ReportedValue(2, 98.5)]), 0);
      final out = StringBuffer();
      final start = DateTime.utc(2026);
      final r = PcLogRecorder(
        live: live,
        channels: pcLogChannels(d, [2, 9, 1]),
        write: out.write,
        frequency: 10,
        now: () => start.add(async.elapsed),
      )..start();
      async.elapse(const Duration(milliseconds: 250));
      r.mark();
      async.elapse(const Duration(milliseconds: 100));
      r.stop();
      async.elapse(const Duration(seconds: 1));
      expect(
        out.toString(),
        'Time, Marker, MAP, RPM\r\n'
        '0.10,0,98.50,1500.25\r\n'
        '0.20,0,98.50,1500.25\r\n'
        '0.30,1,98.50,1500.25\r\n',
      );
    });
  });
}
