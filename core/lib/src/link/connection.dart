/// Keeps a link to the ECU up: opens the transport, confirms an ECU answers, watches for silence and reconnects.
library;

import 'dart:async';

import '../wire/messages/sys.dart';
import 'channel.dart';
import 'transport.dart';

enum LinkPhase {
  /// Not connected and not trying.
  closed,

  /// Opening the port and asking the ECU who it is.
  opening,

  /// Frames are arriving.
  connected,

  /// Waiting to try again after a drop or a failed attempt.
  reconnecting,
}

final class LinkState {
  const LinkState(this.phase, {this.attempt = 0, this.baudRate});
  final LinkPhase phase;

  /// Reconnecting only: consecutive attempt number.
  final int attempt;
  final int? baudRate;

  @override
  bool operator ==(Object other) =>
      other is LinkState && other.phase == phase && other.attempt == attempt && other.baudRate == baudRate;
  @override
  int get hashCode => Object.hash(phase, attempt, baudRate);
  @override
  String toString() => 'LinkState($phase, attempt $attempt, ${baudRate ?? '-'} baud)';
}

enum _End { dropped, failed }

/// Connection lifecycle for one port.
///
/// The ECU is first tried at 230400 baud. If it doesn't answer and has never answered on this port, 115200 is tried
/// once. After a successful connection the working rate is kept. The connection drops when no recognised frame
/// arrives for a whole watchdog period (live data keeps it alive; the trigger scope pauses the watchdog while it holds
/// reporting off), and reconnects until [LinkTiming.maxAttempts] consecutive attempts have failed.
class Connection {
  Connection(this._open, {this.timing = LinkTiming.cable, FramePolicy? policy})
    : channel = Channel(timing: timing, policy: policy) {
    channel
      ..onAnyFrame = (_) {
        _everConnected = true;
        _goodBaud = _baud;
        _set(LinkState(LinkPhase.connected, baudRate: _baud));
      }
      ..onLost = _endRun;
  }

  static const defaultBaud = 230400;
  static int nextBaud(int b) => b == 230400 ? 115200 : 230400;

  final TransportOpener _open;
  final LinkTiming timing;
  final Channel channel;

  final _states = StreamController<LinkState>.broadcast(sync: true);
  var _state = const LinkState(LinkPhase.closed);
  LinkState get state => _state;
  Stream<LinkState> get states => _states.stream;

  var _wanted = false;
  Future<void>? _loop;
  Completer<void>? _run;
  Completer<void>? _wake;
  Transport? _transport;
  var _attempts = 0;
  var _everConnected = false;
  var _baud = defaultBaud;
  var _goodBaud = defaultBaud;
  Timer? _watchdog;
  var _watchLast = 0;

  /// Starts connecting; does nothing when already connecting or connected.
  void connect() {
    _wanted = true;
    _loop ??= _runLoop().whenComplete(() => _loop = null);
  }

  /// Stops reconnecting and closes the port. Completes when the port is closed.
  Future<void> disconnect() async {
    _wanted = false;
    _wake?.complete();
    _wake = null;
    _endRun();
    await _loop;
  }

  /// The trigger scope holds reporting off; silence is expected until [resumeWatchdog].
  void pauseWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  void resumeWatchdog() {
    if (_run != null) _armWatchdog();
  }

  void _set(LinkState s) {
    if (s == _state) return;
    _state = s;
    _states.add(s);
  }

  Future<void> _runLoop() async {
    var delay = Duration.zero;
    for (;;) {
      final attempt = ++_attempts;
      if (delay > Duration.zero) {
        _set(LinkState(LinkPhase.reconnecting, attempt: attempt));
        await _sleep(delay);
        if (!_wanted) break;
      }
      final end = await _runOnce();
      await _close();
      delay = end == _End.dropped ? timing.cancelDelay : timing.errorDelay;
      if (!(attempt < timing.maxAttempts && _wanted)) break;
    }
    _attempts = 0;
    _set(const LinkState(LinkPhase.closed));
  }

  Future<void> _sleep(Duration d) {
    final wake = _wake = Completer<void>();
    return Future.any([Future<void>.delayed(d), wake.future]);
  }

  Future<_End> _runOnce() async {
    final run = _run = Completer<void>();
    try {
      _baud = _everConnected ? _goodBaud : defaultBaud;
      _set(LinkState(LinkPhase.opening, baudRate: _baud));
      final t = _transport = await _open(_baud);
      if (!_wanted || run.isCompleted) return _End.dropped;
      channel.attach(t);
      _armWatchdog();
      if (!await _handshake(t, run)) return _End.dropped;
      await run.future;
      return _End.dropped;
    } catch (_) {
      return _End.failed;
    } finally {
      pauseWatchdog();
      _run = null;
    }
  }

  Future<bool> _handshake(Transport t, Completer<void> run) async {
    Future<bool> ask() async =>
        (await channel.request(getEcuInfoRequest(), timeout: timing.handshakeTimeout)).reply != null;
    if (await ask()) return true;
    if (_everConnected || run.isCompleted) return false;
    _baud = nextBaud(_baud);
    await t.setBaudRate(_baud);
    _set(LinkState(LinkPhase.opening, baudRate: _baud));
    return ask();
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchLast = channel.receivedCount;
    _watchdog = Timer.periodic(timing.watchdogPeriod, (_) {
      final now = channel.receivedCount;
      if (now == _watchLast) {
        _endRun();
      } else {
        _attempts = 0;
      }
      _watchLast = now;
    });
  }

  void _endRun() {
    channel.detach();
    final run = _run;
    if (run != null && !run.isCompleted) run.complete();
  }

  Future<void> _close() async {
    channel.detach();
    final t = _transport;
    _transport = null;
    try {
      await t?.close();
    } catch (_) {
      // a port that won't close is already gone
    }
  }
}
