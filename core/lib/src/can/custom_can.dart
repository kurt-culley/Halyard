/// The custom CAN configuration (U14-C05 to C12): CAN ids, the twelve receive and twelve transmit messages, their
/// 3780-byte wire form, checks before sending, and the ids the driver's own OEM streams reserve. Check results are
/// typed; the app words them.
library;

import 'dart:typed_data';

import '../definition/definition.dart';
import '../wire/bytes.dart' show fround;
import 'can_bits.dart';

const maxCanId = 0x1fffffff;

/// Hex, with an optional 0x or &H prefix and surrounding white space; at most eight digits and 0x1FFFFFFF.
int? tryParseCanId(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  var t = s.trim();
  final lower = t.toLowerCase();
  if (lower.startsWith('0x') || lower.startsWith('&h')) t = t.substring(2);
  if (t.isEmpty || t.length > 8) return null;
  if (!RegExp(r'^[\t\n\x0B\f\r ]*[0-9a-fA-F]+[\t\n\x0B\f\r ]*$').hasMatch(t)) return null;
  final v = int.parse(t.trim(), radix: 16);
  return v > maxCanId ? null : v;
}

bool isExtendedCanId(int id) => (id & 0xffffffff) > 0x7ff;

/// Upper-case hex, at least three digits.
String formatCanId(int id) => (id & 0xffffffff).toRadixString(16).toUpperCase().padLeft(3, '0');

enum SignalFormat { unsigned, signed, bool, float32 }

enum TxMode { periodic, eventPeriodic, eventOneShot }

final class RxSignal {
  bool enabled = false;
  int format = 0, startBit = 0, bitLength = 1, timeoutMs = 0, dstLinkId = 0;
  double mult = 1, offset = 0, fallback = 0;
}

final class RxMessage {
  bool enabled = false, extended = false, bigEndian = false, muxEnabled = false;
  int canId = 0, muxStartBit = 0, muxBitLength = 1, muxMatch = 0;
  final signals = List.generate(8, (_) => RxSignal(), growable: false);
}

final class TxSignal {
  bool enabled = false, bigEndian = false, signed = false;
  int startBit = 0, bitLength = 1, srcLinkId = 0;
  double mult = 1, offset = 0, constValue = 0;
}

final class TxMessage {
  bool enabled = false, extended = false;
  int canId = 0, mode = 0, freqHz = 10, triggerLinkId = 0;
  final signals = List.generate(8, (_) => TxSignal(), growable: false);
}

final class CustomCanConfig {
  final rx = List.generate(12, (_) => RxMessage(), growable: false);
  final tx = List.generate(12, (_) => TxMessage(), growable: false);

  /// The blob had another layout version, so the configuration started empty.
  bool wasReset = false;

  static const blobSize = 3780, layoutVersion = 2;

  Uint8List encode() {
    final b = ByteData(blobSize);
    var o = 0;
    void u8(int v) => b.setUint8(o++, v & 0xff);
    void u16(int v) {
      b.setUint16(o, v & 0xffff, Endian.little);
      o += 2;
    }

    void u32(int v) {
      b.setUint32(o, v & 0xffffffff, Endian.little);
      o += 4;
    }

    void f32(double v) {
      b.setFloat32(o, v, Endian.little);
      o += 4;
    }

    u8(layoutVersion);
    u8(12);
    u8(12);
    u8(0);
    for (final m in rx) {
      u32(m.canId);
      u8((m.enabled ? 1 : 0) | (m.extended ? 2 : 0) | (m.bigEndian ? 4 : 0) | (m.muxEnabled ? 8 : 0));
      u8(m.muxStartBit);
      u8(m.muxBitLength);
      u8(0);
      u32(m.muxMatch);
      for (final s in m.signals) {
        u8((s.enabled ? 1 : 0) | (s.format << 1));
        u8(s.startBit);
        u8(s.bitLength);
        f32(s.mult);
        f32(s.offset);
        u16(s.timeoutMs);
        f32(s.fallback);
        u16(s.dstLinkId);
      }
    }
    for (final m in tx) {
      u32(m.canId);
      u8((m.enabled ? 1 : 0) | (m.extended ? 2 : 0) | ((m.mode << 2) & 0xff));
      u8(0);
      u16(m.freqHz);
      u16(m.triggerLinkId);
      u16(0);
      for (final s in m.signals) {
        u8((s.enabled ? 1 : 0) | (s.bigEndian ? 2 : 0) | (s.signed ? 4 : 0));
        u8(s.startBit);
        u8(s.bitLength);
        f32(s.mult);
        f32(s.offset);
        u16(s.srcLinkId);
        f32(s.constValue);
      }
    }
    assert(o == blobSize - 32, 'custom CAN layout');
    return b.buffer.asUint8List();
  }

