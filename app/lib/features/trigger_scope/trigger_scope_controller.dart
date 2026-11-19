import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'strings.dart';

/// The trigger logger as the original ran it: starting clears the log, turns live reporting and the link's
/// silence watchdog off, and asks for the chosen channels; stopping undoes that. Reports become the trace.
class TriggerScopeController extends ChangeNotifier {
  TriggerScopeController(this._session, this._saver) {
    _sub = _session.connection.channel.received.listen(_onReceived);
    _states = _session.states.listen((_) {
      if (isOnline && available == null) unawaited(_ask());
      notifyListeners();
    });
    if (isOnline) unawaited(_ask());
  }

  final Session _session;
  final FileSaver _saver;
  late final StreamSubscription<Received> _sub;
  late final StreamSubscription<SessionState> _states;
  final log = TriggerLog();

  /// The channels the ECU offers; null until it answers.
  List<int>? available;
  bool running = false;
  bool follow = true;
  String? message;
  double start = 0, end = 0.1;
  (double, double)? selection;
  Timer? _repaint;
  bool _dirty = false;

  bool get isOnline => _session.state.phase == SessionPhase.online;

  Future<void> _ask() async {
    available = const [];
    final r = await _session.connection.channel.request(triggerIsSupportedRequest());
    if (r.reply case final TriggerSupportReply s when s.ok) available = s.availableChannelIds;
    notifyListeners();
  }

  void _onReceived(Received r) {
    switch (r.reply) {
      case final TriggerReportReply report when running:
        log.addReport(report.entries);
        _dirty = true;
      case final TriggerStateReply state:
        log.applyState(state);
    }
  }

  void setChannel(int id, bool on) {
    log.enabled[id] = on;
    notifyListeners();
  }

  Future<void> startLog() async {
    if (!isOnline || running) return;
    log.clear();
    selection = null;
    running = true;
    follow = true;
    _session.connection.pauseWatchdog();
    await _session.pauseReporting();
    await _session.connection.channel.request(triggerSetStateRequest(true, log.enabledChannels));
    _repaint = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_dirty) return;
      _dirty = false;
      if (follow) _followLatest();
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> stopLog() async {
    if (!running) return;
    running = false;
    _repaint?.cancel();
    await _session.connection.channel.request(triggerSetStateRequest(false, const []));
    await _session.resumeReporting();
    _session.connection.resumeWatchdog();
    notifyListeners();
  }

  void _followLatest() {
    final pts = log.points;
    if (pts.isEmpty) return;
    final width = end - start;
    end = pts.last.timestamp;
    start = end - width;
  }

  void fit() {
    final pts = log.points;
    if (pts.isEmpty) return;
    start = pts.first.timestamp;
    end = math.max(pts.last.timestamp, start + 1e-3);
    follow = false;
    notifyListeners();
  }

  void setWindow(double a, double b) {
    if (b - a < 1e-5) return;
    start = a;
    end = b;
    follow = false;
    notifyListeners();
  }

  void setFollow(bool v) {
    follow = v;
    if (v) _followLatest();
    notifyListeners();
  }

  void select((double, double)? span) {
    selection = span;
    notifyListeners();
  }

  /// Rising and falling edges of each shown channel within the selection.
  List<String> get measures {
    final s = selection;
    if (s == null || s.$2 <= s.$1) return const [];
    return [
      TriggerScopeStrings.span((s.$2 - s.$1) * 1000),
      for (final id in log.enabledChannels)
        if (edgesBetween(log.points, id, s.$1, s.$2) case final e)
          TriggerScopeStrings.edges(TriggerScopeStrings.channels[id], e.rising, e.falling),
    ];
  }

  Future<void> save({bool span = false}) async {
    final s = selection;
    final text = span && s != null ? log.toText(from: s.$1, to: s.$2) : log.toText();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'Trigger_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.metlg';
    await _saver.save(name, Uint8List.fromList(utf8.encode(text)));
  }

  void open(String text) {
    try {
      log.readText(text);
      message = null;
      fit();
    } on FormatException catch (e) {
      message = TriggerScopeStrings.unreadable(e.message);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stopLog());
    unawaited(_sub.cancel());
    unawaited(_states.cancel());
    _repaint?.cancel();
    super.dispose();
  }
}
