import 'package:fake_async/fake_async.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

Future<void> main() async {
  final xml = ((await loadVectors('live.json')).first as Map<String, dynamic>)['xml'] as String;

  List<BenchResult> run({required bool faults, void Function(Session s)? before}) {
    late List<BenchResult> results;
    fakeAsync((async) {
      final ecu = SimEcu(readDeviceFile(xml).calibration, reportPeriod: const Duration(milliseconds: 100));
      if (faults) ecu.faults.seed();
      final c = Connection((baud) => openSimulator(ecu, baud), policy: const ReadOnlyPolicy());
      final s = Session(c, definitions: (_) => readDeviceFile(xml), now: () => DateTime.utc(2026).add(async.elapsed));
      c.connect();
      async.elapse(const Duration(seconds: 1));
      before?.call(s);
      runBenchChecks(s, now: () => DateTime.utc(2026).add(async.elapsed)).then((r) => results = r);
      async.elapse(const Duration(seconds: 10));
      c.disconnect();
      async.flushMicrotasks();
      s.dispose();
    });
    return results;
  }

  test('every check passes against the simulator through the read-only policy', () {
    final results = run(faults: true);
    expect([for (final r in results) r.check], BenchCheck.values);
    expect(
      {for (final r in results) r.check: r.status},
      {for (final c in BenchCheck.values) c: c == BenchCheck.canIds ? anything : BenchStatus.pass},
    );
    final live = results.firstWhere((r) => r.check == BenchCheck.live);
    expect(live.details['frames'], greaterThanOrEqualTo(25));
    expect(live.details['perSecond'], 10);
  });

  test('a simulator without a fault log skips that check', () {
    final r = run(faults: false).firstWhere((r) => r.check == BenchCheck.faults);
    expect(r.status, BenchStatus.skip);
    expect(r.details['reason'], 'fault log not supported');
  });

  test('the report lists checks, blocked writes and requests sent', () {
    final t = DateTime.utc(2026, 11, 18, 9);
    final text = benchReportText(
      started: t,
      results: [
        const BenchResult(BenchCheck.hash, BenchStatus.pass, {'mode': 0, 'overall': 1234}, Duration(milliseconds: 12)),
        const BenchResult(BenchCheck.trigger, BenchStatus.skip, {'reason': 'not supported'}, Duration.zero),
      ],
      blocked: [(t, Frame.request(1, 6))],
      sent: {'Sys.GetHash': 1, 'Reporting.Ack (lifesign)': 4},
    );
    expect(
      text,
      'Halyard read-only bench test - 2026-11-18T09:00:00.000Z\n'
      '\n'
      'PASS  Calibration hash (GetHash) (12 ms)\n'
      '      mode=0 overall=1234\n'
      'SKIP  Trigger scope support (IsSupported) (0 ms)\n'
      '      reason=not supported\n'
      '\n'
      'Blocked writes (1):\n'
      '  2026-11-18T09:00:00.000Z  Tables.Store (1/6)\n'
      '\n'
      'Requests sent:\n'
      '  Reporting.Ack (lifesign): 4\n'
      '  Sys.GetHash: 1',
    );
  });
}
