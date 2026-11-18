import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

/// Runs the bench checklist over the session and keeps what the link blocked and sent meanwhile.
class BenchController extends ChangeNotifier {
  BenchController(this._session);

  final Session _session;
  final results = <BenchResult>[];
  final _blocked = <(DateTime, Frame)>[];
  final _sent = <String, int>{};
  DateTime? _started;
  bool running = false;

  bool get isOnline => _session.state.phase == SessionPhase.online;

  Future<void> run() async {
    if (running) return;
    final channel = _session.connection.channel;
    running = true;
    results.clear();
    _blocked.clear();
    _sent.clear();
    _started = DateTime.now();
    notifyListeners();
    channel.onBlocked = (f) => _blocked.add((DateTime.now(), f));
    channel.onSent = (f) => _sent.update(frameName(f), (n) => n + 1, ifAbsent: () => 1);
    try {
      await runBenchChecks(
        _session,
        onResult: (r) {
          results.add(r);
          notifyListeners();
        },
      );
    } finally {
      channel
        ..onBlocked = null
        ..onSent = null;
      running = false;
      notifyListeners();
    }
  }

  String? get report => _started == null || running
      ? null
      : benchReportText(started: _started!, results: results, blocked: _blocked, sent: _sent);
}
