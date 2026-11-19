import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../instruments/log_plot.dart';

/// Recording live data to CSV, and reviewing a CSV log.
class LoggingController extends ChangeNotifier {
  LoggingController(this._session, this._saver) {
    _session.states.listen((_) => notifyListeners());
  }

  final Session _session;
  final FileSaver _saver;

  PcLogRecorder? _recorder;
  final _text = StringBuffer();
  int lines = 0;
  DateTime? _started, _stopped;

  bool get isOnline => _session.state.phase == SessionPhase.online && _session.live != null;
  bool get isRecording => _recorder?.isRecording ?? false;
  bool get hasRecording => lines > 0 && !isRecording;
  double get seconds => _started == null ? 0 : (_stopped ?? DateTime.now()).difference(_started!).inMilliseconds / 1000;

  void start() {
    final cal = _session.calibration, live = _session.live;
    if (cal == null || live == null || isRecording) return;
    _text.clear();
    lines = 0;
    _started = DateTime.now();
    _stopped = null;
    _recorder = PcLogRecorder(
      live: live,
      channels: pcLogChannels(cal.definition, const []),
      write: (t) {
        _text.write(t);
        lines++;
        if (lines % 10 == 0) notifyListeners();
      },
    )..start();
    notifyListeners();
  }

  void mark() => _recorder?.mark();

  void stop() {
    _recorder?.stop();
    _stopped = DateTime.now();
    lines = lines > 0 ? lines - 1 : 0; // the header
    notifyListeners();
  }

  Future<void> save() async {
    final t = _started ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'Log_${t.year}_${two(t.month)}_${two(t.day)}_${two(t.hour)}_${two(t.minute)}_${two(t.second)}.csv';
    await _saver.save(name, Uint8List.fromList(utf8.encode(_text.toString())));
  }

  // ---------------------------------------------------------------- review

  LogSession? log;
  final selected = <int>{};

  void openLog(String name, String text) {
    log = csvLogSession(name, text);
    selected
      ..clear()
      ..addAll(
        [
          for (final (i, c) in log!.channels.indexed)
            if (!c.isMarker) i,
        ].take(4),
      );
    notifyListeners();
  }

  void toggle(int channel) {
    selected.contains(channel) ? selected.remove(channel) : selected.add(channel);
    notifyListeners();
  }

  /// The selected channels reduced to about one point per pixel of [width], spikes kept.
  List<LogLane> lanes(double width) {
    final s = log;
    if (s == null) return const [];
    final times = s.samples.times;
    final out = math.max(4, width.round());
    return [
      for (final i in selected.toList()..sort())
        if (i < s.samples.values.length)
          () {
            final values = s.samples.values[i];
            final keep = times.length <= out * 2
                ? [for (var k = 0; k < times.length; k++) k]
                : minMaxLttb(times, values, out);
            return (
              label: s.channels[i].displayName,
              times: [for (final k in keep) times[k]],
              values: [for (final k in keep) values[k]],
            );
          }(),
    ];
  }
}
