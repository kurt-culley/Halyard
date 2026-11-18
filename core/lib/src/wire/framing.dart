import 'dart:typed_data';

import 'bytes.dart';

/// Frame direction byte.
abstract final class MsgType {
  static const req = 0x00;
  static const rsp = 0x0f;
}

/// One protocol frame: type, message class, command and payload.
///
/// [hostAnswer] marks a frame the host sends as an *answer* to an ECU request (a lifesign ack, a firmware region). Such
/// frames never wait for a reply.
final class Frame {
  Frame(this.type, this.cls, this.cmd, [Uint8List? payload, this.hostAnswer = false])
    : payload = payload ?? Uint8List(0);

  Frame.request(int cls, int cmd, [Uint8List? payload]) : this(MsgType.req, cls, cmd, payload);

  final int type;
  final int cls;
  final int cmd;
  final Uint8List payload;
  final bool hostAnswer;

  /// type, cls, cmd and payload as hex: the form the test vectors use.
  String get hex => toHex([type, cls, cmd, ...payload]);

  @override
  String toString() => 'Frame($hex)';
}

const sof = [0x4d, 0x45]; // "ME"

int fletcher16(List<int> data) {
  var s1 = 0, s2 = 0;
  for (final b in data) {
    s1 = (s1 + b) % 255;
    s2 = (s2 + s1) % 255;
  }
  return (s2 << 8) | s1;
}

int frameChecksum(Frame f) => fletcher16([f.type, f.cls, f.cmd, ...f.payload]);

/// `M E len16 type cls cmd payload crc16`. The length field keeps only 16 bits, as the original does.
Uint8List encodeFrame(Frame f) {
  final n = f.payload.length;
  final out =
      Uint8List(9 + n)
        ..[0] = sof[0]
        ..[1] = sof[1]
        ..[2] = n & 0xff
        ..[3] = (n >> 8) & 0xff
        ..[4] = f.type
        ..[5] = f.cls
        ..[6] = f.cmd
        ..setRange(7, 7 + n, f.payload);
  final crc = frameChecksum(f);
  out[7 + n] = crc & 0xff;
  out[8 + n] = crc >> 8;
  return out;
}

/// A complete frame and its checksum verdict.
final class RawFrame {
  const RawFrame(this.frame, this.received, this.expected);
  final Frame frame;
  final int received;
  final int expected;
  bool get ok => received == expected;
}

enum _S { huntM, huntE, len, header, payload, crc }

/// Byte-stream to frames. Hunts for "ME", reads the length and header, then the payload and checksum; a stray "M"
/// after "M" keeps hunting for "E". Chunking never changes the result.
class FrameDecoder {
  void Function(RawFrame bad)? onCrcError;

  var _state = _S.huntM;
  final _buf = <int>[];
  final _header = <int>[];
  var _len = 0;
  var _payload = Uint8List(0);
  var _pos = 0;

  void reset() {
    _state = _S.huntM;
    _buf.clear();
    _header.clear();
    _pos = 0;
  }

  /// Every complete frame in [chunk], with its checksum verdict.
  List<RawFrame> pushRaw(List<int> chunk) {
    final out = <RawFrame>[];
    for (final b in chunk) {
      switch (_state) {
        case _S.huntM:
          if (b == sof[0]) _state = _S.huntE;
        case _S.huntE:
          if (b == sof[1]) {
            _state = _S.len;
            _buf.clear();
          } else if (b != sof[0]) {
            _state = _S.huntM;
          }
        case _S.len:
          _buf.add(b);
          if (_buf.length == 2) {
            _len = _buf[0] | (_buf[1] << 8);
            _header.clear();
            _state = _S.header;
          }
        case _S.header:
          _header.add(b);
          if (_header.length == 3) {
            _payload = Uint8List(_len);
            _pos = 0;
            _buf.clear();
            _state = _len > 0 ? _S.payload : _S.crc;
          }
        case _S.payload:
          _payload[_pos++] = b;
          if (_pos == _len) {
            _state = _S.crc;
            _buf.clear();
          }
        case _S.crc:
          _buf.add(b);
          if (_buf.length < 2) break;
          final frame = Frame(_header[0], _header[1], _header[2], _payload);
          final received = _buf[0] | (_buf[1] << 8);
          reset();
          out.add(RawFrame(frame, received, frameChecksum(frame)));
      }
    }
    return out;
  }

  /// Good frames only; bad checksums go to [onCrcError].
  List<Frame> push(List<int> chunk) {
    final out = <Frame>[];
    for (final r in pushRaw(chunk)) {
      if (r.ok) {
        out.add(r.frame);
      } else {
        onCrcError?.call(r);
      }
    }
    return out;
  }
}
