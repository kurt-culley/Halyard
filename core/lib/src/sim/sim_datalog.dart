/// The simulated on-board logger (class 6): idle (1) or logging (2), a configuration and the logs it holds.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../wire/bytes.dart';
import 'sim_ecu.dart';

/// A log the simulated logger holds.
final class SimLog {
  SimLog(this.id, this.start, this.durationSec, this.freq, this.channelIds);
  final int id;
  final DateTime start;
  final double durationSec;
  final int freq;
  final List<int> channelIds;

  int get entries => (durationSec * freq).floor();
}

class SimDataLog {
  SimDataLog(this._ecu);
  final SimEcu _ecu;

  int status = 1, freq = 25, nextId = 1, startedAtMs = 0;
  bool switchHigh = false;
  List<int> channelIds = [];
  final logs = <SimLog>[];
  static const maxFreq = 100, maxChannels = 32;

  /// Samples recorded by the log in progress.
  int samplesSoFar(int nowMs) => status == 2 ? ((nowMs - startedAtMs) / 1000 * freq).floor() : 0;

  /// A configuration from the definition's standard-logging links, and two stored logs.
  void seed() {
    final links = _ecu.definition.links.values;
    final std =
        [
          for (final l in links)
            if (l.viewInTree && l.standardLogging) l.id,
        ].take(12).toList();
    channelIds = std.isNotEmpty ? std : _ecu.definition.links.keys.take(8).toList();
    final n = _ecu.now();
    final minute = n.subtract(Duration(seconds: n.second, milliseconds: n.millisecond, microseconds: n.microsecond));
    for (final (ago, dur) in [(26 * 3600000, 94.5), (50 * 60000, 31.2)]) {
      logs.add(SimLog(nextId++, minute.subtract(Duration(milliseconds: ago)), dur, freq, [...channelIds]));
    }
  }

  List<int> _info(SimLog l) {
    final d = l.start;
    return [
      l.id & 0xff,
      d.day,
      d.month,
      ..._u16(d.year),
      d.hour,
      d.minute,
      ...f32Bytes(l.durationSec),
      ..._u32(l.entries),
      ..._u16(l.channelIds.length),
    ];
  }

  void _stop() {
    if (status != 2) return;
    final ms = _ecu.nowMs;
    final dur = math.max(0.1, (ms - startedAtMs) / 1000);
    logs.add(
      SimLog(nextId++ & 0xff, DateTime.fromMillisecondsSinceEpoch(startedAtMs, isUtc: _ecu.now().isUtc), dur, freq, [
        ...channelIds,
      ]),
    );
    status = 1;
  }

  void handle(int cmd, Uint8List p) {
    void reply(List<int> payload) => _ecu.reply(6, cmd, payload);
    SimLog? find() {
      for (final l in logs) {
        if (p.isNotEmpty && l.id == p[0]) return l;
      }
      return null;
    }

    switch (cmd) {
      case 0:
        reply([0, ..._u16(maxFreq), ..._u16(maxChannels)]);
      case 1:
        reply([
          0,
          ..._u16(freq),
          ..._u16(channelIds.length),
          switchHigh ? 1 : 0,
          for (final id in channelIds) ..._u16(id),
        ]);
      case 2:
        if (status == 2 || p.length < 5) return reply([1]);
        final n = u16(p, 2);
        freq = u16(p, 0);
        switchHigh = p[4] != 0;
        channelIds = [for (var i = 0; i < n; i++) u16(p, 5 + 2 * i)];
        reply([0]);
      case 3:
        if (status != 2) {
          status = 2;
          startedAtMs = _ecu.nowMs;
        }
        reply([0]);
      case 4:
        _stop();
        reply([0]);
      case 5:
        reply([0, ..._u16(logs.length), 0, 0, 0, 0, 0, 0, 0, 0, for (final l in logs) ..._info(l)]);
      case 6:
        final l = find();
        if (l == null) return reply([1]);
        reply([0, ..._info(l), for (final id in l.channelIds) ..._u16(id)]);
      case 7:
        final l = find();
        if (l == null) return reply([1]);
        final start = u32(p, 1);
        final count = math.max(0, math.min(math.min(u32(p, 5), l.entries - start), 40));
        final out = [0, l.id, ..._u16(l.channelIds.length), ..._u32(start), ..._u32(count)];
        for (var i = start; i < start + count; i++) {
          final t = i / l.freq;
          out.addAll(f32Bytes(t * 1000));
          for (final id in l.channelIds) {
            final lk = _ecu.definition.links[id];
            final (lo, hi) =
                lk != null && lk.minValue != lk.maxValue ? (lk.minValue, lk.maxValue) : _ecu.ranges[id] ?? (0.0, 100.0);
            out.addAll(f32Bytes(simValue(id, lo, hi, t)));
          }
        }
        reply(out);
      case 8:
        final l = find();
        if (l == null || status == 2) return reply([1, if (p.isNotEmpty) p[0] else 0]);
        logs.remove(l);
        reply([0, p[0]]);
      case 9:
        if (status == 2) return reply([1]);
        logs.clear();
        reply([0]);
      default:
        reply([3]);
    }
  }
}

List<int> _u16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _u32(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
