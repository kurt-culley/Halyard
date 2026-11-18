/// Live values from the ECU's reports: per link, a preallocated ring buffer of (time, value), the latest value, and a
/// staleness flag; for the whole store, one version counter and per-link dirty bits. The app turns the version into one
/// repaint tick per report; instruments read from here directly.
///
/// History follows the original (U11-H01, V01, V02): every report adds a sample to every link. A link the report
/// doesn't mention repeats its latest value, and is marked stale; one mentioned twice gets both. The latest value
/// keeps its stored form when an equal one arrives (0 equals -0, NaN equals NaN); history keeps what arrived.
///
/// Playback (U27, V03 to V05, V07) works on the same buffers. While paused, reports go to a second buffer per link and
/// what instruments see stays put; seeking back shows history up to that point, the value there as the latest; going
/// live again appends what arrived meanwhile. A recording loaded for playback replaces the history.
library;

import 'dart:typed_data';

import '../definition/definition.dart';
import '../logs/live_recording.dart';
import '../wire/bytes.dart' show fround;
import '../wire/messages/reporting.dart';

class LiveStore {
  LiveStore(Definition definition, {this.capacity = defaultCapacity})
    : ids = List.unmodifiable(definition.links.keys),
      _names = [for (final l in definition.links.values) l.name],
      _times = Float64List(definition.links.length * capacity),
      _values = Float32List(definition.links.length * capacity),
      _start = Int32List(definition.links.length),
      _count = Int32List(definition.links.length),
      _visible = Int32List(definition.links.length),
      _pendingTimes = Float64List(definition.links.length * capacity),
      _pendingValues = Float32List(definition.links.length * capacity),
      _pendingStart = Int32List(definition.links.length),
      _pendingCount = Int32List(definition.links.length),
      _latest = Float32List(definition.links.length),
      _stale = Uint8List(definition.links.length)..fillRange(0, definition.links.length, 1),
      _dirty = Uint8List(definition.links.length),
      _reported = Uint8List(definition.links.length) {
    for (final (i, id) in ids.indexed) {
      _index[id] = i;
    }
  }

  /// Samples kept per link, as the original kept.
  static const defaultCapacity = 1200;
  final int capacity;

  /// Links in definition order.
  final List<int> ids;
  final _index = <int, int>{};

  /// Bumped once per report applied.
  int version = 0;

  final List<String?> _names;
  final Float64List _times, _pendingTimes;
  final Float32List _values, _pendingValues;
  final Int32List _start, _count, _visible, _pendingStart, _pendingCount;
  bool _paused = false;
  final Float32List _latest;
  final Uint8List _stale, _dirty, _reported;

  bool has(int id) => _index.containsKey(id);

  /// The latest value; 0 before any report.
  double value(int id) => _latest[_i(id)];

  /// Not in the latest report (or no report yet).
  bool isStale(int id) => _stale[_i(id)] != 0;

  /// Samples shown for [id], at most [capacity]: all of them when live, those up to the playback point when seeking.
  int length(int id) => _visible[_i(id)];

  /// The [k]th sample of [id], oldest first: (time in ms since the epoch, value).
  (double, double) sample(int id, int k) {
    final i = _i(id);
    RangeError.checkValidIndex(k, null, 'k', _visible[i]);
    final at = i * capacity + (_start[i] + k) % capacity;
    return (_times[at], _values[at]);
  }

  /// Ids whose latest value changed since the last call, in definition order; clears the dirty bits.
  List<int> takeDirty() {
    final out = <int>[];
    for (var i = 0; i < ids.length; i++) {
      if (_dirty[i] != 0) {
        out.add(ids[i]);
        _dirty[i] = 0;
      }
    }
    return out;
  }

