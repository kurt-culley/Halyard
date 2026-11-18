/// A simulated ECU for demo mode and tests. It holds its own copy of a calibration, answers what the connect sequence
/// and the editors ask, applies writes to its copy and streams live reports while reporting is on. Ported from the
/// TypeScript project's `ecu-sim.ts` (requirement W02 S01–S11); not something the original tool had.
///
/// Not yet simulated, waiting for `faults/` and `can/`: the fault log (class 9 gets no answer, as when the
/// TypeScript simulator's fault log is off, and the fault-bit links report 0) and the CAN ids reserved by the
/// driver's own streams (2/3 answers with none).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../calibration/calibration.dart';
import '../definition/definition.dart';
import '../wire/bytes.dart';
import '../wire/framing.dart';
import 'sim_datalog.dart';
import 'sim_trigger.dart';

class SimEcu {
  /// [calibration] is copied; the simulator changes only its own copy.
  SimEcu(
    Calibration calibration, {
    this.uuid = 'SIM-0001',
    this.fwVersion = 'sim',
    this.reportPeriod = const Duration(milliseconds: 100),
    this.baudRate = 230400,
    DateTime Function()? now,
    this.engineStopped = false,
    this.password,
  }) : calibration = calibration.copy(),
       now = now ?? DateTime.now {
    final d = definition;
    // A configured ECU: the tables shown in the tree are on.
    for (final t in d.tables.values) {
      if (t.viewInTree) this.calibration.tables[t.id]!.enabled = true;
    }
    // Links without a range in the definition sweep across the axes of the tables that use them.
    void span(int id, Float32List axis) {
      if (id == 0 || axis.length < 2) return;
      var lo = double.infinity, hi = double.negativeInfinity;
      for (final v in axis) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
      final r = ranges[id];
      ranges[id] = r == null ? (lo, hi) : (math.min(r.$1, lo), math.max(r.$2, hi));
    }

    for (final t in d.tables.values) {
      final v = this.calibration.tables[t.id]!;
      span(t.input0LinkId, v.x);
      if (t.isMap) span(t.input1LinkId, v.y);
    }
    dataLog = SimDataLog(this);
    trigger = SimTrigger(this);
  }

  final Calibration calibration;
  final String uuid, fwVersion;
  final Duration reportPeriod;

  /// The only rate the simulator answers at.
  final int baudRate;
  final DateTime Function() now;

  /// RPM reads 0.
  bool engineStopped;

  /// Password protection; null for an unprotected ECU. The TypeScript simulator had none.
  SimPassword? password;
  bool reporting = false;

  /// Live values sweep inside these ranges when the definition gives none.
  final ranges = <int, (double, double)>{};

  /// Each request handled, as "class/command".
  final log = <String>[];

  late final SimDataLog dataLog;
  late final SimTrigger trigger;

  /// Drive-by-wire duty from the last 8/0 request.
  double dbwDuty = 0;

  Definition get definition => calibration.definition;

  void Function(Uint8List bytes)? _send;
  Timer? _reportTimer;

  /// Connects the simulator to a byte sink; null disconnects and stops everything it streams.
  void attach(void Function(Uint8List bytes)? send) {
    _send = send;
    if (send == null) {
      setReporting(false);
      trigger.stop();
    }
  }

  void reply(int cls, int cmd, List<int> payload) =>
      _send?.call(encodeFrame(Frame(MsgType.rsp, cls, cmd, Uint8List.fromList(payload))));

  int get nowMs => now().millisecondsSinceEpoch;

