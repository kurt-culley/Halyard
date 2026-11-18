/// The session: what the app knows about the connected ECU, and the connect sequence that gets it there.
///
/// On every identity reply the session either confirms the calibration it already holds (same kind of ECU and the
/// same overall hash), reads only what changed (detailed hashes), or matches a definition and reads everything. Then
/// it turns reporting on and keeps it alive with a lifesign. Ported from the original's message handler by way of the
/// TypeScript project's `message-handler.ts` (U08 H01–H03, H12, H14, L01–L07).
library;

import 'dart:async';

import '../calibration/calibration.dart';
import '../definition/definition.dart';
import '../definition/device_file.dart';
import '../link/channel.dart';
import '../link/connection.dart';
import '../wire/messages/drivers.dart';
import '../wire/messages/reporting.dart';
import '../wire/messages/sys.dart';
import '../wire/messages/tables.dart';

/// Finds the definition file for an ECU, or null when there is none. The definition library implements this.
typedef DefinitionLookup = FutureOr<DeviceFile?> Function(DeviceInfo ecu);

enum SessionPhase {
  /// No link.
  offline,

  /// Opening the port, or waiting to reconnect.
  connecting,

  /// The link is up; asking the ECU who it is, its password state and its hashes.
  identifying,

  /// Finding a definition for the ECU.
  loadingDefinition,

  /// Reading tables and drivers.
  readingCalibration,

  /// The calibration matches the ECU and reporting is on.
  online,

  /// Updating firmware.
  flashing,
}

/// Why a session stopped short of online while the link is up.
enum SessionProblem {
  none,

  /// No definition describes the ECU.
  noDefinition,

  /// The ECU didn't answer a request in the connect sequence.
  noAnswer,
}

final class SessionState {
  const SessionState(this.phase, {this.problem = SessionProblem.none, this.done = 0, this.total = 0});
  final SessionPhase phase;
  final SessionProblem problem;

  /// Reading only: tables and drivers read so far, and how many there are to read.
  final int done, total;

  @override
  bool operator ==(Object other) =>
      other is SessionState &&
      other.phase == phase &&
      other.problem == problem &&
      other.done == done &&
      other.total == total;
  @override
  int get hashCode => Object.hash(phase, problem, done, total);
  @override
  String toString() => 'SessionState($phase, $problem, $done/$total)';
}

/// The ECU's password protection.
final class PasswordState {
  const PasswordState({required this.locked, required this.temporary, required this.contact});
  final bool locked, temporary;

  /// How to reach the tuner who locked it.
  final String contact;
}

class Session {
  Session(this.connection, {required this.definitions, this.lifesignPeriod = const Duration(milliseconds: 1500)}) {
    _subs
      ..add(connection.states.listen(_onLink))
      ..add(connection.channel.received.listen(_onReceived));
    _onLink(connection.state);
  }

  final Connection connection;
  final DefinitionLookup definitions;
  final Duration lifesignPeriod;

  Channel get _channel => connection.channel;

  final _states = StreamController<SessionState>.broadcast(sync: true);
  var _state = const SessionState(SessionPhase.offline);
  SessionState get state => _state;
  Stream<SessionState> get states => _states.stream;

  /// The connected ECU as it identified itself; kept after the link drops.
  DeviceInfo? ecu;
  String? ecuUuid;
  PasswordState? password;

  /// The ECU's calibration as last read; kept after the link drops, so a reconnect reads only what changed.
  Calibration? calibration;

  /// The calibration as it was when the session last came online.
  Calibration? snapshot;

  /// Tables and drivers whose values from the ECU didn't fit the definition; they keep the definition's values.
  final unreadable = <int>{};

  final _subs = <StreamSubscription<Object?>>[];
  Timer? _lifesign;

  /// Bumped whenever a connect sequence starts or the link changes, so a stale one stops at its next step.
  var _run = 0;

  void dispose() {
    _stopLifesign();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _run++;
  }

  void _set(SessionState s) {
    if (s == _state) return;
    _state = s;
    _states.add(s);
  }

  void _onLink(LinkState s) {
    switch (s.phase) {
      case LinkPhase.closed:
        _run++;
        _stopLifesign();
        _set(const SessionState(SessionPhase.offline));
      case LinkPhase.opening || LinkPhase.reconnecting:
        _run++;
        _stopLifesign();
        _set(const SessionState(SessionPhase.connecting));
      case LinkPhase.connected:
        if (_state.phase == SessionPhase.connecting || _state.phase == SessionPhase.offline) {
          _set(const SessionState(SessionPhase.identifying));
        }
    }
  }

