/// Class 9: fault log. Wire format only; the fault catalogue and report text live in `faults/`.
library;

import 'dart:typed_data';

import '../bytes.dart';
import '../framing.dart';
import '../reply.dart';

abstract final class FaultsCmd {
  static const getInfo = 0, frameLayout = 1, summary = 2, occurrence = 3, clear = 4, eraseLog = 5;
}

Frame _req(int cmd, [void Function(ByteWriter w)? body]) => Frame.request(9, cmd, body == null ? null : build(body));

Frame faultsGetInfoRequest() => _req(FaultsCmd.getInfo);
Frame faultsGetFrameLayoutRequest(int start, int count) => _req(
  FaultsCmd.frameLayout,
  (w) =>
      w
        ..u16(start)
        ..u16(count < 200 ? count : 200),
);
Frame faultsGetSummaryRequest(int start, int count) => _req(
  FaultsCmd.summary,
  (w) =>
      w
        ..u16(start)
        ..u16(count < 40 ? count : 40),
);
Frame faultsGetOccurrenceRequest(int ordinal) => _req(FaultsCmd.occurrence, (w) => w.u16(ordinal));

/// Clears the fault counters on the ECU: desktop only.
Frame faultsClearRequest() => _req(FaultsCmd.clear);

/// Erases the fault history on the ECU: desktop only.
Frame faultsEraseLogRequest() => _req(FaultsCmd.eraseLog);

class FaultLogInfo {
  const FaultLogInfo({
    required this.catalogueVersion,
    required this.numCodes,
    required this.slotSize,
    required this.frameLength,
    required this.numFrameLinks,
    required this.logCapacity,
    required this.logUsed,
    required this.numSummary,
    required this.engineHoursX100,
    required this.mode,
    required this.logStatus,
    required this.dropped,
  });
  final int catalogueVersion, numCodes, slotSize, frameLength, numFrameLinks, logCapacity, logUsed, numSummary;
  final int engineHoursX100, mode, logStatus, dropped;
  static const size = 24;

  Map<String, Object?> toJson() => {
    'catalogueVersion': catalogueVersion,
    'numCodes': numCodes,
    'slotSize': slotSize,
    'frameLength': frameLength,
    'numFrameLinks': numFrameLinks,
    'logCapacity': logCapacity,
    'logUsed': logUsed,
    'numSummary': numSummary,
    'engineHoursX100': engineHoursX100,
    'mode': mode,
    'logStatus': logStatus,
    'dropped': dropped,
  };
}

FaultLogInfo parseFaultLogInfo(Uint8List p, int o) => FaultLogInfo(
  catalogueVersion: u16(p, o),
  numCodes: u16(p, o + 2),
  slotSize: u16(p, o + 4),
  frameLength: u16(p, o + 6),
  numFrameLinks: u16(p, o + 8),
  logCapacity: u16(p, o + 10),
  logUsed: u16(p, o + 12),
  numSummary: u16(p, o + 14),
  engineHoursX100: u32(p, o + 16),
  mode: u8(p, o + 20),
  logStatus: u8(p, o + 21),
  dropped: u16(p, o + 22),
);

/// One channel in a fault's freeze frame. Type, name and unit come from the definition later.
class FaultFrameLayoutEntry {
  const FaultFrameLayoutEntry(this.linkId, this.size);
  final int linkId;
  final int size;
  static const wireSize = 3;
  Map<String, Object?> toJson() => {'linkId': linkId, 'size': size, 'type': null, 'name': null, 'unit': null};
}

class FaultSummaryEntry {
  const FaultSummaryEntry({
    required this.code,
    required this.state,
    required this.severity,
    required this.count,
    required this.lifetime,
    required this.firstHoursX100,
    required this.firstRtc,
    required this.lastHoursX100,
    required this.lastRtc,
  });
  final int code, state, severity, count, lifetime, firstHoursX100, firstRtc, lastHoursX100, lastRtc;
  static const size = 26;

  Map<String, Object?> toJson() => {
    'code': code,
    'state': state,
    'severity': severity,
    'count': count,
    'lifetime': lifetime,
    'firstHoursX100': firstHoursX100,
    'firstRtc': firstRtc,
    'lastHoursX100': lastHoursX100,
    'lastRtc': lastRtc,
  };
}

FaultSummaryEntry parseFaultSummaryEntry(Uint8List p, int o) => FaultSummaryEntry(
  code: u16(p, o),
  state: u8(p, o + 2),
  severity: u8(p, o + 3),
  count: u16(p, o + 4),
  lifetime: u32(p, o + 6),
  firstHoursX100: u32(p, o + 10),
  firstRtc: u32(p, o + 14),
  lastHoursX100: u32(p, o + 18),
  lastRtc: u32(p, o + 22),
);

/// One record from the fault history.
class FaultLogRecord {
  const FaultLogRecord({
    required this.ordinal,
    required this.magic,
    required this.type,
    required this.catalogueVersion,
    required this.seq,
    required this.code,
    required this.count,
    required this.lifetime,
    required this.hoursX100,
    required this.rtc,
    required this.bodyLength,
    required this.slotSize,
    required this.body,
  });
  final int ordinal, magic, type, catalogueVersion, seq, code, count, lifetime, hoursX100, rtc, bodyLength, slotSize;
  final Uint8List body;
  static const headerSize = 28;
  static const validMagic = 0xfa17;
  bool get isValid => magic == validMagic;