  /// One frame from the host. Throws when a request doesn't fit the calibration (a blob of the wrong shape, an offset
  /// out of range); such a request gets no answer.
  void handle(Frame f) {
    if (f.type != MsgType.req) return; // a lifesign and other answers need no reply
    final p = f.payload;
    final id = p.length >= 2 ? p[0] | (p[1] << 8) : 0;
    log.add('${f.cls}/${f.cmd}');
    switch (f.cls) {
      case 6:
        return dataLog.handle(f.cmd, p);
      case 9:
        return; // no fault log yet
      case 7:
        return trigger.handle(f.cmd, p);
      case 8 when f.cmd == 0 && p.length >= 5:
        dbwDuty = f32(p, 1);
        return reply(8, 0, [0]);
    }
    final c = calibration;
    switch ((f.cls, f.cmd)) {
      case (4, 0):
        final i = definition.info;
        final hash = c.overallHash.toRadixString(16).toUpperCase().padLeft(4, '0');
        reply(4, 0, [
          0,
          ...utf8.encode(
            '${i.productName}\u0000${i.modelName}\u0000${i.version}\u0000$fwVersion\u0000$uuid\u0000$hash\u0000',
          ),
          if (password != null) ...utf8.encode('PW\u0000'),
        ]);
      case (4, 1):
        if (p.isEmpty || p[0] != 1) return reply(4, 1, [0, 0, ..._u16(c.overallHash)]);
        final ids = [...definition.tables.keys, ...definition.drivers.keys];
        reply(4, 1, [
          0,
          1,
          ..._u16(c.overallHash),
          ..._u16(ids.length),
          for (final i in ids) ...[..._u16(i), ..._u16(c.hashFor(i)!)],
        ]);
      case (4, 5):
        final pw = password;
        reply(4, 5, [
          0,
          if (pw != null) ...[
            if (pw.locked) 1 else 0,
            if (pw.temporary) 1 else 0,
            ...utf8.encode(pw.contact),
          ] else ...[
            0,
            0,
          ],
        ]);
      case (1, 1):
        final t = definition.tables[id];
        if (t == null) return reply(1, 1, [2, ..._u16(id)]);
        final b = tableBlob(t, c.tables[id]!);
        reply(1, 1, [0, ..._u16(id), ..._u16(b.length), ...b]);
      case (1, 0):
        final t = definition.tables[id];
        if (t == null) return reply(1, 0, [2, ..._u16(id)]);
        c.tables[id] = parseTableBlob(t, Uint8List.sublistView(p, 4), c.tables[id]);
        reply(1, 0, [0, ..._u16(id)]);
      case (1, 4):
        if (definition.tables[id] == null) return reply(1, 4, [2, ..._u16(id)]);
        _setData(id, p);
      case (1, 6):
        reply(1, 6, [0, ..._u16(id)]);
      case (2, 1):
        final d = definition.drivers[id];
        if (d == null) return reply(2, 1, [2, ..._u16(id)]);
        final b = driverBlob(d, c.drivers[id]!);
        reply(2, 1, [0, ..._u16(id), ..._u16(b.length), ...b]);
      case (2, 0):
        final d = definition.drivers[id];
        if (d == null) return reply(2, 0, [2, ..._u16(id)]);
        c.drivers[id] = parseDriverBlob(d, Uint8List.sublistView(p, 4), c.drivers[id]);
        reply(2, 0, [0, ..._u16(id)]);
      case (2, 2):
        reply(2, 2, [0, ..._u16(id)]);
      case (2, 3):
        reply(2, 3, [0, 0]); // no reserved CAN ids yet
      case (0, 2):
        setReporting(p.isNotEmpty && p[0] == 1);
        reply(0, 2, [0]);
      default:
        reply(f.cls, f.cmd, [3]); // unsupported request
    }
  }

  /// SetTableData: element, count, then (offset, value) pairs. The wire form doesn't say how many values follow each
  /// offset; the editors only ever send one, so one is assumed.
  void _setData(int id, Uint8List p) {
    final v = calibration.tables[id]!;
    final elem = p[2];
    final count = p[3] | (p[4] << 8);
    final arr = switch (elem) {
      0 => v.x,
      1 => v.y,
      _ => v.z,
    };
    final out = [0, ..._u16(id), elem, ..._u16(count)];
    var o = 5;
    for (var i = 0; i < count; i++, o += 6) {
      final off = u16(p, o);
      final value = f32(p, o + 2);
      RangeError.checkValidIndex(off, arr);
      if (arr[off] != value) arr[off] = value;
      out.addAll([..._u16(off), ...f32Bytes(value)]);
    }
    reply(1, 4, out);
  }