  void _onReceived(Received r) {
    // Every identity reply starts the sequence, the one the connection's handshake gets included.
    if (r.reply case final EcuInfoReply info when info.ok) unawaited(_identify(info));
  }

  Future<void> _identify(EcuInfoReply r) async {
    final run = ++_run;
    bool stale() => run != _run;
    final info = DeviceInfo(
      productName: r.productName,
      modelName: r.modelName,
      version: r.version,
      fwVersion: r.fwVersion,
    );
    _set(const SessionState(SessionPhase.identifying));

    // The same kind of ECU as before: confirm by the overall hash, or read what changed.
    final cal = calibration;
    final previous = ecu;
    if (cal != null && previous != null && previous.sameDevice(info) && r.hash != null) {
      ecu = info;
      if (cal.overallHash == r.hash) return _read(run, const [], announceEmpty: true);
      final hashes = await _channel.request(getHashRequest(HashMode.detailed));
      if (stale()) return;
      final reply = hashes.reply;
      if (reply is! HashReply || !reply.ok) return _set(_problem(SessionProblem.noAnswer));
      return _read(run, [
        for (final (id, h) in reply.hashes)
          if (cal.hashFor(id) case final mine? when mine != h) id,
      ]);
    }

    _set(const SessionState(SessionPhase.loadingDefinition));
    final file = await definitions(info);
    if (stale()) return;
    if (file == null) {
      calibration = null;
      return _set(const SessionState(SessionPhase.loadingDefinition, problem: SessionProblem.noDefinition));
    }
    ecu = info;
    ecuUuid = r.uuid;
    unreadable.clear();
    final fresh = calibration = file.calibration.copy();
    if (r.passwordProtection) {
      _set(const SessionState(SessionPhase.identifying));
      final pw = await _channel.request(pwLockGetStateRequest());
      if (stale()) return;
      final reply = pw.reply;
      if (reply is! PwLockReply || !reply.ok) return _set(_problem(SessionProblem.noAnswer));
      password = PasswordState(locked: reply.locked, temporary: reply.temporary, contact: reply.tunerContact ?? '');
    } else {
      password = null;
    }
    // Everything, tables first; a locked ECU is read too (it answers what it allows).
    await _read(run, [...fresh.definition.tables.keys, ...fresh.definition.drivers.keys]);
  }

  SessionState _problem(SessionProblem p) =>
      SessionState(_state.phase, problem: p, done: _state.done, total: _state.total);

  /// Reads [ids] with reporting off, then turns reporting on. With nothing to read, reporting is only turned off first
  /// when [announceEmpty] (the overall hash matched), as the original did.
  Future<void> _read(int run, List<int> ids, {bool announceEmpty = false}) async {
    final cal = calibration!;
    if (ids.isNotEmpty || announceEmpty) {
      _set(SessionState(SessionPhase.readingCalibration, total: ids.length));
      _stopLifesign();
      unawaited(_channel.request(setStateRequest(false)));
    }
    for (final (i, id) in ids.indexed) {
      final table = cal.definition.tables[id];
      final driver = cal.definition.drivers[id];
      if (table == null && driver == null) continue;
      final result = await _channel.request(table != null ? getTableRequest(id) : getDriverRequest(id));
      if (run != _run) return;
      if (result.reply == null) return _set(_problem(SessionProblem.noAnswer));
      if (result.reply case final BlobReply b when b.ok) {
        try {
          if (table != null) {
            cal.tables[id] = parseTableBlob(table, b.blob, cal.tables[id]);
          } else {
            cal.drivers[id] = parseDriverBlob(driver!, b.blob, cal.drivers[id]);
          }
          unreadable.remove(id);
        } on BlobError {
          unreadable.add(id);
        }
      }
      _set(SessionState(SessionPhase.readingCalibration, done: i + 1, total: ids.length));
    }
    if (run != _run) return;
    snapshot = cal.copy();
    unawaited(_channel.request(setStateRequest(true)));
    _startLifesign();
    _set(const SessionState(SessionPhase.online));
  }

  void _startLifesign() {
    _lifesign?.cancel();
    _lifesign = Timer.periodic(lifesignPeriod, (_) => unawaited(_channel.request(ackFrame())));
  }

  void _stopLifesign() {
    _lifesign?.cancel();
    _lifesign = null;
  }

  /// Turns reporting off (for the trigger scope, say) and stops the lifesign; [resumeReporting] undoes it.
  Future<RequestResult> pauseReporting() {
    _stopLifesign();
    return _channel.request(setStateRequest(false));
  }

  Future<RequestResult> resumeReporting() {
    _startLifesign();
    return _channel.request(setStateRequest(true));
  }
}