  Map<String, Object?> toJson() => {
    'ordinal': ordinal,
    'magic': magic,
    'type': type,
    'catalogueVersion': catalogueVersion,
    'seq': seq,
    'code': code,
    'count': count,
    'lifetime': lifetime,
    'hoursX100': hoursX100,
    'rtc': rtc,
    'bodyLength': bodyLength,
    'slotSize': slotSize,
    'body': body,
  };
}

/// The body is cut to what both the slot and the payload hold.
FaultLogRecord parseFaultLogRecord(int ordinal, Uint8List p, int o, int size) {
  if (size < FaultLogRecord.headerSize || p.length < o + FaultLogRecord.headerSize) {
    throw const PayloadError('fault record shorter than its header');
  }
  final bodyLength = u16(p, o + 24);
  final start = o + FaultLogRecord.headerSize;
  final avail = _min(size - FaultLogRecord.headerSize, p.length - start);
  final n = _max(0, _min(bodyLength, avail));
  return FaultLogRecord(
    ordinal: ordinal,
    magic: u16(p, o),
    type: u8(p, o + 2),
    catalogueVersion: u8(p, o + 3),
    seq: u32(p, o + 4),
    code: u16(p, o + 8),
    count: u16(p, o + 10),
    lifetime: u32(p, o + 12),
    hoursX100: u32(p, o + 16),
    rtc: u32(p, o + 20),
    bodyLength: bodyLength,
    slotSize: u16(p, o + 26),
    body: Uint8List.fromList(p.sublist(start, start + n)),
  );
}

int _min(int a, int b) => a < b ? a : b;
int _max(int a, int b) => a > b ? a : b;

class FaultInfoReply extends Reply {
  const FaultInfoReply(super.status, this.info);

  /// Null when the ECU refused or sent too little.
  final FaultLogInfo? info;
  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'info': info?.toJson()};
}

/// GetFrameLayout and GetSummary: a page of [entries] from [start] out of [total].
class FaultPageReply<T> extends Reply {
  const FaultPageReply(super.status, this.start, this.count, this.total, this.entries, this._json);
  final int start, count, total;
  final List<T> entries;
  final Map<String, Object?> Function(T) _json;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'entries': [for (final e in entries) _json(e)],
    'start': start,
    'num': count,
    'total': total,
  };
}

class FaultOccurrenceReply extends Reply {
  const FaultOccurrenceReply(super.status, this.ordinal, this.size, this.record);
  final int ordinal, size;
  final FaultLogRecord? record;

  /// The ECU answers "invalid parameter" past the last record.
  bool get isEndOfHistory => status == ReplyStatus.invalidParameter;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'ordinal': ordinal,
    'size': size,
    'record': record?.toJson(),
    'isEndOfHistory': isEndOfHistory,
  };
}

/// Clear and EraseLog: "busy" means the ECU refused (erase refuses while the engine runs).
class FaultActionReply extends Reply {
  const FaultActionReply(super.status, this._key);
  final String _key;
  bool get refused => status == ReplyStatus.busy;
  @override
  Map<String, Object?> toJson() => {...super.toJson(), _key: refused};
}

FaultInfoReply parseFaultInfo(Uint8List p, int status) =>
    FaultInfoReply(status, status == 0 && p.length >= 1 + FaultLogInfo.size ? parseFaultLogInfo(p, 1) : null);

FaultPageReply<T> _page<T>(
  Uint8List p,
  int status,
  int entrySize,
  T Function(Uint8List p, int o) parse,
  Map<String, Object?> Function(T) json,
) {
  if (status != 0 || p.length < 7) return FaultPageReply<T>(status, 0, 0, 0, <T>[], json);
  final start = u16(p, 1), count = u16(p, 3), total = u16(p, 5);
  final entries = <T>[];
  for (var i = 0, o = 7; i < count && o + entrySize <= p.length; i++, o += entrySize) {
    entries.add(parse(p, o));
  }
  return FaultPageReply<T>(status, start, count, total, entries, json);
}

FaultPageReply<FaultFrameLayoutEntry> parseFaultFrameLayout(Uint8List p, int status) => _page(
  p,
  status,
  FaultFrameLayoutEntry.wireSize,
  (p, o) => FaultFrameLayoutEntry(u16(p, o), u8(p, o + 2)),
  (e) => e.toJson(),
);

FaultPageReply<FaultSummaryEntry> parseFaultSummary(Uint8List p, int status) =>
    _page(p, status, FaultSummaryEntry.size, parseFaultSummaryEntry, (e) => e.toJson());

FaultOccurrenceReply parseFaultOccurrence(Uint8List p, int status) {
  var ordinal = 0, size = 0;
  if (p.length >= 5) {
    ordinal = u16(p, 1);
    size = u16(p, 3);
  }
  final record =
      status == 0 && size >= FaultLogRecord.headerSize && p.length >= 5 + FaultLogRecord.headerSize
          ? parseFaultLogRecord(ordinal, p, 5, _min(size, p.length - 5))
          : null;
  return FaultOccurrenceReply(status, ordinal, size, record);
}

FaultActionReply parseFaultClear(Uint8List p, int status) => FaultActionReply(status, 'isBusy');
FaultActionReply parseFaultErase(Uint8List p, int status) => FaultActionReply(status, 'isRefusedEngineRunning');