  /// Applies one report received at [atMs] (ms since the epoch). A report with a failure status is ignored.
  void apply(ReportReply report, double atMs) {
    if (!report.ok) return;
    _reported.fillRange(0, ids.length, 0);
    for (final e in report.entities) {
      final i = _index[e.id];
      if (i == null) continue; // a link the definition doesn't have
      _receive(i, fround(e.value.toDouble()), atMs);
      _reported[i] = 1;
    }
    for (var i = 0; i < ids.length; i++) {
      final missing = _reported[i] == 0;
      if (missing) _receive(i, _latest[i], atMs);
      if (!_paused) _stale[i] = missing ? 1 : 0;
    }
    if (!_paused) version++;
  }

  // ---------------------------------------------------------------- playback

  /// Paused or seeking: reports are kept aside and what is shown stays put.
  bool get isPaused => _paused;

  void pause() => _paused = true;

  /// Whether any link has a sample [back] samples before its newest.
  bool canSeekBack(int back) {
    for (var i = 0; i < ids.length; i++) {
      if (_count[i] - back - 1 >= 0) return true;
    }
    return false;
  }

  /// Pauses and shows each link as it was [back] samples before its newest (no history and 0 when it has fewer).
  void seekBack(int back) {
    _paused = true;
    for (var i = 0; i < ids.length; i++) {
      _showUpTo(i, _count[i] - back - 1);
    }
    version++;
  }

  /// Goes live: what arrived while paused joins the history, and each link shows its newest sample.
  void resume() {
    if (!_paused) return;
    for (var i = 0; i < ids.length; i++) {
      for (var k = 0; k < _pendingCount[i]; k++) {
        final at = i * capacity + (_pendingStart[i] + k) % capacity;
        _push(_times, _values, _start, _count, i, _pendingTimes[at], _pendingValues[at]);
      }
      _pendingStart[i] = 0;
      _pendingCount[i] = 0;
      _visible[i] = 0;
      _showUpTo(i, _count[i] - 1);
    }
    _paused = false;
    version++;
  }

  /// Replaces the history with a recording for playback, pausing first: each link gets the column of its name, or
  /// the time column's zeros when the recording has none. Recording times are local clock times, taken here as UTC.
  void loadRecording(LiveRecording recording) {
    final time = recording.columns[liveRecordingTimeHeader];
    if (time == null) throw const FormatException('The recording has no time column.');
    _paused = true;
    for (var i = 0; i < ids.length; i++) {
      final column = recording.columns[_names[i]] ?? time;
      _start[i] = 0;
      _count[i] = 0;
      for (final (ms, v) in column.skip(column.length > capacity ? column.length - capacity : 0)) {
        _push(_times, _values, _start, _count, i, (ms - _epochFrom0001Ms).toDouble(), v);
      }
      _visible[i] = _count[i];
      if (column.isNotEmpty) _setLatest(i, column.last.$2);
    }
    version++;
  }

  static const _epochFrom0001Ms = 62135596800000;

  void _showUpTo(int i, int idx) {
    if (idx < 0) {
      _visible[i] = 0;
      _setLatest(i, 0);
    } else if (idx != _visible[i] - 1) {
      _visible[i] = idx + 1;
      _setLatest(i, _values[i * capacity + (_start[i] + idx) % capacity]);
    }
  }

  int _i(int id) => _index[id] ?? (throw ArgumentError.value(id, 'id', 'no such link'));

  void _receive(int i, double v, double atMs) {
    if (_paused) {
      _push(_pendingTimes, _pendingValues, _pendingStart, _pendingCount, i, atMs, v);
      return;
    }
    _push(_times, _values, _start, _count, i, atMs, v);
    _visible[i] = _count[i];
    _setLatest(i, v);
  }

  void _push(Float64List times, Float32List values, Int32List start, Int32List count, int i, double atMs, double v) {
    final base = i * capacity;
    final int at;
    if (count[i] < capacity) {
      at = base + (start[i] + count[i]) % capacity;
      count[i]++;
    } else {
      at = base + start[i];
      start[i] = (start[i] + 1) % capacity;
    }
    times[at] = atMs;
    values[at] = v;
  }

  void _setLatest(int i, double v) {
    final old = _latest[i];
    if (!(old == v || (old.isNaN && v.isNaN))) {
      _latest[i] = fround(v);
      _dirty[i] = 1;
    }
  }
}