  /// From the wire form; another layout version gives an empty configuration with [wasReset] set.
  static CustomCanConfig decode(Uint8List b) {
    if (b.length != blobSize) throw ArgumentError('custom CAN blob must be $blobSize bytes, not ${b.length}');
    final c = CustomCanConfig();
    if (b[0] != layoutVersion) return c..wasReset = true;
    final d = ByteData.sublistView(b);
    var o = 4;
    int u8() => d.getUint8(o++);
    int u16() {
      final v = d.getUint16(o, Endian.little);
      o += 2;
      return v;
    }

    int u32() {
      final v = d.getUint32(o, Endian.little);
      o += 4;
      return v;
    }

    double f32() {
      final v = d.getFloat32(o, Endian.little);
      o += 4;
      return v;
    }

    for (final m in c.rx) {
      m.canId = u32();
      final f = u8();
      m
        ..enabled = f & 1 != 0
        ..extended = f & 2 != 0
        ..bigEndian = f & 4 != 0
        ..muxEnabled = f & 8 != 0
        ..muxStartBit = u8()
        ..muxBitLength = u8();
      u8();
      m.muxMatch = u32();
      for (final s in m.signals) {
        final g = u8();
        s
          ..enabled = g & 1 != 0
          ..format = (g >> 1) & 3
          ..startBit = u8()
          ..bitLength = u8()
          ..mult = f32()
          ..offset = f32()
          ..timeoutMs = u16()
          ..fallback = f32()
          ..dstLinkId = u16();
      }
    }
    for (final m in c.tx) {
      m.canId = u32();
      final f = u8();
      m
        ..enabled = f & 1 != 0
        ..extended = f & 2 != 0
        ..mode = (f >> 2) & 3;
      u8();
      final freq = u16();
      m
        ..freqHz = freq < 1 ? 1 : (freq > 1000 ? 1000 : freq)
        ..triggerLinkId = u16();
      u16();
      for (final s in m.signals) {
        final g = u8();
        s
          ..enabled = g & 1 != 0
          ..bigEndian = g & 2 != 0
          ..signed = g & 4 != 0
          ..startBit = u8()
          ..bitLength = u8()
          ..mult = f32()
          ..offset = f32()
          ..srcLinkId = u16()
          ..constValue = f32();
      }
    }
    return c;
  }
}

// ---------------------------------------------------------------- checks

enum CanIssueKind {
  /// [CanIssue.a] is the id, [CanIssue.b] the range maximum; [CanIssue.extended] says which range.
  idOutOfRange,

  /// [CanIssue.a] is the id.
  idReserved,

  /// [CanIssue.a] is the length.
  muxLength,

  /// [CanIssue.a] start bit, [CanIssue.b] length.
  muxSpan,

  /// Signal [CanIssue.signal]: [CanIssue.a] start bit, [CanIssue.b] length.
  signalSpan,
  signalMultiplier,

  /// [CanIssue.a] is the length it has.
  signalFloatLength,
  signalNoTarget,

  /// [CanIssue.a] is the channel id.
  signalTargetMissing,

  /// [CanIssue.a] is the rate in Hz.
  rate,
  unknownMode,
  noTrigger,

  /// [CanIssue.a] is the channel id.
  triggerMissing,

  /// A warning: [CanIssue.a] is the channel id; its constant value is sent instead.
  sourceMissing,
}

final class CanIssue {
  const CanIssue(this.kind, {this.signal, this.a = 0, this.b = 0, this.extended = false});
  final CanIssueKind kind;

  /// Signal index from 0, for signal issues.
  final int? signal;
  final int a, b;
  final bool extended;
}

final class CanCheck {
  final errors = <CanIssue>[];
  final warnings = <CanIssue>[];
  bool get isValid => errors.isEmpty;
}

typedef LinkExists = bool Function(int id);

void _checkId(int id, bool extended, Set<int>? reserved, CanCheck v) {
  final max = extended ? 0x1fffffff : 0x7ff;
  final u = id & 0xffffffff;
  if (u > max) v.errors.add(CanIssue(CanIssueKind.idOutOfRange, a: u, b: max, extended: extended));
  if (reserved != null && reserved.contains(u)) v.errors.add(CanIssue(CanIssueKind.idReserved, a: u));
}

void _checkShape(int start, int len, bool bigEndian, double mult, bool isFloat, int i, CanCheck v) {
  if (!spanValid(start, len, bigEndian: bigEndian)) {
    v.errors.add(CanIssue(CanIssueKind.signalSpan, signal: i, a: start, b: len));
  }
  if (mult == 0 || !mult.isFinite) v.errors.add(CanIssue(CanIssueKind.signalMultiplier, signal: i));
  if (isFloat && len != 32) v.errors.add(CanIssue(CanIssueKind.signalFloatLength, signal: i, a: len));
}

