/// Reading what the fault log holds: hour and clock stamps, record bodies, freeze frames and the active-code bits
/// (U13-C04 to C07).
library;

import 'dart:typed_data';

import '../wire/bytes.dart';
import '../wire/messages/faults.dart';
import 'fault_codes.dart';

/// Engine hours from hundredths, as a float.
double faultHours(int x100) => fround(fround(x100.toDouble()) / 100);

/// The ECU's clock stamp: minutes since 2020-01-01 00:00, or null for 0. Kept as UTC components.
DateTime? faultRtc(int minutes) {
  if (minutes == 0) return null;
  final d = DateTime.utc(2020).add(Duration(minutes: minutes & 0xffffffff));
  if (d.year > 9999) throw RangeError('fault clock stamp $minutes is past year 9999');
  return d;
}

/// One code's counters in a checkpoint record.
final class FaultCheckpointEntry {
  const FaultCheckpointEntry(
    this.code,
    this.count,
    this.lifetime,
    this.firstHoursX100,
    this.firstRtc,
    this.lastHoursX100,
    this.lastRtc,
  );
  final int code, count, lifetime, firstHoursX100, firstRtc, lastHoursX100, lastRtc;
}

extension FaultRecordBody on FaultLogRecord {
  FaultCode get catalogueEntry => faultCode(code);

  /// Logging-mode change: the mode before and after.
  int? get oldMode => type == FaultRecordType.config && body.length >= 2 ? body[0] : null;
  int? get newMode => type == FaultRecordType.config && body.length >= 2 ? body[1] : null;

  int? get checkpointHoursX100 => type == FaultRecordType.checkpoint && body.length >= 4 ? u32(body, 0) : null;

  List<FaultCheckpointEntry> get checkpointEntries {
    if (type != FaultRecordType.checkpoint || body.length < 6) return const [];
    final n = u16(body, 4);
    return [
      for (var i = 0, o = 6; i < n && o + 24 <= body.length; i++, o += 24)
        FaultCheckpointEntry(
          u16(body, o),
          u16(body, o + 2),
          u32(body, o + 4),
          u32(body, o + 8),
          u32(body, o + 12),
          u32(body, o + 16),
          u32(body, o + 20),
        ),
    ];
  }
}

/// Reporting value types, as the live-data layout gives them.
abstract final class FrameValueType {
  static const float = 0, int16 = 1, uint16 = 2, int8 = 3, uint8 = 4, bool8 = 5;
}

/// One freeze-frame channel: the link, its size in bytes, and its value type when the live-data layout gave one.
final class FrameChannel {
  const FrameChannel(this.linkId, this.size, [this.type]);
  final int linkId, size;
  final int? type;

  /// Without a type: one byte is unsigned, two bytes unsigned, anything else a float.
  int get effectiveType =>
      type ?? (size == 1 ? FrameValueType.uint8 : (size == 2 ? FrameValueType.uint16 : FrameValueType.float));
}

/// Decodes a freeze frame: channels in order until one has size 0 or runs past the body. Floats are 4 bytes; other
/// sizes of a float channel read as unsigned integers; integers of 1, 2 and 4 bytes, other sizes read 0.
List<(int linkId, double value)> decodeFreezeFrame(List<FrameChannel> layout, Uint8List body) {
  final out = <(int, double)>[];
  var o = 0;
  for (final c in layout) {
    final size = c.size;
    if (size <= 0 || o + size > body.length) break;
    final double v = switch (c.effectiveType) {
      FrameValueType.float => size == 4 ? f32(body, o) : _integer(body, o, size, signed: false),
      FrameValueType.int16 || FrameValueType.int8 => _integer(body, o, size, signed: true),
      _ => _integer(body, o, size, signed: false),
    };
    out.add((c.linkId, fround(v)));
    o += size;
  }
  return out;
}

double _integer(Uint8List b, int o, int size, {required bool signed}) => switch (size) {
  1 => (signed ? i8(b, o) : u8(b, o)).toDouble(),
  2 => (signed ? i16(b, o) : u16(b, o)).toDouble(),
  4 => fround((signed ? u32(b, o).toSigned(32) : u32(b, o)).toDouble()),
  _ => 0,
};

/// Catalogue indexes of the active codes, from the three active-bit link values (24 bits each).
Set<int> activeFaultIndexes(double a, double b, double c) {
  final s = <int>{};
  void add(double v, int base) {
    if (v.isNaN || !(v > 0)) return;
    final bits = v >= 2147483648 ? -2147483648 : v.truncate();
    for (var i = 0; i < 24; i++) {
      if (bits & (1 << i) != 0) s.add(base + i);
    }
  }

  add(a, 0);
  add(b, 24);
  add(c, 48);
  return s;
}
