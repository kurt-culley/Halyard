import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'strings.dart';

typedef FaultRow = ({
  int code,
  String name,
  String severity,
  String state,
  bool active,
  int count,
  int lifetime,
  String last,
});
typedef RecordRow = ({String type, String code, String when});

/// Reads the fault log through the session's channel. Clearing waits for the write gate.
class FaultsController extends ChangeNotifier {
  FaultsController(this._session);

  final Session _session;
  final _log = FaultLog();
  bool busy = false;
  bool? hasLog;
  String? error;

  bool get isOnline => _session.state.phase == SessionPhase.online;
  FaultLogInfo? get info => _log.info;

  List<FaultRow> get codes => [
    for (final s in _log.summary)
      if (s.count > 0 || s.lifetime > 0 || FaultState.isActive(s.state))
        (
          code: s.code,
          name: faultCode(s.code).name,
          severity: _pick(FaultsStrings.severities, s.severity),
          state: _pick(FaultsStrings.states, s.state),
          active: FaultState.isActive(s.state),
          count: s.count,
          lifetime: s.lifetime,
          last: _when(s.lastHoursX100, s.lastRtc),
        ),
  ];

  List<RecordRow> get records => [
    for (final r in _log.records)
      if (r.isValid)
        (
          type: FaultsStrings.recordTypes[r.type] ?? '${r.type}',
          code: r.code == 0 ? '' : '${r.code} ${faultCode(r.code).name}',
          when: _when(r.hoursX100, r.rtc),
        ),
  ];

  static String _pick(List<String> names, int i) => i >= 0 && i < names.length ? names[i] : '$i';

  static String _when(int hoursX100, int rtc) {
    final t = faultRtc(rtc);
    final h = FaultsStrings.hours(faultHours(hoursX100));
    return t == null ? h : '$h  ·  ${t.toIso8601String().substring(0, 16).replaceFirst('T', ' ')}';
  }

  Future<void> read({bool history = false}) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    final reader = FaultLogReader(_session.connection.channel);
    try {
      hasLog = await reader.fetch(_log);
      if (hasLog! && history) await reader.fetchHistory(_log, onRecord: (_) => notifyListeners());
    } on FaultLogError catch (e) {
      error = FaultsStrings.failed(e.failure.name);
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
