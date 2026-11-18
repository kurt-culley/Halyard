import 'package:fake_async/fake_async.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

Future<void> main() async {
  final s = (await loadVectors('sim_faults.json')).cast<Map<String, dynamic>>().first;
  final xml = s['xml'] as String;

  /// A simulated ECU, a channel to it, and a reader; [seed] gives it a fault log.
  ({SimEcu ecu, FaultLogReader reader}) rig({bool seed = true, bool engineStopped = false}) {
    final ecu = SimEcu(readDeviceFile(xml).calibration, engineStopped: engineStopped);
    if (seed) ecu.faults.seed();
    final channel = Channel()..attach(SimTransport(ecu, 230400));
    return (ecu: ecu, reader: FaultLogReader(channel));
  }

  T run<T>(FakeAsync async, Future<T> f) {
    late T out;
    Object? error;
    f.then<void>(
      (v) => out = v,
      onError: (Object e) {
        error = e;
      },
    );
    async.elapse(const Duration(seconds: 30));
    if (error != null) throw error!;
    return out;
  }

  test('reads info, layout, summary and the whole history', () {
    fakeAsync((async) {
      final (:ecu, :reader) = rig();
      final log = FaultLog();
      expect(run(async, reader.fetch(log)), isTrue);
      expect(log.info!.engineHoursX100, 12345);
      expect(log.layout.map((c) => c.linkId), ecu.faults.layout.map((e) => e.$1));
      expect(log.summary.map((e) => e.code), [102, 711, 901, 412]);
      expect(log.codesWithCount, 3);
      run(async, reader.fetchHistory(log));
      expect(log.historyComplete, isTrue);
      expect(log.records.map((r) => r.type), [1, 1, 1, 2, 4, 3]);
      expect(log.records[3].checkpointEntries.map((e) => e.code), [102, 901]);
      expect((log.records[4].oldMode, log.records[4].newMode), (1, 2));
      final frame = log.frameOf(log.records[1]);
      if (ecu.definition.links.containsKey(1)) expect(frame.first, (1, 7600.0));
    });
  });

  test('an ECU without a fault log does not answer: fetch says so', () {
    fakeAsync((async) {
      final (ecu: _, :reader) = rig(seed: false);
      expect(run(async, reader.fetch(FaultLog())), isFalse);
    });
  });

  test('clearing zeroes the counters and reads the log and history again', () {
    fakeAsync((async) {
      final (ecu: _, :reader) = rig();
      final log = FaultLog();
      run(async, reader.fetch(log));
      run(async, reader.fetchHistory(log));
      run(async, reader.clear(log));
      expect(log.codesWithCount, 0);
      expect(log.records.first.type, FaultRecordType.clear);
      expect(log.records, hasLength(7));
    });
  });

  test('erasing is refused while the engine runs, and empties the log when it is stopped', () {
    fakeAsync((async) {
      final running = rig();
      final log = FaultLog();
      run(async, running.reader.fetch(log));
      expect(
        () => run(async, running.reader.erase(log)),
        throwsA(isA<FaultLogError>().having((e) => e.failure, 'failure', FaultLogFailure.engineRunning)),
      );
      final stopped = rig(engineStopped: true);
      final log2 = FaultLog();
      run(async, stopped.reader.fetch(log2));
      run(async, stopped.reader.erase(log2));
      run(async, stopped.reader.fetchHistory(log2));
      expect(log2.records, isEmpty);
      expect(log2.historyComplete, isTrue);
    });
  });

  test('live-data types reach the freeze-frame layout', () {
    final log = FaultLog()..layout = [const FrameChannel(1, 2), const FrameChannel(6, 4)];
    log.applyReportingTypes({1: FrameValueType.int16});
    expect(log.layout.map((c) => c.effectiveType), [FrameValueType.int16, FrameValueType.float]);
  });
}
