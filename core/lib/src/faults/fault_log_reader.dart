/// Reading and clearing the ECU's fault log (U13-M06 to M08): info, freeze-frame layout and code summary in pages,
/// then the history one record at a time. Failures are [FaultLogError]s; the app words them.
library;

import 'dart:async';

import '../link/channel.dart';
import '../wire/framing.dart' show Frame;
import '../wire/messages/faults.dart';
import 'fault_codes.dart';
import 'fault_records.dart';

/// What the ECU's fault log holds, as far as it has been read.
final class FaultLog {
  FaultLogInfo? info;
  List<FrameChannel> layout = [];
  List<FaultSummaryEntry> summary = [];
  List<FaultLogRecord> records = [];
  bool historyComplete = false;

  /// Codes that have occurred since the counters were last cleared.
  int get codesWithCount => summary.where((s) => s.count > 0).length;

  /// The freeze frame of an occurrence record; empty for other records.
  List<(int, double)> frameOf(FaultLogRecord r) =>
      r.type == FaultRecordType.occurrence ? decodeFreezeFrame(layout, r.body) : const [];

  /// Gives the layout the value types of the live-data layout (link id to type); links it doesn't list keep theirs.
  void applyReportingTypes(Map<int, int> types) {
    layout = [for (final c in layout) FrameChannel(c.linkId, c.size, types[c.linkId] ?? c.type)];
  }
}

enum FaultLogFailure {
  /// A request after the first went unanswered.
  noAnswer,
  getInfo,
  getFrameLayout,
  getSummary,
  getOccurrence,

  /// Clearing was refused, or the ECU stayed busy writing the log.
  clearRefused,
  clearBusy,
  eraseRefused,

  /// Erasing needs the engine stopped.
  engineRunning,
}

class FaultLogError implements Exception {
  const FaultLogError(this.failure, [this.status]);
  final FaultLogFailure failure;

  /// The ECU's reply status, where there was a reply.
  final int? status;
  @override
  String toString() => 'FaultLogError($failure${status == null ? '' : ', status $status'})';
}

class FaultLogReader {
  FaultLogReader(this.channel, {this.clearRetryDelay = const Duration(milliseconds: 100)});
  final Channel channel;
  final Duration clearRetryDelay;

  /// Reads info, layout and summary into [log]. False when the ECU doesn't answer at all: it has no fault log.
  Future<bool> fetch(FaultLog log) async {
    final info = await _send<FaultInfoReply>(faultsGetInfoRequest(), failure: null);
    if (info == null) return false;
    if (!info.ok || info.info == null) throw FaultLogError(FaultLogFailure.getInfo, info.status);
    final layout = <FrameChannel>[];
    final summary = <FaultSummaryEntry>[];
    await _pages<FaultFrameLayoutEntry>(
      (start) => faultsGetFrameLayoutRequest(start, 200),
      FaultLogFailure.getFrameLayout,
      (e) => layout.add(FrameChannel(e.linkId, e.size)),
    );
    await _pages<FaultSummaryEntry>(
      (start) => faultsGetSummaryRequest(start, 40),
      FaultLogFailure.getSummary,
      summary.add,
    );
    log
      ..info = info.info
      ..layout = layout
      ..summary = summary;
    return true;
  }

  /// Reads the whole history, newest first, until the ECU says there is no more.
  Future<void> fetchHistory(FaultLog log, {void Function(FaultLogRecord r)? onRecord}) async {
    log
      ..records = []
      ..historyComplete = false;
    final cap = log.info?.logCapacity ?? 0;
    final max = cap * 4 > 4096 ? cap * 4 : 4096;
    for (var i = 0; i < max; i++) {
      final r = await _send<FaultOccurrenceReply>(faultsGetOccurrenceRequest(i & 0xffff));
      if (r!.isEndOfHistory) break;
      final rec = r.record;
      if (!r.ok || rec == null) throw FaultLogError(FaultLogFailure.getOccurrence, r.status);
      log.records.add(rec);
      onRecord?.call(rec);
    }
    log.historyComplete = true;
  }

  /// Clears the counters, asking up to five times while the ECU is busy, then reads the log again (and its history
  /// when it had been read).
  Future<void> clear(FaultLog log) async {
    FaultActionReply? r;
    for (var i = 0; i < 5; i++) {
      r = await _send<FaultActionReply>(faultsClearRequest());
      if (!r!.refused) break;
      await Future<void>.delayed(clearRetryDelay);
    }
    if (!r!.ok) throw FaultLogError(r.refused ? FaultLogFailure.clearBusy : FaultLogFailure.clearRefused, r.status);
    await _refetch(log);
  }

  /// Erases the log (the ECU refuses while the engine runs), then reads it again.
  Future<void> erase(FaultLog log) async {
    final r = await _send<FaultActionReply>(faultsEraseLogRequest());
    if (!r!.ok) throw FaultLogError(r.refused ? FaultLogFailure.engineRunning : FaultLogFailure.eraseRefused, r.status);
    log
      ..records = []
      ..historyComplete = false;
    await fetch(log);
  }

  Future<void> _refetch(FaultLog log) async {
    final history = log.records.isNotEmpty || log.historyComplete;
    if (await fetch(log) && history) await fetchHistory(log);
  }

  Future<void> _pages<T>(Frame Function(int start) request, FaultLogFailure failure, void Function(T) add) async {
    var start = 0;
    for (;;) {
      final r = await _send<FaultPageReply<T>>(request(start));
      if (!r!.ok) throw FaultLogError(failure, r.status);
      r.entries.forEach(add);
      start = (start + r.count) & 0xffff;
      if (r.count == 0 || start >= r.total) break;
    }
  }

  /// The reply, or null when there was none and [failure] is null; otherwise no reply throws [failure].
  Future<T?> _send<T extends Object>(Frame f, {FaultLogFailure? failure = FaultLogFailure.noAnswer}) async {
    final r = (await channel.request(f)).reply;
    if (r case final T reply) return reply;
    if (failure == null) return null;
    throw FaultLogError(failure);
  }
}
