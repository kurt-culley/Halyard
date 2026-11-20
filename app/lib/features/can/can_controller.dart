import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'strings.dart';

/// The custom CAN configuration (driver 8253's private data) as a working copy: twelve receive and twelve transmit
/// messages of eight signals each, checked the original's way and saved and stored through the write gate.
class CanController extends ChangeNotifier {
  CanController(this._session, this._gate, this._policy, this._saver) {
    _sub = _session.states.listen((_) {
      if (config == null) _load();
      notifyListeners();
    });
    _load();
  }

  static const driverId = 8253;

  final Session _session;
  final WriteGate _gate;
  final SwitchablePolicy _policy;
  final FileSaver _saver;
  late final StreamSubscription<SessionState> _sub;

  CustomCanConfig? config;
  bool transmit = false;
  int message = 0;
  int? signal;
  bool dirty = false;
  bool busy = false;
  String? note;

  bool get isOnline => _session.calibration != null && _session.state.phase == SessionPhase.online;
  bool get supported => _session.calibration?.definition.drivers.containsKey(driverId) ?? false;
  bool get canSave => isOnline && !_policy.readOnly && !busy;

  void _load() {
    final v = _session.calibration?.drivers[driverId];
    if (v == null) return;
    final c = config = CustomCanConfig.decode(v.priv);
    note = c.wasReset ? CanStrings.wasReset : null;
    dirty = false;
  }

  void revert() {
    _load();
    notifyListeners();
  }

  List<LinkDef> get links => [
    for (final l in _session.calibration?.definition.links.values ?? const <LinkDef>[])
      if (l.viewInTree) l,
  ]..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

  String linkName(int id) => id == 0 ? CanStrings.none : (_session.calibration?.definition.links[id]?.name ?? '$id');

  bool _exists(int id) => _session.calibration?.definition.links.containsKey(id) ?? false;

  RxMessage? get rx => transmit ? null : config?.rx[message];
  TxMessage? get tx => transmit ? config?.tx[message] : null;

  /// The selected message's check.
  CanCheck get check {
    final c = config;
    if (c == null) return CanCheck();
    return transmit ? checkTx(c.tx[message], _exists, null) : checkRx(c.rx[message], _exists, null);
  }

  /// Every message's errors, for the save button.
  bool get allValid {
    final c = config;
    if (c == null) return false;
    final all = checkCustomCan(c, _exists, null);
    return [...all.rx, ...all.tx].every((v) => v.isValid);
  }

  void side(bool tx) {
    transmit = tx;
    message = 0;
    signal = null;
    notifyListeners();
  }

  void pick(int i) {
    message = i;
    signal = null;
    notifyListeners();
  }

  void pickSignal(int? i) {
    signal = i;
    notifyListeners();
  }

  /// Any change to the working copy.
  void edit(void Function() f) {
    f();
    dirty = true;
    notifyListeners();
  }

  /// Turns a signal on or off. A signal turned on with no shape yet (an empty configuration is all zeros) gets 8
  /// bits from the first free bit and a multiplier of 1, as a new signal dragged on the original's grid did.
  void enableSignal(int i, bool on) => edit(() {
    final used = <int>{};
    for (final s in spans) {
      for (var b = s.start; b < s.start + s.length && b < 64; b++) {
        used.add(b);
      }
    }
    var free = 0;
    while (used.contains(free) && free < 56) {
      free += 8;
    }
    if (rx case final m?) {
      final s = m.signals[i]..enabled = on;
      if (on && s.bitLength == 0) {
        s
          ..startBit = free
          ..bitLength = 8;
      }
      if (on && s.mult == 0) s.mult = 1;
    } else if (tx case final m?) {
      final s = m.signals[i]..enabled = on;
      if (on && s.bitLength == 0) {
        s
          ..startBit = free
          ..bitLength = 8;
      }
      if (on && s.mult == 0) s.mult = 1;
    }
  });

  /// The selected message's signal spans, as (start, length, big endian) per enabled signal, in signal order.
  List<({int index, int start, int length, bool bigEndian})> get spans {
    final out = <({int index, int start, int length, bool bigEndian})>[];
    if (rx case final m?) {
      for (final (i, s) in m.signals.indexed) {
        if (s.enabled) out.add((index: i, start: s.startBit, length: s.bitLength, bigEndian: m.bigEndian));
      }
    } else if (tx case final m?) {
      for (final (i, s) in m.signals.indexed) {
        if (s.enabled) out.add((index: i, start: s.startBit, length: s.bitLength, bigEndian: s.bigEndian));
      }
    }
    return out;
  }

  /// Imports the chosen DBC messages into this side's slots, asking before an id is replaced; the summary text.
  Future<String> importDbc(List<(DbcMessage, List<DbcSignal>)> selection, ReplaceQuestion ask) async {
    final c = config;
    if (c == null) return '';
    final r = transmit ? await importTx(c, selection, ask: ask) : await importRx(c, selection, ask: ask);
    if (r.added > 0) dirty = true;
    notifyListeners();
    return dbcImportSummary(r);
  }

  bool get hasMessages => transmit ? config!.tx.any((m) => m.enabled) : config!.rx.any((m) => m.enabled);

  Future<void> exportDbc() async {
    final c = config;
    if (c == null) return;
    String? name(int id) => _session.calibration?.definition.links[id]?.name;
    final text = transmit ? exportTxDbc(c.tx, name) : exportRxDbc(c.rx, name);
    await _saver.save(CanStrings.exportName(transmit), Uint8List.fromList(utf8.encode(text)));
  }

  /// Encodes the working copy into the driver's private data (with its checksum), sends the driver and stores it.
  Future<void> save() async {
    final c = config;
    if (c == null || !canSave || !allValid) return;
    busy = true;
    notifyListeners();
    _gate.setDriverPrivate(driverId, c.encode());
    final r = await _gate.saveDriver(driverId, store: true);
    busy = false;
    final failed = r.failed;
    if (failed == null) {
      dirty = false;
      note = CanStrings.saved;
    } else {
      note = CanStrings.failed(failed.failure.name);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}
