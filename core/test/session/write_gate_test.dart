import 'package:fake_async/fake_async.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

/// A quiet NaN as one pattern: Dart's NaN carries the sign bit on x64 (as .NET's float.NaN does), JavaScript's
/// doesn't. Values are aligned in these frames, so the pattern can only be a NaN.
String _nan(String hex) => hex.replaceAll('0000c0ff', '0000c07f');

Future<void> main() async {
  final cases = (await loadVectors('saving.json')).cast<Map<String, dynamic>>();

  test('saves send what the original sent (${cases.length} definitions)', () {
    for (final (n, c) in cases.indexed) {
      final cal = readDeviceFile(c['xml'] as String).calibration;
      final gate = WriteGate.over(() => cal, Channel.new);
      for (final (k, s) in (c['steps'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
        final why = 'case $n step $k';
        final store = s['store'] as bool;
        final List<Frame> frames;
        if (s['table'] case final int id) {
          for (final e in (s['edits'] as List<dynamic>).cast<List<dynamic>>()) {
            gate.setTableCell(id, e[0] as int, e[1] as int, fromHex(e[2] as String).buffer.asFloat32List()[0]);
          }
          frames = gate.tableSaveFrames(id, store: store);
        } else {
          frames = gate.driverSaveFrames(s['driver'] as int, store: store);
        }
        expect(
          [for (final f in frames) _nan(frameToHex(f))],
          [for (final h in s['frames'] as List<dynamic>) _nan(h as String)],
          reason: why,
        );
      }
      // The original built these from the edited model.
      expect(
        [for (final f in gate.calibrationFrames(cal)) _nan(frameToHex(f))],
        [for (final h in c['calibration'] as List<dynamic>) _nan(h as String)],
        reason: 'case $n',
      );
    }
  });

  test('a whole edited table sets only the cells that differ, each element in its own request', () {
    final cal = readDeviceFile(cases.first['xml'] as String).calibration;
    final gate = WriteGate.over(() => cal, Channel.new);
    final id = cal.tables.keys.first;
    final edited = cal.tables[id]!.copy();
    edited.z[1] = 123.25;
    edited.x[0] = -77.5;
    gate.setTable(id, edited);
    final frames = gate.tableSaveFrames(id);
    expect(frames, hasLength(2));
    expect(cal.tables[id]!.z[1], edited.z[1]);
    expect(cal.tables[id]!.x[0], edited.x[0]);
  });

  simulatorTests(((await loadVectors('live.json')).first as Map<String, dynamic>)['xml'] as String);
}

void simulatorTests(String xml) {
  test('a saved and stored cell reaches the simulated ECU', () {
    fakeAsync((async) {
      final ecu = SimEcu(readDeviceFile(xml).calibration, reportPeriod: const Duration(milliseconds: 100));
      final c = Connection((baud) => openSimulator(ecu, baud));
      final s = Session(c, definitions: (_) => readDeviceFile(xml), now: () => DateTime.utc(2026).add(async.elapsed));
      c.connect();
      async.elapse(const Duration(seconds: 2));
      final gate = WriteGate(s);
      final id = s.calibration!.tables.keys.first;
      gate.setTableCell(id, TableElement.values, 0, 12.5);
      WriteResult? r;
      gate.saveTable(id).then((x) => r = x);
      async.elapse(const Duration(seconds: 1));
      expect(gate.isUnstored(id), isTrue);
      gate.saveTable(id, store: true).then((x) => r = x);
      async.elapse(const Duration(seconds: 1));
      expect(r?.ok, isTrue);
      expect(ecu.calibration.tables[id]!.z[0], 12.5);

      // Through the read-only policy nothing is written.
      final ro = Connection((baud) => openSimulator(ecu, baud), policy: const ReadOnlyPolicy());
      final s2 = Session(ro, definitions: (_) => readDeviceFile(xml), now: () => DateTime.utc(2026).add(async.elapsed));
      c.disconnect();
      async.elapse(const Duration(seconds: 1));
      ro.connect();
      async.elapse(const Duration(seconds: 2));
      final g2 = WriteGate(s2)..setTableCell(id, TableElement.values, 0, 99);
      g2.saveTable(id).then((x) => r = x);
      async.elapse(const Duration(seconds: 1));
      expect(r!.failed?.failure, Failure.blocked);
      expect(ecu.calibration.tables[id]!.z[0], 12.5);
      ro.disconnect();
      async.flushMicrotasks();
      s.dispose();
      s2.dispose();
    });
  });

  test('a sent calibration reaches the simulated ECU and is read back here', () {
    fakeAsync((async) {
      final ecu = SimEcu(readDeviceFile(xml).calibration, reportPeriod: const Duration(milliseconds: 100));
      final c = Connection((baud) => openSimulator(ecu, baud));
      final s = Session(c, definitions: (_) => readDeviceFile(xml), now: () => DateTime.utc(2026).add(async.elapsed));
      c.connect();
      async.elapse(const Duration(seconds: 2));
      final gate = WriteGate(s);
      final file = s.calibration!.copy();
      final id = file.tables.keys.first;
      file.tables[id]!.z[0] = 33.25;
      final only = Calibration(file.definition, tables: {id: file.tables[id]!}, drivers: {});
      WriteResult? r;
      gate.sendCalibration(only).then((x) => r = x);
      async.elapse(const Duration(seconds: 2));
      expect(r?.ok, isTrue);
      expect(r!.results, hasLength(3));
      expect(ecu.calibration.tables[id]!.z[0], 33.25);
      expect(s.calibration!.tables[id]!.z[0], 33.25);
      c.disconnect();
      async.flushMicrotasks();
      s.dispose();
    });
  });
}
