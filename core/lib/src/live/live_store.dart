/// Live values from the ECU's reports: per link, a preallocated ring buffer of (time, value), the latest value, and a
/// staleness flag; for the whole store, one version counter and per-link dirty bits. The app turns the version into one
/// repaint tick per report; instruments read from here directly.
///
/// History follows the original (U11-H01, V01, V02): every report adds a sample to every link. A link the report
/// doesn't mention repeats its latest value, and is marked stale; one mentioned twice gets both. The latest value
/// keeps its stored form when an equal one arrives (0 equals -0, NaN equals NaN); history keeps what arrived.
library;

import 'dart:typed_data';

import '../definition/definition.dart';
import '../wire/bytes.dart' show fround;
import '../wire/messages/reporting.dart';

class LiveStore {
  LiveStore(Definition definition, {this.capacity = defaultCapacity})
    : ids = List.unmodifiable(definition.links.keys),
      _times = Float64List(definition.links.length * capacity),
      _values = Float32List(definition.links.length * capacity),
      _start = Int32List(definition.links.length),
      _count = Int32List(definition.links.length),
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

  final Float64List _times;
  final Float32List _values;
  final Int32List _start, _count;
  final Float32List _latest;
  final Uint8List _stale, _dirty, _reported;

  bool has(int id) => _index.containsKey(id);

  /// The latest value; 0 before any report.
  double value(int id) => _latest[_i(id)];

  /// Not in the latest report (or no report yet).
  bool isStale(int id) => _stale[_i(id)] != 0;

  /// Samples held for [id], at most [capacity].
  int length(int id) => _count[_i(id)];

  /// The [k]th sample of [id], oldest first: (time in ms since the epoch, value).
  (double, double) sample(int id, int k) {
    final i = _i(id);
    RangeError.checkValidIndex(k, null, 'k', _count[i]);
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
      _append(i, fround(e.value.toDouble()), atMs);
      _reported[i] = 1;
    }
    for (var i = 0; i < ids.length; i++) {
      final missing = _reported[i] == 0;
      if (missing) _append(i, _latest[i], atMs);
      _stale[i] = missing ? 1 : 0;
    }
    version++;
  }

  int _i(int id) => _index[id] ?? (throw ArgumentError.value(id, 'id', 'no such link'));

  void _append(int i, double v, double atMs) {
    final base = i * capacity;
    if (_count[i] < capacity) {
      final at = base + (_start[i] + _count[i]) % capacity;
      _times[at] = atMs;
      _values[at] = v;
      _count[i]++;
    } else {
      final at = base + _start[i];
      _times[at] = atMs;
      _values[at] = v;
      _start[i] = (_start[i] + 1) % capacity;
    }
    final old = _latest[i];
    if (!(old == v || (old.isNaN && v.isNaN))) {
      _latest[i] = v;
      _dirty[i] = 1;
    }
  }
}
