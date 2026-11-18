/// One request at a time to the ECU, each waiting for its reply; everything else that arrives is broadcast.
library;

import 'dart:async';
import 'dart:typed_data';

import '../wire/framing.dart';
import '../wire/message_factory.dart';
import '../wire/reply.dart';
import 'transport.dart';

/// Why a request has no usable reply.
enum Failure {
  none,

  /// No reply within the timeout.
  timeout,

  /// Another reply came first: the ECU answered something else.
  mismatch,

  /// The frame policy refused it; nothing was written.
  blocked,

  /// No link, or the link dropped.
  notConnected,

  /// An earlier request in the same batch failed.
  cancelled,
}

final class RequestResult {
  const RequestResult(this.request, this.reply, this.failure);
  const RequestResult.failed(this.request, this.failure) : reply = null;

  final Frame request;

  /// The reply; null for frames that expect none, and on failure.
  final Reply? reply;
  final Failure failure;

  /// Delivered, and answered with success where an answer was expected.
  bool get ok => failure == Failure.none && (reply?.ok ?? true);
}

/// A recognised frame from the ECU and its parsed reply (null for the bootloader's requests).
final class Received {
  const Received(this.frame, this.reply);
  final Frame frame;
  final Reply? reply;
}

final class _Waiter {
  _Waiter(this.expected);
  final ExpectedReply expected;
  final _done = Completer<(Reply?, Failure)>();
  Future<(Reply?, Failure)> get future => _done.future;
  void finish(Reply? r, Failure f) {
    if (!_done.isCompleted) _done.complete((r, f));
  }
}

/// Request/reply over whatever transport is attached. Requests queue and go one at a time; the first reply-type frame
/// after a request answers it, or fails it when it is for something else. Survives reconnects: the connection attaches
/// each new transport.
class Channel {
  Channel({this.timing = LinkTiming.cable, FramePolicy? policy}) : _policy = policy;

  LinkTiming timing;
  final FramePolicy? _policy;

  /// A frame the policy refused.
  void Function(Frame f)? onBlocked;

  /// A frame written to the transport.
  void Function(Frame f)? onSent;

  /// Every decoded frame, good checksum or not (the connection treats any frame as a sign of life).
  void Function(Frame f)? onAnyFrame;

  /// The transport failed a write or its input ended.
  void Function()? onLost;

  int sentCount = 0;

  /// Recognised frames with good checksums.
  int receivedCount = 0;
  int crcErrors = 0;

  Transport? _transport;
  StreamSubscription<Uint8List>? _sub;
  var _decoder = FrameDecoder();
  var _factory = MessageFactory();
  _Waiter? _waiter;
  Future<void> _queue = Future<void>.value();
  final _received = StreamController<Received>.broadcast(sync: true);

  bool get isAttached => _transport != null;
  Stream<Received> get received => _received.stream;

  /// Starts reading [t]. Live-data layout and partial frames from an earlier link are dropped.
  void attach(Transport t) {
    detach();
    _transport = t;
    _decoder = FrameDecoder();
    _factory = MessageFactory();
    _sub = t.input.listen(_receive, onError: (Object _) => _lose(), onDone: _lose);
  }

  /// Stops reading; a request waiting for its reply fails as not connected. Does not close the transport.
  void detach() {
    final sub = _sub;
    _sub = null;
    _transport = null;
    if (sub != null) unawaited(sub.cancel());
    _waiter?.finish(null, Failure.notConnected);
    _waiter = null;
  }

  void _lose() {
    if (_transport == null) return;
    detach();
    onLost?.call();
  }

  /// Sends [f] after the requests ahead of it and waits for its reply.
  Future<RequestResult> request(Frame f, {Duration? timeout}) => _serial(() => _exchange(f, timeout));

  /// Sends [frames] back to back with nothing in between; stops at the first that fails. A store request after a write
  /// that went unanswered is never sent.
  Future<List<RequestResult>> requestAll(List<Frame> frames) => _serial(() async {
    final out = <RequestResult>[];
    for (final f in frames) {
      if (out.isNotEmpty && !out.last.ok) {
        out.add(RequestResult.failed(f, Failure.cancelled));
      } else {
        out.add(await _exchange(f, null));
      }
    }
    return out;
  });

  Future<T> _serial<T>(Future<T> Function() job) {
    final c = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        c.complete(await job());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  Future<RequestResult> _exchange(Frame f, Duration? timeout) async {
    final t = _transport;
    if (t == null) return RequestResult.failed(f, Failure.notConnected);
    if (_policy != null && !_policy.allows(f)) {
      onBlocked?.call(f);
      return RequestResult.failed(f, Failure.blocked);
    }
    final expected = expectedReply(f);
    final waiter = expected == null ? null : (_waiter = _Waiter(expected));
    try {
      await t.write(encodeFrame(f));
      sentCount++;
      onSent?.call(f);
    } catch (_) {
      if (identical(_waiter, waiter)) _waiter = null;
      _lose();
      return RequestResult.failed(f, Failure.notConnected);
    }
    if (waiter == null) return RequestResult(f, null, Failure.none);
    final (reply, failure) = await waiter.future.timeout(
      timeout ?? timing.replyTimeout,
      onTimeout: () => (null, Failure.timeout),
    );
    if (identical(_waiter, waiter)) _waiter = null;
    return RequestResult(f, reply, failure);
  }

  void _receive(Uint8List chunk) {
    for (final raw in _decoder.pushRaw(chunk)) {
      onAnyFrame?.call(raw.frame);
      // A bad checksum never answers a request (the original let one through: docs/behaviour-changes.md).
      if (!raw.ok) {
        crcErrors++;
        continue;
      }
      final f = raw.frame;
      if (!_factory.isRecognised(f)) continue;
      receivedCount++;
      final reply = _factory.create(f);
      final w = _waiter;
      if (w != null && _factory.countsAsReply(f)) {
        _waiter = null;
        if (w.expected.matches(f)) {
          w.finish(reply, Failure.none);
        } else {
          w.finish(null, Failure.mismatch);
        }
      }
      _received.add(Received(f, reply));
    }
  }
}
