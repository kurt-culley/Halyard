/// The read-only bench test (B01 to B03, Halyard's own, not the original's): a checklist of reads against a real
/// ECU through a session whose connection only lets reads through ([ReadOnlyPolicy]), and a plain-text report of
/// what passed, what was blocked and what was sent. It answers the open bench questions before anything is written.
library;

import '../wire/framing.dart';
import '../wire/messages/datalog.dart';
import '../wire/messages/drivers.dart';
import '../wire/messages/faults.dart';
import '../wire/messages/sys.dart';
import '../wire/messages/tables.dart';
import '../wire/messages/trigger.dart';
import '../wire/reply.dart';
import 'session.dart';

enum BenchCheck {
  ecuInfo('ECU information (GetECUInfo)'),
  definition('Definition and calibration read'),
  table('Read one table back (GetTable)'),
  driver('Read one driver back (GetDriver)'),
  hash('Calibration hash (GetHash)'),
  live('Live data'),
  password('Password protection state (PWLockGetState)'),
  canIds('CAN reserved ids (GetCanReservedIds)'),
  onboardLog('On-board logging (IsSupported, GetConfig, GetLogsSummary)'),
  faults('Fault log (GetInfo, GetSummary)'),
  trigger('Trigger scope support (IsSupported)');

  const BenchCheck(this.title);
  final String title;
}

enum BenchStatus { pass, fail, skip }

final class BenchResult {
  const BenchResult(this.check, this.status, this.details, this.took);
  final BenchCheck check;
  final BenchStatus status;

  /// What was found, in order; a failure or skip says why under `reason`.
  final Map<String, Object?> details;
  final Duration took;
}

/// Runs the checklist in order over [session], which must be online; a failure doesn't stop the later checks.
Future<List<BenchResult>> runBenchChecks(
  Session session, {
  Duration liveWindow = const Duration(seconds: 3),
  void Function(BenchResult)? onResult,
  DateTime Function()? now,
}) async {
  final clock = now ?? DateTime.now;
  final channel = session.connection.channel;
  final out = <BenchResult>[];
  Future<void> check(BenchCheck c, Future<(BenchStatus, Map<String, Object?>)> Function() run) async {
    final t0 = clock();
    (BenchStatus, Map<String, Object?>) r;
    try {
      r = await run();
    } on Object catch (e) {
      r = (BenchStatus.fail, {'reason': 'error: $e'});
    }
    final res = BenchResult(c, r.$1, r.$2, clock().difference(t0));
    out.add(res);
    onResult?.call(res);
  }

  Future<Reply?> ask(Frame f) async {
    final r = await channel.request(f);
    return r.ok ? r.reply : null;
  }

  (BenchStatus, Map<String, Object?>) fail(String why) => (BenchStatus.fail, {'reason': why});
  (BenchStatus, Map<String, Object?>) skip(String why) => (BenchStatus.skip, {'reason': why});
  const pass = BenchStatus.pass;

  await check(BenchCheck.ecuInfo, () async {
    final r = await ask(getEcuInfoRequest());
    if (r is! EcuInfoReply) return fail('no successful reply');
    return (
      pass,
      {
        'product': r.productName,
        'model': r.modelName,
        'def': r.version,
        'fw': r.fwVersion,
        'uuid': r.uuid ?? '',
        'hash': r.hash ?? 'none',
        'pw': r.passwordProtection,
      },
    );
  });
  final cal = session.calibration;
  await check(BenchCheck.definition, () async {
    if (cal == null) return fail('no calibration: the definition for this ECU is missing or the read did not finish');
    final i = cal.definition.info;
    return (
      pass,
      {
        'product': i.productName,
        'model': i.modelName,
        'def': i.version,
        'fw': i.fwVersion,
        'tables': cal.definition.tables.length,
        'drivers': cal.definition.drivers.length,
        'links': cal.definition.links.length,
      },
    );
  });
  await check(BenchCheck.table, () async {
    final ids = cal?.definition.tables.keys ?? const <int>[];
    if (ids.isEmpty) return skip('no tables');
    final r = await channel.request(getTableRequest(ids.first));
    return r.ok ? (pass, {'table': ids.first}) : fail('table ${ids.first}: no successful reply');
  });
  await check(BenchCheck.driver, () async {
    final ids = cal?.definition.drivers.keys ?? const <int>[];
    if (ids.isEmpty) return skip('no drivers');
    final r = await channel.request(getDriverRequest(ids.first));
    return r.ok ? (pass, {'driver': ids.first}) : fail('driver ${ids.first}: no successful reply');
  });
  await check(BenchCheck.hash, () async {
    final r = await ask(getHashRequest(0));
    if (r is! HashReply) return fail('no successful reply');
    return (pass, {'mode': r.mode, 'overall': r.overall});
  });
  await check(BenchCheck.live, () async {
    final live = session.live;
    if (live == null) return fail('no live data store');
    final v0 = live.version;
    final before = [for (final id in live.ids) live.value(id)];
    await Future<void>.delayed(liveWindow);
    final frames = live.version - v0;
    if (frames == 0) return fail('no live-data frames received');
    var changed = 0;
    for (final (i, id) in live.ids.indexed) {
      final v = live.value(id);
      if (!(v == before[i] || (v.isNaN && before[i].isNaN))) changed++;
    }
    final perSecond = frames * 1000 / liveWindow.inMilliseconds;
    return (
      pass,
      {'frames': frames, 'perSecond': perSecond.round(), 'linksChanged': changed, 'links': live.ids.length},
    );
  });
  await check(BenchCheck.password, () async {
    final r = await ask(pwLockGetStateRequest());
    if (r is! PwLockReply) return fail('no successful reply (older firmware may not answer)');
    return (pass, {'locked': r.locked, 'temporary': r.temporary, 'contact': r.tunerContact ?? ''});
  });
  await check(BenchCheck.canIds, () async {
    final r = await ask(getCanReservedIdsRequest());
    if (r is! CanReservedIdsReply) return skip('not answered (custom CAN may not be supported)');
    return (pass, {'reservedIds': r.reservedIds.length});
  });
  await check(BenchCheck.onboardLog, () async {
    final s = await ask(isSupportedRequest());
    if (s is! DataLogSupportReply) return skip('on-board logging not supported');
    final c = await ask(getConfigRequest());
    final l = await ask(getLogsSummaryRequest());
    return (
      pass,
      {
        'maxFrequency': s.maxFrequency,
        'maxChannels': s.maxNumChans,
        'config': c is DataLogConfigReply ? 'read' : 'none',
        'logs': l is LogsSummaryReply ? l.logs.length : 'none',
      },
    );
  });
  await check(BenchCheck.faults, () async {
    final i = await ask(faultsGetInfoRequest());
    final info = i is FaultInfoReply ? i.info : null;
    if (info == null) return skip('fault log not supported');
    final s =
        info.numSummary > 0 ? await ask(faultsGetSummaryRequest(0, info.numSummary < 40 ? info.numSummary : 40)) : null;
    return (
      pass,
      {
        'codes': info.numCodes,
        'logUsed': info.logUsed,
        'capacity': info.logCapacity,
        'summaries': info.numSummary,
        'read': s is FaultPageReply ? s.entries.length : 0,
      },
    );
  });
  await check(BenchCheck.trigger, () async {
    final r = await ask(triggerIsSupportedRequest());
    if (r is! TriggerSupportReply) return skip('not supported');
    return (pass, {'channels': r.availableChannelIds.join(',')});
  });
  return out;
}

