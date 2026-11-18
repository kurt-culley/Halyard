/// Class 0: live-data reporting. Report frames carry no layout of their own, so decoding them needs the layout from the
/// last SetState or SetSpecialCfg reply: [ReportingDecoder] holds it.
library;

import 'dart:typed_data';

import '../bytes.dart';
import '../framing.dart';
import '../reply.dart';

abstract final class ReportingCmd {
  static const report = 0, ack = 1, setState = 2, setSpecialCfg = 3;
}

/// Value encodings in a version-2 report.
abstract final class ValueType {
  static const float32 = 0, int16 = 1, uint16 = 2, int8 = 3, uint8 = 4, bool8 = 5;
  static int size(int t) => switch (t) {
    1 || 2 => 2,
    3 || 4 || 5 => 1,
    _ => 4,
  };
}

Frame setStateRequest(bool enabled) => Frame.request(0, ReportingCmd.setState, build((w) => w.u8(enabled ? 1 : 0)));

/// High-rate channel list (frequency, then link ids).
Frame setSpecialCfgRequest(int frequency, List<int> ids) => Frame.request(
  0,
  ReportingCmd.setSpecialCfg,
  build((w) {
    w
      ..u8(frequency)
      ..u16(ids.length);
    ids.forEach(w.u16);
  }),
);

/// The host's lifesign, sent while reporting is on. A request-type frame that expects no reply.
Frame ackFrame() => Frame(MsgType.req, 0, ReportingCmd.ack, Uint8List.fromList([0]), true);

class LinkLayout {
  const LinkLayout(this.id, this.type);
  final int id;
  final int type;
  Map<String, Object?> toJson() => {'id': id, 'type': type};
}

class ReportedValue {
  const ReportedValue(this.id, this.value);
  final int id;
  final num value;
  Map<String, Object?> toJson() => {'id': id, 'value': value};
}

/// SetState and SetSpecialCfg replies: the layout of the reports that follow.
class ReportingLayoutReply extends Reply {
  const ReportingLayoutReply(super.status, this.entityMap, {this.protoVersion, this.frequency});
  final List<LinkLayout> entityMap;

  /// SetState only: 1 when the reply has no layout (reports carry ids), 2 when it does.
  final int? protoVersion;

  /// SetSpecialCfg only.
  final int? frequency;
  int get numberOfLinks => entityMap.length;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    if (protoVersion != null) 'protoVersion': protoVersion,
    if (frequency != null) 'frequency': frequency,
    'numberOfLinks': numberOfLinks,
    'entityMap': [for (final e in entityMap) e.toJson()],
  };
}

class ReportReply extends Reply {
  const ReportReply(super.status, this.entities);
  final List<ReportedValue> entities;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'entities': [for (final e in entities) e.toJson()],
  };
}

int _status(Uint8List p) {
  final s = u8(p, 0);
  if (!ReplyStatus.isKnown(s)) throw PayloadError('unknown status $s');
  return s;
}

List<LinkLayout> _layout(Uint8List p, int count, int start) => [
  for (var i = 0, o = start; i < count; i++, o += 3) LinkLayout(u16(p, o), u8(p, o + 2)),
];

/// Decodes class-0 replies in order, keeping the report layout between them. One per connection.
class ReportingDecoder {
  /// 1: reports list (id, float) pairs. 2: reports are packed values in layout order.
  int version = 1;

  /// Link id to value type, in layout order. A repeated id keeps its first position and its last type.
  final Map<int, int> links = {};

  Reply decode(int cmd, Uint8List p) {
    switch (cmd) {
      case ReportingCmd.setState:
        {
          links.clear();
          final status = _status(p);
          final r =
              p.length == 1
                  ? ReportingLayoutReply(status, const [], protoVersion: 1)
                  : ReportingLayoutReply(status, _layout(p, u16(p, 1), 3), protoVersion: 2);
          version = r.protoVersion!;
          _apply(r.entityMap);
          return r;
        }
      case ReportingCmd.setSpecialCfg:
        {
          links.clear();
          final status = _status(p);
          final frequency = u8(p, 1);
          final r = ReportingLayoutReply(status, _layout(p, u16(p, 2), 4), frequency: frequency);
          _apply(r.entityMap);
          return r;
        }
      case ReportingCmd.ack:
        return Reply(_status(p));
      case ReportingCmd.report:
        try {
          return _report(p, version);
        } on PayloadError {
          // A version-2 report that doesn't fit the layout may be an old-style report: if it parses as one, switch.
          if (version != 2) rethrow;
          final r = _report(p, 1); // throws the same kind of error when it doesn't fit either
          version = 1;
          links.clear();
          return r;
        }
      default:
        throw PayloadError('unknown reporting command $cmd');
    }
  }

  void _apply(List<LinkLayout> map) {
    for (final e in map) {
      links[e.id] = e.type;
    }
  }

  ReportReply _report(Uint8List p, int version) {
    final status = _status(p);
    final out = <ReportedValue>[];
    if (version == 1) {
      final n = u16(p, 1);
      for (var i = 0; i < n; i++) {
        out.add(ReportedValue(u16(p, 3 + i * 6), f32(p, 5 + i * 6)));
      }
    } else if (version == 2) {
      var o = 1;
      for (final MapEntry(key: id, value: type) in links.entries) {
        final num v = switch (type) {
          ValueType.float32 => f32(p, o),
          ValueType.int16 => i16(p, o),
          ValueType.uint16 => u16(p, o),
          ValueType.int8 => i8(p, o),
          ValueType.uint8 || ValueType.bool8 => u8(p, o),
          _ => 0,
        };
        out.add(ReportedValue(id, v));
        o += ValueType.size(type);
      }
    }
    return ReportReply(status, out);
  }
}
