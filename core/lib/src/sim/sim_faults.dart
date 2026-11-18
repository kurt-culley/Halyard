/// The simulated fault log (class 9): info, a freeze-frame layout, a code summary and a history, newest first.
/// Off until [SimFaultLog.seed]; while off, fault requests get no answer.
library;

import 'dart:typed_data';

import '../faults/fault_codes.dart';
import '../wire/bytes.dart';
import 'sim_ecu.dart';

final class SimFaultCode {
  SimFaultCode(
    this.code,
    this.state,
    this.severity,
    this.count,
    this.lifetime,
    this.firstHoursX100,
    this.firstRtc,
    this.lastHoursX100,
    this.lastRtc,
  );
  final int code, state, severity;
  int count, lifetime;
  final int firstHoursX100, firstRtc, lastHoursX100, lastRtc;
}

final class SimFaultRecord {
  SimFaultRecord(this.type, this.seq, this.code, this.count, this.lifetime, this.hoursX100, this.rtc, this.body);
  final int type, seq, code, count, lifetime, hoursX100, rtc;
  final List<int> body;
}

class SimFaultLog {
  SimFaultLog(this._ecu);
  final SimEcu _ecu;

  bool supported = false;
  int engineHoursX100 = 0, mode = FaultLogMode.faultsAndEvents, logStatus = 0, dropped = 0, seq = 0;
  static const capacity = 64;
  List<(int, int)> layout = [];
  List<SimFaultCode> summary = [];
  List<SimFaultRecord> records = [];
  Set<int> active = {};

  static final _rtcEpochMs = DateTime.utc(2020).millisecondsSinceEpoch;
  int _rtc(int msAgo) => ((_ecu.nowMs - msAgo - _rtcEpochMs) / 60000).floor();

  /// A frame of RPM, MAP, coolant, battery, throttle and sync status; four codes; six records.
  void seed() {
    supported = true;
    engineHoursX100 = 12345;
    layout =
        [
          (1, 2),
          (6, 4),
          (14, 4),
          (18, 4),
          (924, 4),
          (2, 1),
        ].where((e) => _ecu.definition.links.containsKey(e.$1)).toList();
    List<int> frame(double rpm, double map, double clt, double batt, double tps, double sync) {
      final v = {1: rpm, 6: map, 14: clt, 18: batt, 924: tps, 2: sync};
      return [
        for (final (id, size) in layout)
          ...switch (size) {
            2 => _u16(v[id]!.toInt()),
            1 => [v[id]!.toInt() & 0xff],
            _ => f32Bytes(v[id]!),
          },
      ];
    }

    int h(int x) => engineHoursX100 - x;
    const day = 86400000;
    summary = [
      SimFaultCode(102, 4, 1, 3, 7, h(4000), _rtc(40 * day), h(310), _rtc(3 * day)),
      SimFaultCode(711, 2, 1, 1, 4, h(9000), 0, h(2), _rtc(600000)),
      SimFaultCode(901, 0, 1, 12, 40, h(8000), _rtc(90 * day), h(20), _rtc(day)),
      SimFaultCode(412, 0, 2, 0, 2, h(7000), _rtc(120 * day), h(6900), _rtc(119 * day)),
    ];
    final checkpoint = [
      ..._u32(h(500)),
      ..._u16(2),
      ..._u16(102),
      ..._u16(2),
      ..._u32(6),
      ..._u32(h(4000)),
      ..._u32(_rtc(40 * day)),
      ..._u32(h(900)),
      ..._u32(_rtc(10 * day)),
      ..._u16(901),
      ..._u16(9),
      ..._u32(37),
      ..._u32(h(8000)),
      ..._u32(_rtc(90 * day)),
      ..._u32(h(600)),
      ..._u32(_rtc(6 * day)),
    ];
    seq = 41;
    final recs = [
      (1, 711, 1, 4, h(2), _rtc(600000), frame(0, 101.3, 18.5, 6.8, 0, 0)),
      (1, 901, 12, 40, h(20), _rtc(day), frame(7600, 178.2, 91.4, 14.1, 98.6, 3)),
      (1, 102, 3, 7, h(310), _rtc(3 * day), frame(3150, 64.0, 88.0, 13.9, 21.5, 1)),
      (2, 0, 0, 0, h(500), _rtc(5 * day), checkpoint),
      (4, 0, 0, 0, h(700), _rtc(8 * day), [1, 2]),
      (3, 0, 0, 0, h(800), 0, <int>[]),
    ];
    records = [
      for (final (i, (type, code, count, lifetime, hours, rtc, body)) in recs.indexed)
        SimFaultRecord(type, seq - i, code, count, lifetime, hours, rtc, body),
    ];
    active = {711};
  }

