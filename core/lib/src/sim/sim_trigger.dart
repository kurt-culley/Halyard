/// The simulated trigger logger (class 7): a 36-1 crank wheel and a one-per-cycle cam at 1000 rpm, timer 100 kHz,
/// reported every 50 ms.
library;

import 'dart:async';
import 'dart:typed_data';

import 'sim_ecu.dart';

class SimTrigger {
  SimTrigger(this._ecu);
  final SimEcu _ecu;

  static const mask = 0x3, freq = 100000;
  static const period = Duration(milliseconds: 50);
  int enabledMask = 0;
  bool started = false;

  /// Timer ticks reported so far, and the time of the last edge sent.
  double tick = 0;
  int last = 0;
  Timer? _timer;

  void stop() {
    _timer?.cancel();
    _timer = null;
    started = false;
  }

  void handle(int cmd, Uint8List p) {
    switch (cmd) {
      case 0:
        _ecu.reply(7, 0, [0, mask]);
      case 1:
        final on = p.isNotEmpty && p[0] != 0;
        enabledMask = on ? (p.length > 1 ? p[1] : 0) & mask : 0;
        if (on && !started) {
          started = true;
          tick = 0;
          last = 0;
          _timer = Timer.periodic(period, (_) => report());
        }
        if (!on && started) stop();
        _ecu.reply(7, 1, [0, if (on) 1 else 0, enabledMask, ..._u32(freq)]);
      default:
        _ecu.reply(7, cmd, [3]);
    }
  }

  /// The edges in the next 50 ms: tooth period 1/600 s; tooth 35 missing; cam high over teeth 5–10 of the first turn.
  void report() {
    const tooth = freq / 600;
    final end = tick + freq / 20;
    final ev = <(int, int, int)>[];
    for (var n = (tick / tooth).floor(); n * tooth < end; n++) {
      final t0 = (n * tooth).round();
      final k = n % 36, k72 = n % 72;
      if (k != 35) {
        if (t0 >= tick) ev.add((t0, 0, 1));
        final t1 = (t0 + tooth / 2).round();
        if (t1 >= tick && t1 < end) ev.add((t1, 0, 0));
      }
      if (k72 == 5 && t0 >= tick) ev.add((t0 + 20, 1, 1));
      if (k72 == 11 && t0 >= tick) ev.add((t0 + 20, 1, 0));
    }
    tick = end;
    // A stable sort by time: edges at the same tick keep the order they were found in.
    final kept = [
      for (final (i, e) in ev.indexed)
        if (e.$1 < end && (enabledMask >> e.$2) & 1 == 1) (i, e),
    ]..sort((a, b) => a.$2.$1 != b.$2.$1 ? a.$2.$1.compareTo(b.$2.$1) : a.$1.compareTo(b.$1));
    final out = <int>[];
    for (final (_, (t, ch, st)) in kept) {
      final rev = t / (tooth * 36);
      final sync = rev < 1 ? 1 : (rev < 2 ? 2 : (rev < 3 ? 3 : 4));
      final d = t - last;
      out.addAll([ch | (st << 3) | (sync << 4), d & 0xff, (d >> 8) & 0xff]);
      last = t;
    }
    _ecu.reply(7, 2, [0, kept.length & 0xff, (kept.length >> 8) & 0xff, ...out]);
  }
}

List<int> _u32(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
