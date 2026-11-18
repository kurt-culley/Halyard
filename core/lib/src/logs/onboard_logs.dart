/// The ECU's own data logger (U12): what it supports, its configuration, the logs it holds, and downloading one. A
/// download asks for the log's channels, then its entries in regions of at most 512 bytes, as the original did.
library;

import 'dart:async';

import '../definition/definition.dart';
import '../link/channel.dart';
import '../wire/framing.dart' show Frame;
import '../wire/messages/datalog.dart';
import 'number_text.dart';

/// Logging rates the original offered, up to the ECU's maximum.
const onboardLogFrequencies = [10, 25, 40, 50, 75, 100];

/// The logger's state as the ECU reports it on link 1015: idle 1, logging 2.
abstract final class OnboardLogStatus {
  static const statusLink = 1015, entriesLink = 1018;
  static const idle = 1, logging = 2;
}

final class OnboardLogSupport {
  const OnboardLogSupport(this.maxFrequency, this.maxChannels);
  final int maxFrequency, maxChannels;
  List<int> get frequencies => [
    for (final f in onboardLogFrequencies)
      if (f <= maxFrequency) f,
  ];
}

/// A request the ECU didn't answer, or answered with a failure.
class OnboardLogError implements Exception {
  const OnboardLogError(this.command, [this.status]);

  /// The class-6 command ([DataLogCmd]).
  final int command;

  /// Null when there was no answer.
  final int? status;
  @override
  String toString() => 'OnboardLogError(command $command, ${status == null ? 'no answer' : 'status $status'})';
}

/// A downloaded log.
final class OnboardLog {
  OnboardLog(this.info, this.channelIds, this.entries);
  final LogInfo info;
  final List<int> channelIds;
  final List<LogEntry> entries;

  /// The original's CSV: a "Time" header and the channels' names, then each entry's time and values, every field
  /// followed by a comma, CRLF line ends. A channel the definition lacks is headed by its id; the original could not
  /// save such a log (docs/behaviour-changes.md).
  String toCsv(Definition definition) {
    final b = StringBuffer('Time');
    for (final id in channelIds) {
      final l = definition.links[id];
      b.write(',${l == null ? '$id' : (l.name ?? '')}');
    }
    b.write('\r\n');
    for (final e in entries) {
      b.write('${formatGeneral(e.timestamp)},');
      for (final v in e.values) {
        b.write('${formatGeneral(v)},');
      }
      b.write('\r\n');
    }
    return b.toString();
  }
}

class OnboardLogger {
  OnboardLogger(this.channel);
  final Channel channel;

  /// What the logger supports; null when the ECU has no onboard logging.
  Future<OnboardLogSupport?> support() async {
    final r = (await channel.request(isSupportedRequest())).reply;
    return r is DataLogSupportReply && r.ok ? OnboardLogSupport(r.maxFrequency, r.maxNumChans) : null;
  }

  Future<DataLogConfigReply> configuration() => _ask<DataLogConfigReply>(getConfigRequest(), DataLogCmd.getConfig);

  Future<void> configure(int frequency, List<int> channelIds, {bool switchActiveState = false}) =>
      _ask<Object>(setConfigRequest(frequency, switchActiveState, channelIds), DataLogCmd.setConfig);

  Future<void> start() => _ask<Object>(startRequest(), DataLogCmd.start);
  Future<void> stop() => _ask<Object>(stopRequest(), DataLogCmd.stop);

  /// Erases every log.
  Future<void> format() => _ask<Object>(formatMemoryRequest(), DataLogCmd.formatMemory);

  Future<List<LogInfo>> logs() async =>
      (await _ask<LogsSummaryReply>(getLogsSummaryRequest(), DataLogCmd.logsSummary)).logs;

  Future<void> erase(int id) => _ask<Object>(eraseLogRequest(id & 0xff), DataLogCmd.eraseLog);

  /// Downloads [log]; [onProgress] gets entries so far and the total.
  Future<OnboardLog> download(LogInfo log, {void Function(int done, int total)? onProgress}) async {
    final detail = await _ask<LogDetailReply>(getLogDetailRequest(log.id), DataLogCmd.logDetail);
    final entries = <LogEntry>[];
    final size = LogEntry.size(log.numOfChannels);
    onProgress?.call(0, log.numEntries);
    for (;;) {
      final left = log.numEntries - entries.length;
      final chunk = left < 512 ~/ size ? left : 512 ~/ size;
      if (chunk <= 0) break;
      final region = await _ask<LogRegionReply>(
        getLogRegionRequest(log.id, entries.length, chunk),
        DataLogCmd.logRegion,
      );
      entries.addAll(region.entries);
      onProgress?.call(entries.length, log.numEntries);
    }
    return OnboardLog(log, detail.chanIds, entries);
  }

  Future<T> _ask<T extends Object>(Frame f, int command) async {
    final r = (await channel.request(f)).reply;
    if (r == null) throw OnboardLogError(command);
    if (!r.ok) throw OnboardLogError(command, r.status);
    if (r case final T reply) return reply;
    throw OnboardLogError(command, r.status);
  }
}
