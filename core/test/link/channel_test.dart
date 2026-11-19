import 'package:fake_async/fake_async.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/fake_transport.dart';

/// Lets fake time run (and [elapse]) and returns what [future] completed with.
T settle<T>(FakeAsync async, Future<T> future, {Duration elapse = Duration.zero}) {
  T? out;
  var done = false;
  future.then((v) {
    out = v;
    done = true;
  });
  async
    ..elapse(elapse)
    ..flushMicrotasks();
  expect(done, isTrue, reason: 'future did not complete');
  return out as T;
}

void main() {
  final table4100 = [0, 0x04, 0x10, 0, 0]; // success, id 4100, empty blob

  test('a request is answered by the matching reply', () {
    fakeAsync((async) {
      final t = FakeTransport(respond: (f, _) => [rsp(1, 1, table4100)]);
      final c = Channel()..attach(t);
      final r = settle(async, c.request(getTableRequest(4100)));
      expect(r.ok, isTrue);
      expect((r.reply! as BlobReply).id, 4100);
      expect(c.sentCount, 1);
    });
  });

  test('a reply for something else fails the request as a mismatch', () {
    fakeAsync((async) {
      final t = FakeTransport(
        respond:
            (f, _) => [
              rsp(1, 1, [0, 0x05, 0x10, 0, 0]),
            ],
      );
      final c = Channel()..attach(t);
      final r = settle(async, c.request(getTableRequest(4100)));
      expect(r.failure, Failure.mismatch);
      expect(r.reply, isNull);
    });
  });

  test('an unsuccessful status is a reply, but not ok', () {
    fakeAsync((async) {
      final t = FakeTransport(
        respond:
            (f, _) => [
              rsp(1, 6, [7, 0x04, 0x10]),
            ],
      );
      final c = Channel()..attach(t);
      final r = settle(async, c.request(storeTableRequest(4100)));
      expect(r.failure, Failure.none);
      expect(r.reply!.status, ReplyStatus.lockedDown);
      expect(r.ok, isFalse);
    });
  });

  test('no reply within the timeout', () {
    fakeAsync((async) {
      final c = Channel()..attach(FakeTransport());
      final r = settle(async, c.request(getEcuInfoRequest()), elapse: const Duration(seconds: 3));
      expect(r.failure, Failure.timeout);
    });
  });

  test('a reply with a bad checksum never answers a request', () {
    fakeAsync((async) {
      final t = FakeTransport(
        respond: (f, link) {
          final b = encodeFrame(ecuInfoReply());
          b[b.length - 1] ^= 0xff;
          link.deliverBytes(b);
          return const [];
        },
      );
      final c = Channel()..attach(t);
      final r = settle(async, c.request(getEcuInfoRequest()), elapse: const Duration(seconds: 3));
      expect(r.failure, Failure.timeout);
      expect(c.crcErrors, 1);
    });
  });

  test('frames that expect nothing complete when written', () {
    fakeAsync((async) {
      final t = FakeTransport();
      final c = Channel()..attach(t);
      final r = settle(async, c.request(setStateRequest(false)));
      expect(r.ok, isTrue);
      expect(r.reply, isNull);
      expect(t.written.single.hex, '00000200');
    });
  });

  test('a batch stops at the first failure: the store after a refused write is never sent', () {
    fakeAsync((async) {
      // refused: failure status, id 4100, element 0, no cells echoed
      final t = FakeTransport(
        respond:
            (f, _) => [
              rsp(1, 4, [1, 0x04, 0x10, 0, 0, 0]),
            ],
      );
      final c = Channel()..attach(t);
      final rs = settle(
        async,
        c.requestAll([
          setTableDataRequest(
            4100,
            0,
            [0],
            [
              [1.0],
            ],
          ),
          storeTableRequest(4100),
        ]),
      );
      expect(rs.map((r) => r.failure).toList(), [Failure.none, Failure.cancelled]);
      expect(rs.first.ok, isFalse);
      expect(t.written, hasLength(1));
    });
  });

  test('requests go one at a time, in order', () {
    fakeAsync((async) {
      final order = <int>[];
      final t = FakeTransport(
        respond: (f, _) {
          order.add(f.cmd);
          return f.cls == 4 ? [ecuInfoReply()] : [rsp(1, 1, table4100)];
        },
      );
      final c = Channel()..attach(t);
      final a = c.request(getEcuInfoRequest());
      final b = c.request(getTableRequest(4100));
      final both = settle(async, Future.wait([a, b]));
      expect(both.every((r) => r.ok), isTrue);
      expect(order, [0, 1]);
    });
  });

  test('the read-only policy refuses writes before they reach the wire', () {
    fakeAsync((async) {
      final blocked = <Frame>[];
      final t = FakeTransport(respond: (f, _) => [rsp(1, 1, table4100)]);
      final c =
          Channel(policy: const ReadOnlyPolicy())
            ..onBlocked = blocked.add
            ..attach(t);
      expect(settle(async, c.request(storeTableRequest(4100))).failure, Failure.blocked);
      expect(settle(async, c.request(factoryResetRequest())).failure, Failure.blocked);
      expect(settle(async, c.request(enterBootloaderRequest())).failure, Failure.blocked);
      expect(settle(async, c.request(regionInfoAnswer(0, 0, 0, 0, 0))).failure, Failure.blocked);
      expect(settle(async, c.request(getTableRequest(4100))).ok, isTrue);
      expect(settle(async, c.request(ackFrame())).ok, isTrue);
      expect(settle(async, c.request(setDbwDutyRequest(0, 50))).failure, Failure.blocked);
      expect(blocked.map((f) => (f.cls, f.cmd)).toList(), [(1, 6), (4, 3), (5, 4), (5, 1), (8, 0)]);
      expect(const ReadOnlyPolicy().allows(triggerSetStateRequest(true, [0, 1])), isTrue);
      expect(t.written.map((f) => (f.cls, f.cmd)).toList(), [(1, 1), (0, 1)]);
    });
  });

  test('a failed write reports the link lost and fails the request', () {
    fakeAsync((async) {
      var lost = 0;
      final t = FakeTransport()..failWrites = true;
      final c =
          Channel()
            ..onLost = (() => lost++)
            ..attach(t);
      expect(settle(async, c.request(getEcuInfoRequest())).failure, Failure.notConnected);
      expect(lost, 1);
      expect(c.isAttached, isFalse);
    });
  });

  test('frames that are not answers are broadcast, and live data keeps its layout', () {
    fakeAsync((async) {
      final t = FakeTransport();
      final c = Channel()..attach(t);
      final got = <Received>[];
      c.received.listen(got.add);
      t
        ..deliver(rsp(0, 2, [0, 1, 0, 7, 0, 2])) // layout: link 7 as uint16
        ..deliver(rsp(0, 0, [0, 0x34, 0x12])); // report
      async.flushMicrotasks();
      expect(got, hasLength(2));
      final report = got.last.reply! as ReportReply;
      expect(report.entities.single.id, 7);
      expect(report.entities.single.value, 0x1234);
    });
  });
}
