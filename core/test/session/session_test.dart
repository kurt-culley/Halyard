import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

/// Records every frame the host writes.
class _Recording implements Transport {
  _Recording(this._inner, this.sent);
  final Transport _inner;
  final List<Frame> sent;
  final _decoder = FrameDecoder();

  @override
  Stream<Uint8List> get input => _inner.input;
  @override
  Future<void> write(Uint8List bytes) {
    sent.addAll([for (final r in _decoder.pushRaw(bytes)) r.frame]);
    return _inner.write(bytes);
  }

  @override
  Future<void> setBaudRate(int baud) => _inner.setBaudRate(baud);
  @override
  Future<void> close() => _inner.close();
}

/// The session's own requests: classes 0, 1, 2 and 4, without the lifesign.
List<String> _own(List<Frame> sent) => [
  for (final f in sent)
    if ([0, 1, 2, 4].contains(f.cls) && !(f.cls == 0 && f.cmd == 1)) f.hex,
];

void _apply(SimEcu ecu, List<dynamic> edits) {
  final c = ecu.calibration;
  for (final e in edits.cast<Map<String, dynamic>>()) {
    final blob = fromHex(e['blob'] as String);
    if (e['table'] case final int id) c.tables[id] = parseTableBlob(c.definition.tables[id]!, blob, c.tables[id]);
    if (e['driver'] case final int id) c.drivers[id] = parseDriverBlob(c.definition.drivers[id]!, blob, c.drivers[id]);
  }
}

({SimEcu ecu, Connection connection, Session session, List<Frame> sent}) _rig(Map<String, dynamic> v) {
  final o = v['options'] as Map<String, dynamic>;
  final pw = v['password'] as Map<String, dynamic>?;
  final ecu = SimEcu(
    readDeviceFile(v['xml'] as String).calibration,
    uuid: o['uuid'] as String,
    fwVersion: o['fwVersion'] as String,
    reportPeriod: const Duration(days: 1),
    password:
        pw == null
            ? null
            : SimPassword(
              locked: pw['locked'] as bool,
              temporary: pw['temporary'] as bool,
              contact: pw['contact'] as String,
            ),
  );
  final sent = <Frame>[];
  final connection = Connection((baud) async => _Recording(SimTransport(ecu, baud), sent));
  final hostXml = v['hostXml'] as String;
  final session = Session(
    connection,
    definitions: (info) {
      final file = readDeviceFile(hostXml);
      return file.definition.info.describes(info) ? file : null;
    },
  );
  return (ecu: ecu, connection: connection, session: session, sent: sent);
}