  /// The three "active bits" link values (2339, 2340, 2341 for [n] 0, 1, 2).
  int activeBits(int n) {
    var v = 0;
    for (final c in active) {
      final i = faultCode(c).index;
      if (i >= 24 * n && i < 24 * (n + 1)) v |= 1 << (i - 24 * n);
    }
    return v;
  }

  void handle(int cmd, Uint8List p) {
    void reply(List<int> payload) => _ecu.reply(9, cmd, payload);
    List<int> page<T>(List<T> all, int max, List<int> Function(T) enc) {
      final start = p.length >= 2 ? u16(p, 0) : 0;
      final want = p.length >= 4 ? u16(p, 2) : max;
      final from = start < all.length ? start : all.length;
      final to = from + (want < max ? want : max);
      final items = all.sublist(from, to < all.length ? to : all.length);
      return [0, ..._u16(start), ..._u16(items.length), ..._u16(all.length), for (final x in items) ...enc(x)];
    }

    switch (cmd) {
      case 0:
        final frameLen = layout.fold(0, (a, e) => a + e.$2);
        reply([
          0,
          ..._u16(1),
          ..._u16(faultCatalogue.length),
          ..._u16(64),
          ..._u16(frameLen),
          ..._u16(layout.length),
          ..._u16(capacity),
          ..._u16(records.length < capacity ? records.length : capacity),
          ..._u16(summary.length),
          ..._u32(engineHoursX100),
          mode,
          logStatus,
          ..._u16(dropped),
        ]);
      case 1:
        reply(page(layout, 200, (e) => [..._u16(e.$1), e.$2]));
      case 2:
        reply(
          page(
            summary,
            40,
            (c) => [
              ..._u16(c.code),
              c.state,
              c.severity,
              ..._u16(c.count),
              ..._u32(c.lifetime),
              ..._u32(c.firstHoursX100),
              ..._u32(c.firstRtc),
              ..._u32(c.lastHoursX100),
              ..._u32(c.lastRtc),
            ],
          ),
        );
      case 3:
        final ord = p.length >= 2 ? u16(p, 0) : 0;
        if (ord >= records.length) return reply([2, ..._u16(ord), 0, 0]);
        final r = records[ord];
        final rec = [
          ..._u16(0xfa17),
          r.type,
          1,
          ..._u32(r.seq),
          ..._u16(r.code),
          ..._u16(r.count),
          ..._u32(r.lifetime),
          ..._u32(r.hoursX100),
          ..._u32(r.rtc),
          ..._u16(r.body.length),
          ..._u16(64),
          ...r.body,
        ];
        reply([0, ..._u16(ord), ..._u16(rec.length), ...rec]);
      case 4:
        for (final c in summary) {
          c.count = 0;
        }
        records.insert(0, SimFaultRecord(3, ++seq, 0, 0, 0, engineHoursX100, _rtc(0), const []));
        reply([0]);
      case 5:
        if (!_ecu.engineStopped) return reply([8]);
        records = [];
        for (final c in summary) {
          c
            ..count = 0
            ..lifetime = 0;
        }
        reply([0]);
      default:
        reply([3]);
    }
  }
}

List<int> _u16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _u32(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
