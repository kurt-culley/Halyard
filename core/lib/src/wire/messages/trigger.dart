/// Class 7: trigger scope. Class 8: drive-by-wire duty override.
library;

import 'dart:typed_data';

import '../bytes.dart';
import '../framing.dart';
import '../reply.dart';

abstract final class TriggerCmd {
  static const isSupported = 0, setState = 1, report = 2;
}

/// Trigger scope channels; [events] is the scope's event lane, not an input.
abstract final class TriggerChannel {
  static const events = -1, crank = 0, camA = 1, camB = 2, camC = 3, camD = 4;
}

Frame triggerIsSupportedRequest() => Frame.request(7, TriggerCmd.isSupported);

/// Channels become a bitmask; only the low eight channels can be expressed.
Frame triggerSetStateRequest(bool enabled, List<int> channels) {
  var mask = 0;
  for (final c in channels) {
    mask = (mask | (1 << (c & 31))) & 0xff;
  }
  return triggerSetStateRequestMask(enabled, mask);
}

Frame triggerSetStateRequestMask(bool enabled, int mask) => Frame.request(
  7,
  TriggerCmd.setState,
  build(
    (w) =>
        w
          ..u8(enabled ? 1 : 0)
          ..u8(mask),
  ),
);

/// Drive-by-wire duty override for one channel. Writes to the throttle: desktop only.
Frame setDbwDutyRequest(int channel, double duty) => Frame.request(
  8,
  0,
  build(
    (w) =>
        w
          ..u8(channel)
          ..f32(duty),
  ),
);

class TriggerSupportReply extends Reply {
  const TriggerSupportReply(super.status, this.availableChannelIds);
  final List<int> availableChannelIds;
  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'availableChannelIds': availableChannelIds};
}

class TriggerStateReply extends Reply {
  const TriggerStateReply(super.status, this.enabled, this.channelBitmask, this.freq);
  final bool enabled;

  /// Eight bits, channel 0 first.
  final List<int> channelBitmask;
  final int freq;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'enabled': enabled,
    'channelBitmask': channelBitmask,
    'freq': freq,
  };
}

class TriggerEvent {
  const TriggerEvent(this.channel, this.state, this.gap, this.syncState);
  final int channel;
  final bool state;

  /// Time since the previous event, in the ECU's timer units.
  final int gap;
  final int syncState;
  Map<String, Object?> toJson() => {'channel': channel, 'state': state, 'gap': gap, 'syncState': syncState};
}

class TriggerReportReply extends Reply {
  const TriggerReportReply(super.status, this.entries);
  final List<TriggerEvent> entries;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'numEntries': entries.length,
    'entries': [for (final e in entries) e.toJson()],
  };
}

List<int> _bits(int m) => [for (var i = 0; i < 8; i++) (m >> i) & 1];

/// Older firmware sends no mask: crank and cam only.
TriggerSupportReply parseTriggerSupport(Uint8List p, int status) => TriggerSupportReply(
  status,
  p.length > 1
      ? [
        for (var i = 0; i < 8; i++)
          if (((p[1] >> i) & 1) == 1) i,
      ]
      : const [0, 1],
);

TriggerStateReply parseTriggerState(Uint8List p, int status) {
  final enabled = u8(p, 1) != 0;
  final mask = u8(p, 2);
  return TriggerStateReply(status, enabled, _bits(mask), u32(p, 3));
}

TriggerReportReply parseTriggerReport(Uint8List p, int status) {
  final n = u16(p, 1);
  final out = <TriggerEvent>[];
  for (var i = 0, o = 3; i < n; i++, o += 3) {
    final b = u8(p, o);
    out.add(TriggerEvent(b & 7, (b & 8) != 0, u16(p, o + 1), (b & 0xf0) >> 4));
  }
  return TriggerReportReply(status, out);
}
