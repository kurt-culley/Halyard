/// The trigger logger (U25): crank and cam edges the ECU reports, turned into a square-wave trace, saved to and read
/// from `.metlg` text, and measured (edges between two times, the span between edges around a time). Starting and
/// stopping the logger are requests the app sends through the session.
library;

import '../wire/messages/trigger.dart';
import 'log_review.dart' show readTextLines;
import 'number_text.dart';

/// One time on the trace: every channel's level then.
final class TriggerPoint {
  TriggerPoint(this.timestamp, this.syncState, this.simulated) : values = List<double>.filled(8, 0);

  /// Seconds since logging started.
  final double timestamp;
  final int syncState;

  /// Added between two reports of the same level, where an edge must have been missed.
  final bool simulated;

  /// Level by channel id (0 crank, 1 to 4 cams).
  final List<double> values;
}

typedef _Event = ({int channel, int timestamp, int state, int syncState, bool simulated});

class TriggerLog {
  /// The channels a log can show, and which are on (crank and the first cam by default).
  final Map<int, bool> enabled = {0: true, 1: true, 2: false, 3: false, 4: false};

  /// The ECU's timer ticks per second, from its state reply; 0 after [clear] until the next one.
  int frequency = 1;
  List<TriggerPoint> points = const [];

  static const maxEvents = 50000;

  int _now = 0;
  final _latest = <int, _Event>{};
  var _events = <_Event>[];

  List<int> get enabledChannels => [
    for (final e in enabled.entries)
      if (e.value) e.key,
  ];

  void clear() {
    frequency = 0;
    _now = 0;
    _latest.clear();
    _events = [];
    points = const [];
  }

  /// A state reply: its timer frequency.
  void applyState(TriggerStateReply r) {
    if (r.ok) frequency = r.freq;
  }

  /// Adds a report's edges. Two reports of the same level on a channel get the missed edge between them, a third
  /// of the way along.
  void addReport(List<TriggerEvent> entries) {
    if (entries.isEmpty) return;
    final add = <_Event>[];
    for (final e in entries) {
      _now += e.gap;
      final ev = (
        channel: e.channel,
        timestamp: _now,
        state: e.state ? 1 : 0,
        syncState: e.syncState,
        simulated: false,
      );
      final prev = _latest[ev.channel];
      if (prev != null && ev.state == prev.state) {
        var d = (ev.timestamp - prev.timestamp) ~/ 3;
        if (d <= 0) d = 1;
        final at = prev.timestamp + d;
        var src = prev;
        for (final s in _latest.values) {
          if (s.timestamp > src.timestamp && s.timestamp < at) src = s;
        }
        add.add((
          channel: ev.channel,
          timestamp: at,
          state: ev.state == 0 ? 1 : 0,
          syncState: src.syncState,
          simulated: true,
        ));
      }
      _latest[ev.channel] = ev;
      add.add(ev);
    }
    // A stable sort by time, as the original's.
    final all = [..._events, ...add];
    final order = List<int>.generate(all.length, (i) => i)..sort((a, b) {
      final c = all[a].timestamp.compareTo(all[b].timestamp);
      return c != 0 ? c : a - b;
    });
    _events = [for (final i in order) all[i]];
    if (_events.length > maxEvents) _events = _events.sublist(_events.length - maxEvents);

    final pts = <TriggerPoint>[];
    final last = <int, double>{};
    TriggerPoint? p;
    for (final ev in _events) {
      final t = ev.timestamp / frequency;
      if (p == null || t != p.timestamp) {
        p = TriggerPoint(t, ev.syncState, ev.simulated);
        pts.add(p);
      }
      p.values[ev.channel] = ev.state.toDouble();
      for (final id in enabled.keys) {
        if (id == ev.channel) {
          last[id] = p.values[ev.channel];
        } else if (last[id] case final v?) {
          p.values[id] = v;
        }
      }
    }
    points = pts;
  }

  /// The `.metlg` text of every point, or of those from [from] to [to] with times from the first of them.
  String toText({double? from, double? to}) {
    if (points.isEmpty) return '';
    final b = StringBuffer('Timestamp${enabled.keys.map((id) => ',$id').join()},SyncState,Simulated\r\n');
    double? first;
    for (final p in points) {
      var t = p.timestamp;
      if (from != null && to != null) {
        if (p.timestamp < from || p.timestamp > to) continue;
        first ??= p.timestamp;
        t = p.timestamp - first;
      }
      b.write(_trimmed(t, 8));
      for (final id in enabled.keys) {
        b.write(',${formatGeneral(p.values[id], isFloat: false)}');
      }
      b.write(',${p.syncState},${p.simulated ? 1 : 0}\r\n');
    }
    return b.toString();
  }

