/// Class 6: on-board data logging.
library;

import 'dart:typed_data';

import '../bytes.dart';
import '../framing.dart';
import '../reply.dart';

abstract final class DataLogCmd {
  static const isSupported = 0, getConfig = 1, setConfig = 2, start = 3, stop = 4, logsSummary = 5, logDetail = 6;
  static const logRegion = 7, eraseLog = 8, formatMemory = 9;
}

Frame _req(int cmd, [void Function(ByteWriter w)? body]) => Frame.request(6, cmd, body == null ? null : build(body));

Frame isSupportedRequest() => _req(DataLogCmd.isSupported);
Frame getConfigRequest() => _req(DataLogCmd.getConfig);
Frame startRequest() => _req(DataLogCmd.start);
Frame stopRequest() => _req(DataLogCmd.stop);
Frame getLogsSummaryRequest() => _req(DataLogCmd.logsSummary);
Frame formatMemoryRequest() => _req(DataLogCmd.formatMemory);
Frame eraseLogRequest(int id) => _req(DataLogCmd.eraseLog, (w) => w.u8(id));
Frame getLogDetailRequest(int id) => _req(DataLogCmd.logDetail, (w) => w.u16(id));
Frame getLogRegionRequest(int id, int start, int count) => _req(
  DataLogCmd.logRegion,
  (w) =>
      w
        ..u8(id)
        ..u32(start)
        ..u32(count),
);
Frame setConfigRequest(int frequency, bool switchActiveState, List<int> ids) => _req(DataLogCmd.setConfig, (w) {
  w
    ..u16(frequency)
    ..u16(ids.length)
    ..u8(switchActiveState ? 1 : 0);
  ids.forEach(w.u16);
});

/// Calendar time to the minute, validated as a real date.
class LogTimestamp {
  LogTimestamp(this.year, this.month, this.day, this.hour, this.minute) {
    if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1 || day > _daysIn(year, month)) {
      throw const PayloadError('not a date');
    }
    if (hour > 23 || minute > 59) throw const PayloadError('not a time');
  }
  final int year, month, day, hour, minute;

  static int _daysIn(int y, int m) {
    final leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    return const [31, 0, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1] + (m == 2 ? (leap ? 29 : 28) : 0);
  }

  Map<String, Object?> toJson() => {'year': year, 'month': month, 'day': day, 'hour': hour, 'minute': minute};
}

/// One log in the ECU's memory.
class LogInfo {
  const LogInfo(this.id, this.timestamp, this.durationSeconds, this.numEntries, this.numOfChannels);
  final int id;
  final LogTimestamp timestamp;
  final double durationSeconds;
  final int numEntries;
  final int numOfChannels;
  static const size = 17;

  Map<String, Object?> toJson() => {
    'id': id,
    'timestamp': timestamp.toJson(),
    'durationSeconds': durationSeconds,
    'numEntries': numEntries,
    'numOfChannels': numOfChannels,
  };
}

LogInfo parseLogInfo(Uint8List p, int o) {
  final id = u8(p, o);
  final day = u8(p, o + 1), month = u8(p, o + 2), year = u16(p, o + 3), hour = u8(p, o + 5), minute = u8(p, o + 6);
  final duration = f32(p, o + 7);
  final entries = u32(p, o + 11);
  final channels = u16(p, o + 15);
  return LogInfo(id, LogTimestamp(year, month, day, hour, minute), duration, entries, channels);
}

/// One sample row: time in seconds (single precision) and one value per channel.
class LogEntry {
  const LogEntry(this.timestamp, this.values);
  final double timestamp;
  final List<double> values;
  static int size(int channels) => 4 + channels * 4;
  Map<String, Object?> toJson() => {'timestamp': timestamp, 'values': values};
}

LogEntry parseLogEntry(int channels, Uint8List p, int o) =>
    LogEntry(fround(f32(p, o) / 1000), [for (var i = 0; i < channels; i++) f32(p, o + 4 + 4 * i)]);

class DataLogSupportReply extends Reply {
  const DataLogSupportReply(super.status, this.maxFrequency, this.maxNumChans);
  final int maxFrequency;
  final int maxNumChans;
  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'maxFrequency': maxFrequency, 'maxNumChans': maxNumChans};
}

class DataLogConfigReply extends Reply {
  const DataLogConfigReply(super.status, this.freq, this.switchActiveState, this.loggedIds);
  final int freq;
  final bool switchActiveState;
  final List<int> loggedIds;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'freq': freq,
    'numOfChans': loggedIds.length,
    'switchActiveState': switchActiveState,
    'loggedIds': loggedIds,
  };
}

class EraseLogReply extends Reply {
  const EraseLogReply(super.status, this.logId);
  final int logId;
  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'logId': logId};
}

class LogsSummaryReply extends Reply {
  const LogsSummaryReply(super.status, this.logs);
  final List<LogInfo> logs;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'numLogs': logs.length,
    'logsSummaries': [for (final l in logs) l.toJson()],
  };
}

class LogDetailReply extends Reply {
  const LogDetailReply(super.status, this.summary, this.chanIds);
  final LogInfo summary;
  final List<int> chanIds;
  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'summary': summary.toJson(), 'chanIds': chanIds};
}

class LogRegionReply extends Reply {
  const LogRegionReply(super.status, this.idx, this.numOfChans, this.startEntry, this.entries);
  final int idx;
  final int numOfChans;
  final int startEntry;
  final List<LogEntry> entries;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'idx': idx,
    'numOfChans': numOfChans,
    'startEntry': startEntry,
    'numEntries': entries.length,
    'entries': [for (final e in entries) e.toJson()],
  };
}

DataLogSupportReply parseDataLogSupport(Uint8List p, int status) => DataLogSupportReply(status, u16(p, 1), u16(p, 3));

DataLogConfigReply parseDataLogConfig(Uint8List p, int status) {
  final freq = u16(p, 1);
  final n = u16(p, 3);
  final sas = u8(p, 5) != 0;
  return DataLogConfigReply(status, freq, sas, [for (var i = 0; i < n; i++) u16(p, 6 + i * 2)]);
}

EraseLogReply parseEraseLog(Uint8List p, int status) => EraseLogReply(status, u8(p, 1));

LogsSummaryReply parseLogsSummary(Uint8List p, int status) {
  final n = u16(p, 1);
  return LogsSummaryReply(status, [for (var i = 0; i < n; i++) parseLogInfo(p, 11 + i * LogInfo.size)]);
}

LogDetailReply parseLogDetail(Uint8List p, int status) {
  final s = parseLogInfo(p, 1);
  return LogDetailReply(status, s, [for (var i = 0; i < s.numOfChannels; i++) u16(p, 18 + i * 2)]);
}

LogRegionReply parseLogRegion(Uint8List p, int status) {
  final idx = u8(p, 1);
  final nc = u16(p, 2);
  final start = u32(p, 4);
  final ne = u32(p, 8);
  final entries = <LogEntry>[];
  for (var i = 0, o = 12; i < ne; i++, o += LogEntry.size(nc)) {
    entries.add(parseLogEntry(nc, p, o));
  }
  return LogRegionReply(status, idx, nc, start, entries);
}
