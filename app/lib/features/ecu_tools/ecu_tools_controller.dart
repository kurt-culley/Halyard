import 'dart:async';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'strings.dart';

/// The original's ECU tools: the clock (read from the six clock links, set without seconds), password protection
/// (its checks and states) and factory reset (typed ERASE). Each is one request on the session's channel.
class EcuToolsController extends ChangeNotifier {
  EcuToolsController(this._session, this._policy) {
    _sub = _session.states.listen((_) => notifyListeners());
    // The ECU answers a lock change as an unsolicited (4,4) frame; the original kept whatever state it last reported.
    _frames = _session.connection.channel.received.listen((r) {
      if (r.frame.cls == 4 && r.frame.cmd == 3 && r.frame.payload.isNotEmpty) {
        if (!(_reset?.isCompleted ?? true)) _reset!.complete(r.frame.payload[0]);
      }
      if (r.reply case final PwLockReply p when r.frame.cls == 4 && r.frame.cmd == 4) {
        if (p.ok) {
          locked = p.locked;
          temporary = p.temporary;
          if (_pendingContact != null) contact = _pendingContact!;
        } else {
          message = EcuToolsStrings.refused;
        }
        _pendingContact = null;
        notifyListeners();
      }
    });
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => notifyListeners());
    final p = _session.password;
    if (p != null) {
      locked = p.locked;
      temporary = p.temporary;
      contact = p.contact;
    }
  }

  final Session _session;
  final SwitchablePolicy _policy;
  late final StreamSubscription<SessionState> _sub;
  late final StreamSubscription<Received> _frames;
  late final Timer _timer;
  String? _pendingContact;
  Completer<int>? _reset;

  bool locked = false, temporary = false;
  String contact = '';
  String? message;

  bool get isOnline => _session.state.phase == SessionPhase.online;
  bool get canChange => isOnline && !_policy.readOnly;

  double? _byKey(String key) {
    final live = _session.live;
    final def = _session.calibration?.definition;
    if (live == null || def == null) return null;
    for (final l in def.links.values) {
      if (l.dataKey == key && live.has(l.id)) return live.value(l.id);
    }
    return null;
  }

  /// The ECU's clock from its DAY, MONTH, YEAR, HOUR, MIN and SEC links; null when any is missing or not a time.
  DateTime? get ecuTime {
    final v = [
      for (final k in const ['YEAR', 'MONTH', 'DAY', 'HOUR', 'MIN', 'SEC']) _byKey(k),
    ];
    if (v.any((x) => x == null || !x.isFinite)) return null;
    final [y, mo, d, h, mi, s] = [for (final x in v) x!.truncate()];
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || h < 0 || h > 23 || mi < 0 || mi > 59 || s < 0 || s > 59) return null;
    final t = DateTime(y, mo, d, h, mi, s);
    return t.month == mo && t.day == d ? t : null;
  }

  /// Sent as the original sent it, without waiting for an answer: it showed none.
  Future<void> setTime(DateTime t) async {
    message = null;
    final r = await _session.connection.channel.request(
      setRtcRequest(t.day, t.month, t.year, t.hour, t.minute),
      timeout: const Duration(milliseconds: 500),
    );
    message = r.failure == Failure.blocked ? EcuToolsStrings.readOnly : EcuToolsStrings.timeSaved;
    notifyListeners();
  }

  /// The original's view of the lock: what each state says and allows.
  ({String state, bool lock, bool unlock, bool permanent, bool contact}) get view => !locked
      ? (temporary
            ? (state: EcuToolsStrings.unlockedTemporary, lock: false, unlock: true, permanent: true, contact: false)
            : (state: EcuToolsStrings.unlockedPermanent, lock: true, unlock: false, permanent: false, contact: true))
      : (state: EcuToolsStrings.locked, lock: false, unlock: true, permanent: true, contact: false);

  /// Lock: length first, then the match. Returns the problem, if any.
  String? lockCheck(String a, String b) =>
      a.length > 16 ? EcuToolsStrings.tooLong : (a == b ? null : EcuToolsStrings.mismatch);

  /// Unlock: the match only.
  String? unlockCheck(String a, String b) => a.length <= 16 && a == b ? null : EcuToolsStrings.mismatch;

  Future<void> lock(String password, String contactText) =>
      _setLock(pwLockSetStateRequest(true, false, password, contactText, const [0]), contactText);

  Future<void> unlock(String password, {required bool permanent}) =>
      _setLock(pwLockSetStateRequest(false, !permanent, password, '', const [0]), null);

  /// Sent without waiting for a matched answer: the state arrives on the received stream.
  Future<void> _setLock(Frame f, String? newContact) async {
    message = null;
    _pendingContact = newContact;
    final r = await _session.connection.channel.request(f, timeout: const Duration(milliseconds: 500));
    if (r.failure == Failure.blocked) message = EcuToolsStrings.readOnly;
    notifyListeners();
  }

  /// True when the ECU answers the reset with status 0, as the original read its answer.
  Future<bool> factoryReset() async {
    final done = _reset = Completer<int>();
    final r = await _session.connection.channel.request(factoryResetRequest(), timeout: const Duration(seconds: 2));
    if (r.failure == Failure.blocked) return false;
    final status = await done.future.timeout(const Duration(seconds: 3), onTimeout: () => -1);
    return status == 0;
  }

  @override
  void dispose() {
    _timer.cancel();
    unawaited(_sub.cancel());
    unawaited(_frames.cancel());
    super.dispose();
  }
}
