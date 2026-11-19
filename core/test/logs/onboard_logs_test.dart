import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

/// Records what the host sends on its way to the simulator.
class _Recording implements Transport {
  _Recording(this._inner, this.sent);
  final Transport _inner;
  final List<String> sent;
  final _d = FrameDecoder();
  @override
  Stream<Uint8List> get input => _inner.input;
  @override
  Future<void> write(Uint8List b) {
    sent.addAll([for (final r in _d.pushRaw(b)) r.frame.hex]);
    return _inner.write(b);
  }

  @override
  Future<void> setBaudRate(int baud) => _inner.setBaudRate(baud);
  @override
  Future<void> close() => _inner.close();
}

Future<void> main() async {
  final v = (await loadVectors('onboard_logs.json')).first as Map<String, dynamic>;

  test('numbers in log files: .NET "G" for floats and doubles', () {
    for (final g in (v['general'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final d = ByteData.sublistView(fromHex(g['v'] as String)).getFloat64(0, Endian.little);
      expect(formatGeneral(fround(d)), g['f'], reason: '$d as float');
      expect(formatGeneral(d, isFloat: false), g['d'], reason: '$d as double');
    }
  });

  final sessions = (v['sessions'] as List<dynamic>).cast<Map<String, dynamic>>();
  test('downloads ask for the same regions and save the same CSV (${sessions.length} sessions)', () {
    for (final (i, s) in sessions.indexed) {
      fakeAsync((async) {
        final calibration = readDeviceFile(s['xml'] as String).calibration;
        final ecu = SimEcu(calibration, now: () => DateTime.fromMillisecondsSinceEpoch(s['now'] as int, isUtc: true));
        ecu.dataLog.seed();
        final sent = <String>[];
        final channel = Channel()..attach(_Recording(SimTransport(ecu, 230400), sent));
        final logger = OnboardLogger(channel);
        final csv = <int, String>{};
        () async {
          for (final log in await logger.logs()) {
            csv[log.id] = (await logger.download(log)).toCsv(calibration.definition);
          }
        }();
        async.elapse(const Duration(seconds: 30));
        expect(sent, s['sent'], reason: 'session $i requests');
        for (final l in (s['logs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
          expect(csv[l['id']], l['csv'], reason: 'session $i log ${l['id']}');
        }
      });
    }
  });

  test('support, configuration, start, stop, erase and format', () {
    fakeAsync((async) {
      final s = sessions.first;
      final calibration = readDeviceFile(s['xml'] as String).calibration;
      final ecu = SimEcu(calibration, now: () => DateTime.utc(2026, 11, 18).add(async.elapsed))..dataLog.seed();
      final logger = OnboardLogger(Channel()..attach(SimTransport(ecu, 230400)));
      T run<T>(Future<T> f) {
        late T out;
        Object? error;
        f.then<void>(
          (x) => out = x,
          onError: (Object e) {
            error = e;
          },
        );
        async.elapse(const Duration(seconds: 5));
        if (error != null) throw error!;
        return out;
      }

      final support = run(logger.support())!;
      expect(support.frequencies, [10, 25, 40, 50, 75, 100]);
      final ids = calibration.definition.links.keys.take(2).toList();
      run(logger.configure(50, ids));
      expect(run(logger.configuration()).loggedIds, ids);
      run(logger.start());
      expect(() => run(logger.configure(10, ids)), throwsA(isA<OnboardLogError>()), reason: 'refused while logging');
      async.elapse(const Duration(seconds: 2));
      run(logger.stop());
      expect(run(logger.logs()), hasLength(3));
      run(logger.erase(1));
      expect(run(logger.logs()).map((l) => l.id), [2, 3]);
      run(logger.format());
      expect(run(logger.logs()), isEmpty);
    });
  });

  test('a channel the definition lacks is headed by its id (docs/behaviour-changes.md)', () {
    final s = sessions.first;
    final d = readDeviceFile(s['xml'] as String).definition;
    final log = OnboardLog(
      LogInfo(1, LogTimestamp(2026, 1, 1, 0, 0), 1, 1, 1),
      [65000],
      [
        const LogEntry(0.5, [1.5]),
      ],
    );
    expect(log.toCsv(d), 'Time,65000\r\n0.5,1.5,\r\n');
  });
}
