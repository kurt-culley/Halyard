/// Which received frames the app recognises, what they parse to, and which reply a request waits for.
library;

import 'dart:typed_data';

import 'bytes.dart';
import 'framing.dart';
import 'messages/datalog.dart';
import 'messages/drivers.dart';
import 'messages/faults.dart';
import 'messages/reporting.dart';
import 'messages/sys.dart';
import 'messages/tables.dart';
import 'messages/trigger.dart';
import 'reply.dart';

/// Reply commands the app understands, by class. Tables has no 5, Sys has no 2 (the clock reply is never read).
const _replies = <int, Set<int>>{
  0: {0, 1, 2, 3},
  1: {0, 1, 2, 3, 4, 6, 7},
  2: {0, 1, 2, 3},
  4: {0, 1, 3, 4, 5, 6},
  5: {0, 1, 2, 3},
  6: {0, 1, 2, 3, 4, 5, 6, 7, 8, 9},
  7: {0, 1, 2},
  9: {0, 1, 2, 3, 4, 5},
};

/// Requests the ECU sends: the bootloader's region-info and region-data requests.
const _ecuRequests = <int, Set<int>>{
  5: {1, 2},
};

/// Recognised replies that are not answers to a request: reports, lifesign, trigger reports, firmware status, and the
/// password-lock state the ECU pushes.
const _unsolicited = {(0, 0), (0, 1), (7, 2), (5, 3), (4, 4)};

/// Tables commands and the first three Drivers commands carry an entity id after the status byte.
bool isEntityCommand(int cls, int cmd) => cls == 1 || (cls == 2 && cmd <= 2);

typedef _Parser = Reply Function(Uint8List p, int status);
typedef _EntityParser = Reply Function(Uint8List p, int status, int id);

_Parser? _parserFor(int cls, int cmd) => switch ((cls, cmd)) {
  (2, 3) => parseCanReservedIds,
  (4, 0) => parseEcuInfo,
  (4, 1) => parseHash,
  (4, 4) => parsePwLockSet,
  (4, 5) => parsePwLockGet,
  (6, 0) => parseDataLogSupport,
  (6, 1) => parseDataLogConfig,
  (6, 5) => parseLogsSummary,
  (6, 6) => parseLogDetail,
  (6, 7) => parseLogRegion,
  (6, 8) => parseEraseLog,
  (7, 0) => parseTriggerSupport,
  (7, 1) => parseTriggerState,
  (7, 2) => parseTriggerReport,
  (9, 0) => parseFaultInfo,
  (9, 1) => parseFaultFrameLayout,
  (9, 2) => parseFaultSummary,
  (9, 3) => parseFaultOccurrence,
  (9, 4) => parseFaultClear,
  (9, 5) => parseFaultErase,
  _ => null,
};

_EntityParser? _entityParserFor(int cls, int cmd) => switch ((cls, cmd)) {
  (1, 1) || (2, 1) => parseBlobReply,
  (1, 4) => parseSetDataReply,
  _ => null,
};

/// Parses a reply frame of classes 1–9 (class 0 needs a [ReportingDecoder]). Throws [PayloadError] on a malformed
/// payload or an unknown status.
Reply parseReply(Frame f) {
  final p = f.payload;
  final status = u8(p, 0);
  if (!ReplyStatus.isKnown(status)) throw PayloadError('unknown status $status');
  if (isEntityCommand(f.cls, f.cmd)) {
    final id = u16(p, 1);
    return _entityParserFor(f.cls, f.cmd)?.call(p, status, id) ?? EntityReply(status, id);
  }
  return _parserFor(f.cls, f.cmd)?.call(p, status) ?? Reply(status);
}

/// Turns received frames into replies, once per frame object. Holds the live-data layout, so use one per connection.
class MessageFactory {
  final reporting = ReportingDecoder();
  final _cache = Expando<_Parsed>();

  /// The reply, or null when the frame is not a recognised, well-formed reply.
  Reply? create(Frame f) => (_cache[f] ??= _Parsed(_build(f))).reply;

  Reply? _build(Frame f) {
    if (f.type != MsgType.rsp || !(_replies[f.cls]?.contains(f.cmd) ?? false)) return null;
    try {
      if (f.cls == 0) return reporting.decode(f.cmd, f.payload);
      if (f.payload.isEmpty) return null;
      if (isEntityCommand(f.cls, f.cmd) && f.payload.length < 3) return null;
      return parseReply(f);
    } on PayloadError {
      return null;
    }
  }

  bool isRecognised(Frame f) {
    if (f.type == MsgType.rsp) return create(f) != null;
    if (f.type == MsgType.req) {
      if (!(_ecuRequests[f.cls]?.contains(f.cmd) ?? false)) return false;
      return f.payload.length >= (f.cmd == 1 ? 1 : 9);
    }
    return false;
  }

  /// A recognised reply that answers a request (not a report, lifesign or pushed state).
  bool countsAsReply(Frame f) => f.type == MsgType.rsp && isRecognised(f) && !_unsolicited.contains((f.cls, f.cmd));
}

final class _Parsed {
  const _Parsed(this.reply);
  final Reply? reply;
}

/// The entity id of a table or driver reply.
int? entityId(Frame f) =>
    f.type == MsgType.rsp && isEntityCommand(f.cls, f.cmd) && f.payload.length >= 3 ? u16(f.payload, 1) : null;

bool isSuccessful(Frame f) => f.type == MsgType.rsp && f.payload.isNotEmpty && f.payload[0] == 0;

/// What a sent frame waits for. [id] is set for table and driver commands.
final class ExpectedReply {
  const ExpectedReply(this.cls, this.cmd, [this.id]);
  final int cls, cmd;
  final int? id;
  bool matches(Frame f) => f.type == MsgType.rsp && f.cls == cls && f.cmd == cmd && (id == null || entityId(f) == id);
  Map<String, Object?> toJson() => {'type': MsgType.rsp, 'cls': cls, 'cmd': cmd, if (id != null) 'id': id};
}

/// Null for frames that expect nothing: host answers, the drive-by-wire duty, and turning reporting off.
ExpectedReply? expectedReply(Frame req) {
  if (req.hostAnswer) return null;
  if (req.cls == 8 && req.cmd == 0) return null;
  if (req.cls == 0 && req.cmd == ReportingCmd.setState && req.payload.isNotEmpty && req.payload[0] == 0) return null;
  if (!isEntityCommand(req.cls, req.cmd)) return ExpectedReply(req.cls, req.cmd);
  return ExpectedReply(req.cls, req.cmd, req.payload.length >= 2 ? u16(req.payload, 0) : 0);
}
