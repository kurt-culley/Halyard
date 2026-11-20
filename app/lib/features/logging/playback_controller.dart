import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'strings.dart';

/// The original's playback strip: a track of 0.1 s steps back from the newest report (0 is the newest), stepping,
/// playing forward ten steps a second, going live, and loading or saving a recording. Everything that shows live
/// data follows the store, so pages show the moment chosen here.
class PlaybackController extends ChangeNotifier {
  PlaybackController(this._session, this._saver) {
    _sub = _session.states.listen((_) => notifyListeners());
  }

  final Session _session;
  final FileSaver _saver;
  late final StreamSubscription<SessionState> _sub;

  static const maximum = 1199, smallChange = 1, largeChange = 10;

  int seekIndex = 0;
  bool live = true;
  bool playing = false;
  String? message;

  /// The original asked after five seconds away from live whether to go back; "Don't show this again" turns it off.
  bool askToGoLive = true;
  void Function()? onAskLive;
  Timer? _play, _warning;

  LiveStore? get _store => _session.live;
  bool get isOnline => _session.state.phase == SessionPhase.online && _store != null;

  void _leaveLive() {
    if (live) {
      live = false;
      if (askToGoLive) {
        _warning?.cancel();
        _warning = Timer(const Duration(seconds: 5), () => onAskLive?.call());
      }
    }
  }

  /// Moves the track; a step with no history there keeps the old one.
  void seek(int v) {
    final s = _store;
    if (s == null) return;
    v = v.clamp(0, maximum);
    if (v != 0 && !s.canSeekBack(v)) {
      _leaveLive();
      notifyListeners();
      return;
    }
    seekIndex = v;
    s.seekBack(v);
    _leaveLive();
    notifyListeners();
  }

  void step(int by) => seek(seekIndex + by);

  void pause() {
    _stopTimer();
    _store?.pause();
    _leaveLive();
    notifyListeners();
  }

  void play() {
    _store?.pause();
    _leaveLive();
    playing = true;
    _play?.cancel();
    _tick();
    _play = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    notifyListeners();
  }

  void _tick() {
    if (live || seekIndex <= 0) {
      _stopTimer();
      notifyListeners();
      return;
    }
    seek(seekIndex - 1);
  }

  void _stopTimer() {
    _play?.cancel();
    _play = null;
    playing = false;
  }

  void goLive() {
    _stopTimer();
    _warning?.cancel();
    seekIndex = 0;
    _store?.seekBack(0);
    _store?.resume();
    live = true;
    notifyListeners();
  }

  /// Loads a recording in place of the history and pauses on its newest line.
  void load(String text) {
    final s = _store;
    if (s == null) return;
    try {
      final r = readLiveRecording(text);
      s.loadRecording(r);
      message = r.complete ? null : PlaybackStrings.partly;
      _stopTimer();
      seekIndex = 0;
      _leaveLive();
    } on FormatException catch (e) {
      message = PlaybackStrings.unreadable(e.message);
    }
    notifyListeners();
  }

  /// Saves the history shown as a recording, in the format the strip loads.
  Future<void> save() async {
    final s = _store, def = _session.calibration?.definition;
    if (s == null || def == null || s.ids.isEmpty) return;
    final out = StringBuffer();
    String? name;
    final w = LiveRecordingWriter(maxLines: 1 << 30)
      ..useDefinition(def)
      ..setFolder((n) {
        name = n;
        return _Collect(out);
      });
    final n = s.length(s.ids.first);
    for (var k = 0; k < n; k++) {
      final at = s.sample(s.ids.first, k).$1;
      w.addReport(DateTime.fromMillisecondsSinceEpoch(at.round()), [
        for (final id in def.links.keys) s.has(id) && k < s.length(id) ? s.sample(id, k).$2 : double.nan,
      ]);
    }
    w.closeFile();
    if (name != null) await _saver.save(name!, Uint8List.fromList(utf8.encode(out.toString())));
  }

  @override
  void dispose() {
    _play?.cancel();
    _warning?.cancel();
    unawaited(_sub.cancel());
    super.dispose();
  }
}

final class _Collect implements TextFileSink {
  _Collect(this.out);
  final StringBuffer out;
  @override
  void write(String text) => out.write(text);
  @override
  void close() {}
}
