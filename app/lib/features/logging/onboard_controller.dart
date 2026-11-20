import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'strings.dart';

/// The ECU's own data logger, as the original's on-board logging tab ran it: support and configuration are read
/// when the page opens, the state comes from its live link, logs list newest last, and nothing changes on the ECU
/// while it is logging or a download is running.
class OnboardController extends ChangeNotifier {
  OnboardController(this._session, this._policy, this._saver) {
    _sub = _session.states.listen((_) {
      if (isOnline && support == null && !_asked) unawaited(refresh());
      notifyListeners();
    });
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final s = status;
      if (s != _lastStatus) {
        _lastStatus = s;
        notifyListeners();
      }
    });
    if (isOnline) unawaited(refresh());
  }

  final Session _session;
  final SwitchablePolicy _policy;
  final FileSaver _saver;
  late final StreamSubscription<SessionState> _sub;
  late final Timer _timer;
  int? _lastStatus;
  bool _asked = false;

  OnboardLogSupport? support;
  bool supported = true;
  int frequency = 0;
  bool switchActiveState = false;
  Set<int> channels = {};
  List<LogInfo> logs = const [];
  final selected = <int>{};
  bool downloading = false;
  int done = 0, total = 0;
  String? message;
  bool _cancel = false;

  OnboardLogger get _logger => OnboardLogger(_session.connection.channel);
  bool get isOnline => _session.state.phase == SessionPhase.online;
  bool get canChange => !_policy.readOnly;

  /// What the last start or stop left, for a definition without the status link.
  int? _local;

  /// Idle 1, logging 2, as the ECU reports on its status link. A definition without that link gets the state the
  /// last start or stop left, idle at first (docs/behaviour-changes.md).
  int? get status {
    final live = _session.live;
    if (live == null || !live.has(OnboardLogStatus.statusLink)) return support == null ? null : _local;
    return live.value(OnboardLogStatus.statusLink).round();
  }

  bool get isLogging => status == OnboardLogStatus.logging;

  int? get entries {
    final live = _session.live;
    if (live == null || !live.has(OnboardLogStatus.entriesLink)) return null;
    return live.value(OnboardLogStatus.entriesLink).round();
  }

  List<LinkDef> get links => [
    for (final l in _session.calibration?.definition.links.values ?? const <LinkDef>[])
      if (l.viewInTree) l,
  ];

  int get maxChannels => support?.maxChannels ?? 0;

  Future<void> refresh() async {
    _asked = true;
    message = null;
    try {
      support = await _logger.support();
      supported = support != null;
      if (supported) {
        _local ??= OnboardLogStatus.idle;
        final c = await _logger.configuration();
        frequency = c.freq;
        switchActiveState = c.switchActiveState;
        channels = c.loggedIds.toSet();
        logs = await _sorted();
      }
    } on OnboardLogError catch (e) {
      message = OnboardStrings.failed(e);
    }
    notifyListeners();
  }

  Future<List<LogInfo>> _sorted() async {
    int key(LogInfo l) {
      final t = l.timestamp;
      return (((t.year * 12 + t.month) * 31 + t.day) * 24 + t.hour) * 60 + t.minute;
    }

    return (await _logger.logs())..sort((a, b) => key(a).compareTo(key(b)));
  }

  void toggleChannel(int id, bool on) {
    on ? channels.add(id) : channels.remove(id);
    notifyListeners();
  }

  /// The original's quick selections: the definition's standard channels, or none.
  void selectStandard() {
    channels = {
      for (final l in links)
        if (l.standardLogging) l.id,
    };
    notifyListeners();
  }

  void selectNone() {
    channels = {};
    notifyListeners();
  }

  void setFrequency(int f) {
    frequency = f;
    notifyListeners();
  }

  bool get configValid => channels.isNotEmpty && channels.length <= maxChannels && frequency > 0;

  Future<void> _run(Future<void> Function() f, {String? done}) async {
    message = null;
    try {
      await f();
      message = done;
    } on OnboardLogError catch (e) {
      message = OnboardStrings.failed(e);
    }
    notifyListeners();
  }

  Future<void> saveConfiguration() async {
    if (!configValid) {
      message = OnboardStrings.invalid;
      notifyListeners();
      return;
    }
    final ids = [
      for (final l in links)
        if (channels.contains(l.id)) l.id,
    ];
    await _run(
      () => _logger.configure(frequency, ids, switchActiveState: switchActiveState),
      done: OnboardStrings.saved,
    );
  }

  Future<void> toggleLogging() async {
    if (downloading) {
      message = OnboardStrings.cannotStart;
      notifyListeners();
      return;
    }
    final stop = isLogging;
    await _run(() async {
      await (stop ? _logger.stop() : _logger.start());
      _local = stop ? OnboardLogStatus.idle : OnboardLogStatus.logging;
    });
  }

  Future<void> eraseSelected() async {
    if (isLogging) {
      message = OnboardStrings.cannotErase;
      notifyListeners();
      return;
    }
    await _run(() async {
      for (final id in selected) {
        await _logger.erase(id);
      }
      selected.clear();
      logs = await _sorted();
    });
  }

  Future<void> format() async {
    if (isLogging) {
      message = OnboardStrings.cannotFormat;
      notifyListeners();
      return;
    }
    await _run(() async {
      await _logger.format();
      selected.clear();
      logs = await _sorted();
    });
  }

  void select(int id, bool on) {
    on ? selected.add(id) : selected.remove(id);
    notifyListeners();
  }

  /// Downloads each selected log and saves it as the original named it.
  Future<void> download() async {
    if (downloading) {
      _cancel = true;
      return;
    }
    if (isLogging) {
      message = OnboardStrings.cannotDownload;
      notifyListeners();
      return;
    }
    final def = _session.calibration?.definition;
    if (def == null) return;
    downloading = true;
    _cancel = false;
    message = null;
    notifyListeners();
    try {
      for (final l in logs.where((l) => selected.contains(l.id))) {
        if (_cancel) break;
        final log = await _logger.download(
          l,
          onProgress: (d, t) {
            done = d;
            total = t;
            notifyListeners();
          },
        );
        await _saver.save(OnboardStrings.fileName(l), Uint8List.fromList(utf8.encode(log.toCsv(def))));
      }
      message = _cancel ? null : OnboardStrings.complete;
    } on OnboardLogError catch (e) {
      message = OnboardStrings.failed(e);
    }
    downloading = false;
    done = total = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer.cancel();
    unawaited(_sub.cancel());
    super.dispose();
  }
}