  void setReporting(bool on) {
    reporting = on;
    if (on) {
      _reportTimer ??= Timer.periodic(reportPeriod, (_) => report());
    } else {
      _reportTimer?.cancel();
      _reportTimer = null;
    }
  }

  /// A version-1 report with a value for every link: text-valued links cycle through their texts; others sweep inside
  /// their range, else across the axes that use them, else 0–100.
  void report() {
    final ms = nowMs;
    final t = ms / 1000;
    final out = <int>[];
    final links = definition.links.values.toList();
    for (final l in links) {
      out.addAll(_u16(l.id));
      out.addAll(f32Bytes(_reportValue(l, ms, t)));
    }
    reply(0, 0, [0, ..._u16(links.length), ...out]);
  }

  double _reportValue(LinkDef l, int ms, double t) {
    final id = l.id;
    if (id == 1015) return dataLog.status.toDouble();
    if (id == 1018) return dataLog.samplesSoFar(ms).toDouble();
    if (id >= 2331 && id <= 2335) return _canLink(id, t);
    if (id == 1 && engineStopped) return 0;
    if (id >= 2339 && id <= 2341) return 0; // fault bits: no fault log yet
    if (_dbwValue(l.dataKey) case final v?) return v;
    final tv = l.textValues;
    if (tv != null && tv.isNotEmpty) return tv.keys.elementAt((t / 3 + id).floor() % tv.length);
    final (lo, hi) = l.minValue != l.maxValue ? (l.minValue, l.maxValue) : ranges[id] ?? (l.minValue, l.maxValue);
    return simValue(id, lo, hi, t);
  }

  /// Custom CAN status links: active, counters rising.
  double _canLink(int id, double t) => switch (id) {
    2332 => 1,
    2333 => ((t * 50).floor() % 1000000).toDouble(),
    2334 => ((t * 20).floor() % 1000000).toDouble(),
    _ => 0,
  };

  /// A drive-by-wire throttle: plate % = clamp(10 + duty); TPPS raw 10000 + 400·duty (TPPS2 mirrored).
  double? _dbwValue(String? key) {
    final d = dbwDuty;
    final plate = math.min(100.0, math.max(0.0, 10 + d));
    final raw = math.min(60000.0, math.max(2000.0, 10000 + 400 * d));
    return switch (key) {
      'DBW_PWM' => d,
      'DBW_BATT_V_MULT' => 1,
      'TPPS1_VAL' => plate,
      'TPPS2_VAL' => 100 - plate,
      'TPPS1_RAW' => raw,
      'TPPS2_RAW' => 62000 - raw,
      _ => null,
    };
  }
}

/// The simulated ECU's password protection.
final class SimPassword {
  const SimPassword({this.locked = true, this.temporary = false, this.contact = ''});
  final bool locked, temporary;
  final String contact;
}

/// A smooth sweep for link [id] between [min] and [max] (0–100 above [min] when the range is unusable).
double simValue(int id, double min, double max, double t) {
  final lo = min.isFinite ? min : 0.0;
  final hi = max.isFinite && max > lo ? max : lo + 100;
  final phase = (id * 0.618) % 1;
  return lo + (hi - lo) * (0.5 + 0.4 * math.sin(2 * math.pi * (t / (4 + (id % 7)) + phase)));
}

List<int> _u16(int v) => [v & 0xff, (v >> 8) & 0xff];

/// [v] as a little-endian float.
List<int> f32Bytes(double v) => (ByteData(4)..setFloat32(0, v, Endian.little)).buffer.asUint8List();