CanCheck checkRx(RxMessage m, LinkExists? linkExists, Set<int>? reserved) {
  final v = CanCheck();
  if (!m.enabled) return v;
  _checkId(m.canId, m.extended, reserved, v);
  if (m.muxEnabled) {
    if (m.muxBitLength < 1 || m.muxBitLength > 32) {
      v.errors.add(CanIssue(CanIssueKind.muxLength, a: m.muxBitLength));
    } else if (!spanValid(m.muxStartBit, m.muxBitLength, bigEndian: m.bigEndian)) {
      v.errors.add(CanIssue(CanIssueKind.muxSpan, a: m.muxStartBit, b: m.muxBitLength));
    }
  }
  for (final (i, s) in m.signals.indexed) {
    if (!s.enabled) continue;
    _checkShape(s.startBit, s.bitLength, m.bigEndian, s.mult, s.format == SignalFormat.float32.index, i, v);
    if (s.dstLinkId == 0) {
      v.errors.add(CanIssue(CanIssueKind.signalNoTarget, signal: i));
    } else if (linkExists != null && !linkExists(s.dstLinkId)) {
      v.errors.add(CanIssue(CanIssueKind.signalTargetMissing, signal: i, a: s.dstLinkId));
    }
  }
  return v;
}

CanCheck checkTx(TxMessage m, LinkExists? linkExists, Set<int>? reserved) {
  final v = CanCheck();
  if (!m.enabled) return v;
  _checkId(m.canId, m.extended, reserved, v);
  if (m.freqHz < 1 || m.freqHz > 1000) v.errors.add(CanIssue(CanIssueKind.rate, a: m.freqHz));
  if (m.mode != 0) {
    if (m.mode != 1 && m.mode != 2) {
      v.errors.add(const CanIssue(CanIssueKind.unknownMode));
    } else if (m.triggerLinkId == 0) {
      v.errors.add(const CanIssue(CanIssueKind.noTrigger));
    } else if (linkExists != null && !linkExists(m.triggerLinkId)) {
      v.errors.add(CanIssue(CanIssueKind.triggerMissing, a: m.triggerLinkId));
    }
  }
  for (final (i, s) in m.signals.indexed) {
    if (!s.enabled) continue;
    _checkShape(s.startBit, s.bitLength, s.bigEndian, s.mult, false, i, v);
    if (s.srcLinkId != 0 && linkExists != null && !linkExists(s.srcLinkId)) {
      v.warnings.add(CanIssue(CanIssueKind.sourceMissing, signal: i, a: s.srcLinkId));
    }
  }
  return v;
}

({List<CanCheck> rx, List<CanCheck> tx}) checkCustomCan(
  CustomCanConfig c,
  LinkExists? linkExists,
  Set<int>? reserved,
) => (
  rx: [for (final m in c.rx) checkRx(m, linkExists, reserved)],
  tx: [for (final m in c.tx) checkTx(m, linkExists, reserved)],
);

// ---------------------------------------------------------------- ids the OEM streams reserve

final class ReservedCanId {
  ReservedCanId(this.messageId, {required this.secondary, this.receives = false, this.transmits = false});
  final int messageId;
  final bool secondary;
  bool receives, transmits;
}

/// The CAN ids each OEM stream receives and transmits.
const oemStreams = <int, ({List<int> rx, List<int> tx})>{
  1: (rx: [0x700], tx: [0xfa, 0x77a, 0x63, 0x1ba, 0x101, 0x49a]),
  2: (rx: [0x340], tx: [0x300, 0x301, 0x302, 0x303, 0x304, 0x305, 0x306, 0x307, 0x308]),
  3: (rx: [0x4b0], tx: [0x40, 0x200, 0x201, 0x215, 0x231, 0x240, 0x420, 0x4ec, 0x4f0, 0x4f1, 0x4ff]),
  4: (rx: [], tx: [0x201]),
  5: (rx: [], tx: [0x316, 0x329, 0x545]),
};

/// The value of the driver's first parameter named [name], as an integer (0 without one).
int streamSelection(DriverDef d, Float32List config, String name) {
  for (var i = 0; i < d.configCount && i < d.params.length; i++) {
    if (d.params[i].name == name) {
      final v = fround(config[i]);
      return v.isNaN || v.abs() >= 2147483648 ? -2147483648 : v.truncate();
    }
  }
  return 0;
}

/// The ids reserved by the CAN settings driver's primary and secondary OEM streams; an id both receives and transmits
/// on one stream is listed once.
List<ReservedCanId> reservedCanIds(DriverDef? d, Float32List? config) {
  final list = <ReservedCanId>[];
  if (d == null || config == null) return list;
  void add(int id, bool secondary, {required bool rx}) {
    for (final e in list) {
      if (e.messageId == id && e.secondary == secondary) {
        if (rx) {
          e.receives = true;
        } else {
          e.transmits = true;
        }
        return;
      }
    }
    list.add(ReservedCanId(id, secondary: secondary, receives: rx, transmits: !rx));
  }

  for (final (name, secondary) in [('Pri. Stream Selection', false), ('Sec. Stream Selection', true)]) {
    final s = oemStreams[streamSelection(d, config, name)];
    if (s == null) continue;
    for (final id in s.rx) {
      add(id, secondary, rx: true);
    }
    for (final id in s.tx) {
      add(id, secondary, rx: false);
    }
  }
  return list;
}
