import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

String _bits(double v) => toHex((ByteData(4)..setFloat32(0, v, Endian.little)).buffer.asUint8List());
double _fromBits(String hex) => ByteData.sublistView(fromHex(hex)).getFloat32(0, Endian.little);

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}T${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
String _two(int n) => n.toString().padLeft(2, '0');

Future<void> main() async {
  final v = (await loadVectors('faults.json')).first as Map<String, dynamic>;
  List<Map<String, dynamic>> part(String k) => (v[k] as List<dynamic>).cast<Map<String, dynamic>>();

  test('catalogue lookups match the TypeScript module', () {
    for (final l in part('lookups')) {
      final c = faultCode(l['code'] as int);
      expect(
        [c.index, c.name, c.kind.index, c.severity, c.isKnown],
        [l['index'], l['name'], l['kind'], l['severity'], l['known']],
        reason: 'code ${l['code']}',
      );
    }
  });

  test('hour and clock stamps', () {
    for (final s in part('stamps')) {
      final x = s['x'] as int;
      expect(_bits(faultHours(x)), s['hours'], reason: 'hours $x');
      if (s['rtc'] == 'error') {
        expect(() => faultRtc(x), throwsRangeError, reason: 'rtc $x');
      } else {
        final d = faultRtc(x);
        expect(d == null ? null : _iso(d), s['rtc'], reason: 'rtc $x');
      }
    }
  });

  test('record bodies: modes and checkpoints', () {
    for (final (i, r) in part('records').indexed) {
      final body = fromHex(r['body'] as String);
      final rec = FaultLogRecord(
        ordinal: 0,
        magic: r['magic'] as int,
        type: r['type'] as int,
        catalogueVersion: 1,
        seq: 0,
        code: 0,
        count: 0,
        lifetime: 0,
        hoursX100: 0,
        rtc: 0,
        bodyLength: body.length,
        slotSize: 64,
        body: body,
      );
      expect(rec.isValid, r['valid'], reason: 'record $i');
      expect(rec.oldMode, r['oldMode'], reason: 'record $i');
      expect(rec.newMode, r['newMode'], reason: 'record $i');
      expect(rec.checkpointHoursX100, r['checkpointHours'], reason: 'record $i');
      expect(
        [
          for (final e in rec.checkpointEntries)
            {
              'code': e.code,
              'count': e.count,
              'lifetime': e.lifetime,
              'firstHoursX100': e.firstHoursX100,
              'firstRtc': e.firstRtc,
              'lastHoursX100': e.lastHoursX100,
              'lastRtc': e.lastRtc,
            },
        ],
        r['entries'],
        reason: 'record $i',
      );
    }
  });

  test('freeze frames decode as the TypeScript module does', () {
    for (final (i, f) in part('frames').indexed) {
      final layout = [
        for (final e in (f['layout'] as List<dynamic>).cast<List<dynamic>>())
          FrameChannel(e[0] as int, e[1] as int, e[2] as int?),
      ];
      final got = decodeFreezeFrame(layout, fromHex(f['body'] as String));
      expect(
        [
          for (final (id, value) in got) [id, _bits(value)],
        ],
        f['values'],
        reason: 'frame $i',
      );
    }
  });

  test('active codes from the three bit links', () {
    for (final (i, a) in part('actives').indexed) {
      final x = [for (final h in (a['values'] as List<dynamic>).cast<String>()) _fromBits(h)];
      expect(activeFaultIndexes(x[0], x[1], x[2]).toList()..sort(), a['active'], reason: 'case $i');
    }
  });

  final sessions = (await loadVectors('sim_faults.json')).cast<Map<String, dynamic>>();
  test('the simulated fault log answers as the TypeScript one (${sessions.length} sessions)', () {
    for (final (i, s) in sessions.indexed) {
      final o = s['options'] as Map<String, dynamic>;
      final out = <String>[];
      final decoder = FrameDecoder();
      final ecu = SimEcu(
        readDeviceFile(s['xml'] as String).calibration,
        uuid: o['uuid'] as String,
        fwVersion: o['fwVersion'] as String,
        engineStopped: o['engineStopped'] as bool,
        now: () => DateTime.fromMillisecondsSinceEpoch(s['now'] as int, isUtc: true),
      )..attach((b) => out.addAll([for (final r in decoder.pushRaw(b)) r.frame.hex]));
      if (s['seeded'] as bool) ecu.faults.seed();
      for (final (k, step) in (s['steps'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
        out.clear();
        switch (step) {
          case {'send': final String hex}:
            ecu.handle(frameFromHex(hex));
          case {'op': 'report'}:
            ecu.report();
        }
        expect(out, step['replies'], reason: 'session $i step $k ${step['send'] ?? step['op']}');
      }
      ecu.attach(null);
    }
  });
}