const _frameNames = {
  (0, 0): 'Reporting.SendReport',
  (0, 1): 'Reporting.Ack (lifesign)',
  (0, 2): 'Reporting.SetState',
  (0, 3): 'Reporting.SetSpecialCfg',
  (1, 0): 'Tables.SetTable',
  (1, 1): 'Tables.GetTable',
  (1, 2): 'Tables.Enable',
  (1, 3): 'Tables.Disable',
  (1, 4): 'Tables.SetTableData',
  (1, 6): 'Tables.Store',
  (1, 7): 'Tables.SetReporting',
  (2, 0): 'Drivers.SetDriver',
  (2, 1): 'Drivers.GetDriver',
  (2, 2): 'Drivers.Store',
  (2, 3): 'Drivers.GetCanReservedIds',
  (4, 0): 'Sys.GetECUInfo',
  (4, 1): 'Sys.GetHash',
  (4, 2): 'Sys.SetRTC',
  (4, 3): 'Sys.FactoryReset',
  (4, 4): 'Sys.PWLockSetState',
  (4, 5): 'Sys.PWLockGetState',
  (4, 6): 'Sys.RaceUnlock',
  (5, 0): 'Firmware.Start',
  (5, 1): 'Firmware.RegionInfo',
  (5, 2): 'Firmware.RegionData',
  (5, 3): 'Firmware.Done',
  (5, 4): 'Firmware.EnterBootloader',
  (6, 0): 'DataLog.IsSupported',
  (6, 1): 'DataLog.GetConfig',
  (6, 2): 'DataLog.SetConfig',
  (6, 3): 'DataLog.Start',
  (6, 4): 'DataLog.Stop',
  (6, 5): 'DataLog.GetLogsSummary',
  (6, 6): 'DataLog.GetLogDetail',
  (6, 7): 'DataLog.GetLogRegion',
  (6, 8): 'DataLog.EraseLog',
  (6, 9): 'DataLog.FormatMemory',
  (7, 0): 'Trigger.IsSupported',
  (7, 1): 'Trigger.SetState',
  (8, 0): 'DBW.SetDuty',
  (9, 0): 'Faults.GetInfo',
  (9, 1): 'Faults.GetFrameLayout',
  (9, 2): 'Faults.GetSummary',
  (9, 3): 'Faults.GetOccurrence',
  (9, 4): 'Faults.Clear',
  (9, 5): 'Faults.EraseLog',
};

/// A frame's name for the report.
String frameName(Frame f) =>
    _frameNames[(f.cls, f.cmd)] ?? '${f.type == MsgType.req ? 'Request' : 'Frame'} ${f.cls}/${f.cmd}';

String _detailText(Map<String, Object?> d) => d.entries.map((e) => '${e.key}=${e.value}').join(' ');

/// The plain-text report: each check, the writes the policy blocked (with times) and the requests sent by name.
String benchReportText({
  required DateTime started,
  required List<BenchResult> results,
  List<(DateTime, Frame)> blocked = const [],
  Map<String, int> sent = const {},
}) {
  const mark = {BenchStatus.pass: 'PASS', BenchStatus.fail: 'FAIL', BenchStatus.skip: 'SKIP'};
  final lines = ['Halyard read-only bench test - ${started.toIso8601String()}', ''];
  for (final r in results) {
    lines
      ..add('${mark[r.status]}  ${r.check.title} (${r.took.inMilliseconds} ms)')
      ..add('      ${_detailText(r.details)}');
  }
  lines
    ..add('')
    ..add(blocked.isEmpty ? 'Blocked writes: none' : 'Blocked writes (${blocked.length}):');
  for (final (t, f) in blocked) {
    lines.add('  ${t.toIso8601String()}  ${frameName(f)} (${f.cls}/${f.cmd})');
  }
  final counts = sent.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  lines
    ..add('')
    ..add('Requests sent:')
    ..addAll(counts.map((e) => '  ${e.key}: ${e.value}'));
  return lines.join('\n');
}
