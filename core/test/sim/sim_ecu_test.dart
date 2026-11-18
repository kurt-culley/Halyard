import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

/// A simulator whose replies are collected as hex and whose clock is set by the test.
({SimEcu ecu, List<String> out, void Function(int ms) setClock}) _sim(String xml, Map<String, dynamic> o) {
  var now = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final out = <String>[];
  final decoder = FrameDecoder();
  final (definition: _, :calibration) = readDeviceFile(xml);
  final ecu = SimEcu(
    calibration,
    uuid: o['uuid'] as String,
    fwVersion: o['fwVersion'] as String,
    reportPeriod: Duration(milliseconds: o['reportMs'] as int),
    engineStopped: o['engineStopped'] as bool,
    now: () => now,
  )..attach((b) => out.addAll([for (final r in decoder.pushRaw(b)) r.frame.hex]));
  return (ecu: ecu, out: out, setClock: (ms) => now = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
}

Future<void> main() async {
  final sessions = (await loadVectors('simulator.json')).cast<Map<String, dynamic>>();

  test('answers scripted sessions exactly as the TypeScript simulator (${sessions.length} sessions)', () {
    fakeAsync((_) {
      for (final (i, s) in sessions.indexed) {
        final (:ecu, :out, :setClock) = _sim(s['xml'] as String, s['options'] as Map<String, dynamic>);
        for (final (k, step) in (s['steps'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
          setClock(step['at'] as int);
          out.clear();
          switch (step) {
            case {'send': final String hex}:
              ecu.handle(frameFromHex(hex));
            case {'op': 'report'}:
              ecu.report();
            case {'op': 'triggerReport'}:
              ecu.trigger.report();
            case {'op': 'seedDataLogging'}:
              ecu.dataLog.seed();
          }
          expect(out, step['replies'], reason: 'session $i step $k ${step['send'] ?? step['op']}');
        }
        ecu.attach(null);
      }
    });
  });

  test('reports on its own while reporting is on, and stops when detached', () {
    fakeAsync((async) {
      final s = sessions.first;
      final (:ecu, :out, setClock: _) = _sim(s['xml'] as String, s['options'] as Map<String, dynamic>);
      ecu.handle(setStateRequest(true));
      out.clear();
      async.elapse(const Duration(milliseconds: 350));
      expect(out.where((h) => h.startsWith('0f0000')), hasLength(3));
      ecu.attach(null);
      out.clear();
      async.elapse(const Duration(seconds: 1));
      expect(out, isEmpty);
      expect(ecu.reporting, isFalse);
    });
  });

  test('the connection finds it at its own baud rate and reads its identity', () {
    fakeAsync((async) {
      final s = sessions.first;
      final (:ecu, out: _, setClock: _) = _sim(s['xml'] as String, s['options'] as Map<String, dynamic>);
      ecu.attach(null);
      final c = Connection((baud) => openSimulator(ecu, baud));
      c.connect();
      async.flushMicrotasks();
      expect(c.state, const LinkState(LinkPhase.connected, baudRate: 230400));
      late RequestResult r;
      c.channel.request(getEcuInfoRequest()).then((x) => r = x);
      async.flushMicrotasks();
      expect(r.ok, isTrue);
      expect(r.reply, isA<EcuInfoReply>());
      expect((r.reply! as EcuInfoReply).uuid, 'SIM-0');
      c.disconnect();
      async.flushMicrotasks();
    });
  });

  test('a request it cannot apply goes unanswered and the link stays up', () {
    fakeAsync((async) {
      final s = sessions.first;
      final (:ecu, out: _, setClock: _) = _sim(s['xml'] as String, s['options'] as Map<String, dynamic>);
      final t = SimTransport(ecu, 230400);
      final got = <Uint8List>[];
      t.input.listen(got.add);
      final id = ecu.definition.tables.keys.first;
      t.write(encodeFrame(setTableRequest(id, Uint8List.fromList([0xff, 0, 0, 0]))));
      async.flushMicrotasks();
      expect(got, isEmpty);
      t.write(encodeFrame(getEcuInfoRequest()));
      async.flushMicrotasks();
      expect(got, hasLength(1));
    });
  });
}
