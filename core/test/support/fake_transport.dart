/// An in-memory transport with a scriptable ECU on the other end.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';

/// A reply frame from the ECU.
Frame rsp(int cls, int cmd, List<int> payload) => Frame(MsgType.rsp, cls, cmd, Uint8List.fromList(payload));

/// A successful identity reply.
Frame ecuInfoReply([String fields = 'ME360\u0000V2D\u000089\u00001.0']) => rsp(4, 0, [0, ...utf8.encode(fields)]);

class FakeTransport implements Transport {
  FakeTransport({this.respond, this.baud = 230400});

  /// Frames to send back for each frame written.
  List<Frame> Function(Frame written, FakeTransport t)? respond;
  int baud;
  bool failWrites = false;
  bool closed = false;
  final written = <Frame>[];

  final _in = StreamController<Uint8List>();
  final _dec = FrameDecoder();

  @override
  Stream<Uint8List> get input => _in.stream;

  @override
  Future<void> write(Uint8List bytes) async {
    if (failWrites) throw StateError('write failed');
    for (final f in _dec.push(bytes)) {
      written.add(f);
      for (final r in respond?.call(f, this) ?? const <Frame>[]) {
        deliver(r);
      }
    }
  }

  void deliver(Frame f) => deliverBytes(encodeFrame(f));
  void deliverBytes(List<int> b) {
    if (!_in.isClosed) _in.add(Uint8List.fromList(b));
  }

  /// The link drops from the far end.
  Future<void> drop() => _in.close();

  @override
  Future<void> setBaudRate(int b) async => baud = b;

  // Not awaited: once the reader has cancelled, StreamController.close() settles on a root-zone future that
  // fake_async never flushes. A real port's close() doesn't depend on its reader.
  @override
  Future<void> close() async {
    closed = true;
    if (!_in.isClosed) unawaited(_in.close());
  }
}

/// Answers the identity request, only at [answerAt] baud when given.
List<Frame> answerIdentity(Frame f, FakeTransport t, {int? answerAt}) =>
    f.cls == 4 && f.cmd == 0 && (answerAt == null || t.baud == answerAt) ? [ecuInfoReply()] : const [];
