import 'package:fake_async/fake_async.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/fake_transport.dart';

void main() {
  late List<FakeTransport> opened;
  late List<LinkState> states;

  // Each open gets a fresh transport.
  Connection fresh(FakeTransport Function(int baud) create, {LinkTiming timing = LinkTiming.cable}) {
    opened = [];
    states = [];
    final c = Connection((baud) async {
      final t = create(baud);
      opened.add(t);
      return t;
    }, timing: timing);
    c.states.listen(states.add);
    return c;
  }

  test('connects at 230400 when the ECU answers', () {
    fakeAsync((async) {
      final c = fresh((b) => FakeTransport(baud: b, respond: answerIdentity));
      c.connect();
      async.flushMicrotasks();
      expect(c.state, const LinkState(LinkPhase.connected, baudRate: 230400));
      expect(opened.single.written.single.hex, '000400');
    });
  });

  test('tries 115200 once when 230400 gets no answer', () {
    fakeAsync((async) {
      final c = fresh((b) => FakeTransport(baud: b, respond: (f, t) => answerIdentity(f, t, answerAt: 115200)));
      c.connect();
      async.elapse(const Duration(milliseconds: 1100));
      expect(c.state, const LinkState(LinkPhase.connected, baudRate: 115200));
      expect(opened, hasLength(1));
      expect(opened.single.written, hasLength(2));
    });
  });

  test('silence for a watchdog period drops the link and reconnects at the rate that worked', () {
    fakeAsync((async) {
      final c = fresh((b) => FakeTransport(baud: b, respond: (f, t) => answerIdentity(f, t, answerAt: 115200)));
      c.connect();
      async.elapse(const Duration(milliseconds: 1100));
      expect(c.state.phase, LinkPhase.connected);

      // The handshake reply counts at the first watchdog tick (3 s); the second (6 s) sees nothing.
      async.elapse(const Duration(seconds: 5));
      expect(opened.first.closed, isTrue);
      expect(c.state.phase, LinkPhase.reconnecting);

      async.elapse(const Duration(milliseconds: 600));
      expect(opened, hasLength(2));
      expect(c.state, const LinkState(LinkPhase.connected, baudRate: 115200));
      expect(opened.last.written, hasLength(1), reason: 'no baud search once a rate has worked');
    });
  });

  test('live data keeps the link up', () {
    fakeAsync((async) {
      final c = fresh((b) => FakeTransport(baud: b, respond: answerIdentity));
      c.connect();
      async.flushMicrotasks();
      for (var i = 0; i < 10; i++) {
        opened.single.deliver(rsp(0, 0, [0, 0, 0])); // empty version-1 report
        async.elapse(const Duration(seconds: 1));
      }
      expect(c.state.phase, LinkPhase.connected);
      expect(opened, hasLength(1));
    });
  });

  test('a paused watchdog tolerates silence', () {
    fakeAsync((async) {
      final c = fresh((b) => FakeTransport(baud: b, respond: answerIdentity));
      c.connect();
      async.flushMicrotasks();
      c.pauseWatchdog();
      async.elapse(const Duration(seconds: 20));
      expect(c.state.phase, LinkPhase.connected);
      c.resumeWatchdog();
      async.elapse(const Duration(seconds: 3));
      expect(opened.first.closed, isTrue);
    });
  });

  test('gives up after the maximum number of failed attempts', () {
    fakeAsync((async) {
      var opens = 0;
      final c = Connection((baud) async {
        opens++;
        throw StateError('port busy');
      }, timing: const LinkTiming(maxAttempts: 3, errorDelay: Duration(seconds: 1)));
      c.connect();
      async.elapse(const Duration(seconds: 10));
      expect(opens, 3);
      expect(c.state.phase, LinkPhase.closed);
    });
  });

  test('disconnect closes the port and stops reconnecting', () {
    fakeAsync((async) {
      final c = fresh((b) => FakeTransport(baud: b, respond: answerIdentity));
      c.connect();
      async.flushMicrotasks();
      var done = false;
      c.disconnect().then((_) => done = true);
      async.elapse(const Duration(seconds: 10));
      expect(done, isTrue);
      expect(opened.single.closed, isTrue);
      expect(opened, hasLength(1));
      expect(c.state.phase, LinkPhase.closed);
    });
  });

  test('a link that drops from the far end reconnects', () {
    fakeAsync((async) {
      final c = fresh((b) => FakeTransport(baud: b, respond: answerIdentity));
      c.connect();
      async.flushMicrotasks();
      opened.single.drop();
      async.elapse(const Duration(milliseconds: 600));
      expect(opened, hasLength(2));
      expect(c.state.phase, LinkPhase.connected);
      expect(
        states.map((s) => s.phase),
        containsAllInOrder([LinkPhase.opening, LinkPhase.connected, LinkPhase.reconnecting, LinkPhase.connected]),
      );
    });
  });
}