  /// Reads `.metlg` text: clears the log, turns on the channels the file has, and appends its points. Throws
  /// [FormatException] for a file without a time column or with a value that isn't a number.
  void readText(String text) {
    final lines = readTextLines(text);
    if (lines.isEmpty) throw const FormatException('The trigger log is empty.');
    final cols = <String, int>{}, chans = <int, int>{};
    for (final (i, n) in lines.first.split(',').indexed) {
      if (n.isEmpty) continue;
      cols[n] = i;
      if (_channelId(n) case final id?) chans[id] = i;
    }
    clear();
    for (final id in chans.keys) {
      if (!enabled.containsKey(id)) throw FormatException('No channel $id in a trigger log.');
      enabled[id] = true;
    }
    final ti = cols['Timestamp'];
    final pts = <TriggerPoint>[];
    for (final line in lines.skip(1)) {
      final f = line.split(',');
      if (ti == null) throw const FormatException('The trigger log has no timestamp column.');
      String at(int i) => i < f.length ? f[i] : throw const FormatException('A trigger log line is short.');
      final si = cols['SyncState'], mi = cols['Simulated'];
      final p = TriggerPoint(
        parseNetDouble(at(ti)),
        si == null ? 0 : _int32(at(si)) & 0xff,
        mi != null && _int32(at(mi)) == 1,
      );
      for (final e in chans.entries) {
        p.values[e.key] = parseNetDouble(at(e.value));
      }
      pts.add(p);
    }
    points = [...points, ...pts];
  }
}

const _channelNames = {'Events': -1, 'Crank': 0, 'CamA': 1, 'Cam': 1, 'CamB': 2, 'CamC': 3, 'CamD': 4};
final _wholeNumber = RegExp(r'^[+-]?\d+$');

/// `Enum.TryParse` of a channel: a name (comma lists are OR-ed) or a number.
int? _channelId(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  if (_wholeNumber.hasMatch(t)) {
    final v = int.parse(t);
    return v >= -128 && v <= 127 ? v : null;
  }
  var v = 0;
  for (final part in t.split(',')) {
    final n = _channelNames[part.trim()];
    if (n == null) return null;
    v |= n;
  }
  return v;
}

int _int32(String s) {
  final t = s.trim();
  if (!_wholeNumber.hasMatch(t)) throw FormatException('Not a whole number: $s');
  final v = int.parse(t);
  if (v > 2147483647 || v < -2147483648) throw FormatException('Out of range: $s');
  return v;
}

String _trimmed(double v, int decimals) {
  if (!v.isFinite) return formatFixed(v, decimals, isFloat: false);
  var s = formatFixed(v, decimals, isFloat: false);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s == '-0' ? '0' : s;
}

/// Rising and falling edges of [channel] between [from] and [to].
({int rising, int falling}) edgesBetween(List<TriggerPoint> points, int channel, double from, double to) {
  var rising = 0, falling = 0;
  TriggerPoint? prev;
  for (final p in points) {
    if (p.timestamp < from) {
      prev = p;
      continue;
    }
    if (p.timestamp > to) break;
    if (prev == null) {
      prev = p;
      continue;
    }
    if (prev.values[channel] < p.values[channel]) {
      rising++;
    } else if (prev.values[channel] > p.values[channel]) {
      falling++;
    }
    prev = p;
  }
  return (rising: rising, falling: falling);
}

/// The times of the edges of [channel] either side of [at], or null when it isn't between two.
({double from, double to})? edgesAround(List<TriggerPoint> points, int channel, double at) {
  TriggerPoint? last, a, b;
  for (final p in points) {
    if (a != null && b != null) break;
    if (last == null) {
      last = p;
      continue;
    }
    if (last.values[channel] == p.values[channel]) continue;
    last = p;
    if (p.timestamp < at) {
      a = p;
    } else if (p.timestamp > at) {
      b = p;
      break;
    }
  }
  return a == null || b == null ? null : (from: a.timestamp, to: b.timestamp);
}
