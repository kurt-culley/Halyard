import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

String _bits(double v) => toHex((ByteData(4)..setFloat32(0, v, Endian.little)).buffer.asUint8List());

ReportReply _report(String hex) => MessageFactory().create(frameFromHex(hex))! as ReportReply;

Future<void> main() async {
  final cases = (await loadVectors('live.json')).cast<Map<String, dynamic>>();

  test('values and history follow the TypeScript handler (${cases.length} cases)', () {
    for (final (i, c) in cases.indexed) {
      final definition = readDeviceFile(c['xml'] as String).definition;
      final store = LiveStore(definition);
      for (final (k, s) in (c['steps'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
        store.apply(_report(s['frame'] as String), (s['at'] as int).toDouble());
        expect([for (final id in store.ids) _bits(store.value(id))], s['values'], reason: 'case $i report $k');
      }
      for (final h in (c['histories'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final id = h['id'] as int;
        final samples = [for (var k = 0; k < store.length(id); k++) store.sample(id, k)];
        expect([for (final (at, _) in samples) at.toInt()], h['at'], reason: 'case $i link $id times');
        expect([for (final (_, v) in samples) _bits(v)], h['values'], reason: 'case $i link $id values');
      }
    }
  });

  final definition = readDeviceFile(cases.first['xml'] as String).definition;
  final ids = definition.links.keys.toList();
  ReportReply reportOf(Map<int, double> values, {int status = 0}) =>
      ReportReply(status, [for (final e in values.entries) ReportedValue(e.key, e.value)]);

  test('a link missing from a report is stale until it is reported again', () {
    final store = LiveStore(definition);
    expect(store.isStale(ids[0]), isTrue);
    store.apply(reportOf({ids[0]: 1, ids[1]: 2}), 0);
    expect(store.isStale(ids[0]), isFalse);
    expect(store.isStale(ids[2]), isTrue);
    store.apply(reportOf({ids[1]: 3}), 10);
    expect(store.isStale(ids[0]), isTrue);
    expect(store.value(ids[0]), 1);
    expect(store.sample(ids[0], 1), (10.0, 1.0));
  });

  test('the version counts reports; dirty bits name the links that changed', () {
    final store = LiveStore(definition);
    store.apply(reportOf({ids[0]: 1, ids[1]: 0}), 0);
    expect(store.version, 1);
    expect(store.takeDirty(), [ids[0]]);
    expect(store.takeDirty(), isEmpty);
    store.apply(reportOf({ids[0]: 1, ids[1]: 5}), 1);
    expect(store.takeDirty(), [ids[1]]);
    store.apply(reportOf({ids[0]: 9}, status: 1), 2);
    expect(store.version, 2, reason: 'a failed report is ignored');
  });

  test('history keeps the newest samples once full', () {
    final store = LiveStore(definition, capacity: 3);
    for (var k = 0; k < 5; k++) {
      store.apply(reportOf({ids[0]: k.toDouble()}), k.toDouble());
    }
    expect([for (var k = 0; k < store.length(ids[0]); k++) store.sample(ids[0], k).$2], [2, 3, 4]);
    expect(() => store.sample(ids[0], 3), throwsRangeError);
    expect(() => store.value(99999), throwsArgumentError);
  });

  test('the session feeds reports into the store once online', () {
    fakeAsync((async) {
      final xml = cases.first['xml'] as String;
      final ecu = SimEcu(readDeviceFile(xml).calibration, reportPeriod: const Duration(milliseconds: 100));
      final c = Connection((baud) => openSimulator(ecu, baud));
      final s = Session(
        c,
        definitions: (_) => readDeviceFile(xml),
        now: () => DateTime.utc(2026, 11, 18).add(async.elapsed),
      );
      c.connect();
      async.elapse(const Duration(milliseconds: 1050));
      final live = s.live!;
      expect(live.version, greaterThanOrEqualTo(9));
      final id = live.ids.first;
      expect(live.isStale(id), isFalse);
      expect(live.length(id), live.version);
      c.disconnect();
      async.flushMicrotasks();
      s.dispose();
    });
  });
}