Future<void> main() async {
  final cases = (await loadVectors('session.json')).cast<Map<String, dynamic>>();

  test('connects, reads and reconnects as the TypeScript app did (${cases.length} cases)', () {
    for (final (i, v) in cases.indexed) {
      fakeAsync((async) {
        final (:ecu, :connection, :session, :sent) = _rig(v);
        _apply(ecu, v['before'] as List<dynamic>);
        final between = v['between'] as List<dynamic>;
        for (final (k, phase) in (v['phases'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
          final why = 'case $i (${v['kind']}) connect $k';
          if (k > 0) {
            connection.disconnect();
            async.flushMicrotasks();
            expect(session.state.phase, SessionPhase.offline, reason: why);
            _apply(ecu, between[k - 1] as List<dynamic>);
          }
          sent.clear();
          connection.connect();
          async.elapse(const Duration(seconds: 1));
          expect(_own(sent), phase['sent'], reason: '$why requests');

          final host = phase['host'] as Map<String, dynamic>;
          final cal = session.calibration;
          if (host['load'] == 'notFound') {
            expect(
              session.state,
              const SessionState(SessionPhase.loadingDefinition, problem: SessionProblem.noDefinition),
            );
            expect(cal, isNull, reason: why);
            continue;
          }
          expect(session.state, const SessionState(SessionPhase.online), reason: why);
          expect(session.ecuUuid, host['uuid'], reason: why);
          for (final t in (host['tables'] as List<dynamic>).cast<List<dynamic>>()) {
            final id = t[0] as int;
            expect(toHex(tableBlob(cal!.definition.tables[id]!, cal.tables[id]!)), t[1], reason: '$why table $id');
          }
          for (final d in (host['drivers'] as List<dynamic>).cast<List<dynamic>>()) {
            final id = d[0] as int;
            expect(toHex(driverBlob(cal!.definition.drivers[id]!, cal.drivers[id]!)), d[1], reason: '$why driver $id');
          }
          final pw = host['password'] as Map<String, dynamic>?;
          expect(session.password?.locked, pw?['locked'], reason: why);
          expect(session.password?.contact, pw?['contact'], reason: why);
          expect(session.calibration!.overallHash, ecu.calibration.overallHash, reason: why);
        }
        connection.disconnect();
        async.flushMicrotasks();
        session.dispose();
      });
    }
  });

  test('online, it sends a lifesign every 1.5 s until the link drops', () {
    fakeAsync((async) {
      final (ecu: _, :connection, :session, :sent) = _rig(cases.first);
      connection.connect();
      async.elapse(const Duration(seconds: 1));
      expect(session.state.phase, SessionPhase.online);
      sent.clear();
      async.elapse(const Duration(milliseconds: 4600));
      expect(sent.where((f) => f.cls == 0 && f.cmd == 1).length, 3);
      connection.disconnect();
      async.flushMicrotasks();
      sent.clear();
      async.elapse(const Duration(seconds: 5));
      expect(sent, isEmpty);
      session.dispose();
    });
  });

  test('pausing reporting stops the lifesign; resuming starts both again', () {
    fakeAsync((async) {
      final (:ecu, :connection, :session, :sent) = _rig(cases.first);
      connection.connect();
      async.elapse(const Duration(seconds: 1));
      session.pauseReporting();
      async.flushMicrotasks();
      expect(ecu.reporting, isFalse);
      sent.clear();
      async.elapse(const Duration(seconds: 2));
      expect(sent.where((f) => f.cls == 0 && f.cmd == 1), isEmpty);
      connection.pauseWatchdog();
      session.resumeReporting();
      async.elapse(const Duration(milliseconds: 1600));
      expect(ecu.reporting, isTrue);
      expect(sent.where((f) => f.cls == 0 && f.cmd == 1), hasLength(1));
      connection.disconnect();
      async.flushMicrotasks();
      session.dispose();
    });
  });

  test('password and hash replies outside the connect sequence start no read (docs/behaviour-changes.md)', () {
    fakeAsync((async) {
      final v = cases.firstWhere((c) => c['kind'] == 'password');
      final (:ecu, :connection, :session, :sent) = _rig(v);
      connection.connect();
      async.elapse(const Duration(seconds: 1));
      expect(session.state.phase, SessionPhase.online);
      _apply(ecu, [
        {
          'table': ecu.definition.tables.keys.first,
          'blob': toHex(
            tableBlob(ecu.definition.tables.values.first, TableValues.zero(ecu.definition.tables.values.first)),
          ),
        },
      ]);
      sent.clear();
      connection.channel
        ..request(pwLockGetStateRequest())
        ..request(getHashRequest(HashMode.detailed))
        ..request(getHashRequest(HashMode.overall));
      async.elapse(const Duration(seconds: 1));
      expect(_own(sent), ['000405', '00040101', '00040100']);
      expect(session.state.phase, SessionPhase.online);
      connection.disconnect();
      async.flushMicrotasks();
      session.dispose();
    });
  });

  test('an identity reply with a failure status is ignored (docs/behaviour-changes.md)', () {
    fakeAsync((async) {
      final v = cases.firstWhere((c) => c['kind'] == 'reconnect');
      final ecu = SimEcu(readDeviceFile(v['xml'] as String).calibration);
      var failIdentity = false;
      final c = Connection(
        (baud) async => _Tamper(
          SimTransport(ecu, baud),
          read: (f) => failIdentity && f.cls == 4 && f.cmd == 0 ? Frame(f.type, 4, 0, Uint8List.fromList([1])) : f,
        ),
      );
      final s = Session(c, definitions: (_) => readDeviceFile(v['hostXml'] as String));
      c.connect();
      async.elapse(const Duration(seconds: 1));
      expect(s.state.phase, SessionPhase.online);
      final cal = s.calibration;
      failIdentity = true;
      c.channel.request(getEcuInfoRequest());
      async.elapse(const Duration(seconds: 1));
      expect(s.state.phase, SessionPhase.online);
      expect(s.calibration, same(cal));
      c.disconnect();
      async.flushMicrotasks();
      s.dispose();
    });
  });

  test('an ECU that stops answering mid-read leaves the session short of online', () {
    fakeAsync((async) {
      final v = cases.firstWhere((c) => c['kind'] == 'reconnect');
      final ecu = SimEcu(readDeviceFile(v['xml'] as String).calibration);
      // Table reads go unanswered.
      final c = Connection((baud) async => _Tamper(SimTransport(ecu, baud), write: (f) => f.cls == 1 ? null : f));
      final s = Session(c, definitions: (_) => readDeviceFile(v['hostXml'] as String));
      c
        ..connect()
        ..pauseWatchdog();
      async.elapse(const Duration(seconds: 4));
      expect(s.state.phase, SessionPhase.readingCalibration);
      expect(s.state.problem, SessionProblem.noAnswer);
      expect(ecu.reporting, isFalse);
      c.disconnect();
      async.flushMicrotasks();
      s.dispose();
    });
  });

  test('a table whose blob does not fit is listed and keeps its values', () {
    fakeAsync((async) {
      final v = cases.firstWhere((c) => c['kind'] == 'reconnect');
      final ecu = SimEcu(readDeviceFile(v['xml'] as String).calibration);
      final first = ecu.definition.tables.keys.first;
      // The ECU answers the first table with a shape the definition doesn't have.
      final c = Connection(
        (baud) async => _Tamper(
          SimTransport(ecu, baud),
          read:
              (f) =>
                  f.cls == 1 && f.cmd == 1 && f.payload[1] == (first & 0xff) && f.payload[2] == first >> 8
                      ? Frame(f.type, f.cls, f.cmd, Uint8List.fromList(f.payload)..[8] ^= 0xff)
                      : f,
        ),
      );
      final file = readDeviceFile(v['hostXml'] as String);
      final s = Session(c, definitions: (_) => readDeviceFile(v['hostXml'] as String));
      c.connect();
      async.elapse(const Duration(seconds: 1));
      expect(s.state.phase, SessionPhase.online);
      expect(s.unreadable, {first});
      final def = file.definition.tables[first]!;
      expect(tableBlob(def, s.calibration!.tables[first]!), tableBlob(def, file.calibration.tables[first]!));
      c.disconnect();
      async.flushMicrotasks();
      s.dispose();
    });
  });
}

/// Passes frames through [write] (host to ECU) and [read] (ECU to host); null drops a frame.
class _Tamper implements Transport {
  _Tamper(this._inner, {Frame? Function(Frame)? write, Frame? Function(Frame)? read})
    : _write = write ?? ((f) => f),
      _read = read ?? ((f) => f);
  final Transport _inner;
  final Frame? Function(Frame) _write, _read;
  final _out = FrameDecoder(), _in = FrameDecoder();

  @override
  Stream<Uint8List> get input => _inner.input.map(
    (b) => Uint8List.fromList([
      for (final r in _in.pushRaw(b))
        if (_read(r.frame) case final f?) ...encodeFrame(f),
    ]),
  );
  @override
  Future<void> write(Uint8List bytes) async {
    for (final r in _out.pushRaw(bytes)) {
      if (_write(r.frame) case final f?) await _inner.write(encodeFrame(f));
    }
  }

  @override
  Future<void> setBaudRate(int baud) => _inner.setBaudRate(baud);
  @override
  Future<void> close() => _inner.close();
}
