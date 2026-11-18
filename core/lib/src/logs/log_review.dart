/// The log reviewer's data (U21b R01 to R07, S01 to S03, L01, A01 to A03): CSV logs read into sessions of sample
/// sets, statistics over a time range, anomalies, and the difference between two sessions. Warnings and events are
/// typed; the app words them.
library;

final _netWs = RegExp(
  '^[\\s\u0085   -     　﻿]+'
  '|[\\s\u0085   -     　﻿]+\$',
);
String _netTrim(String s) => s.replaceAll(_netWs, '');
bool _blank(String? s) => s == null || _netTrim(s).isEmpty;

/// Lines as `TextReader.ReadLine` gives them: CR, LF or CRLF end a line; no empty line after a final line end.
List<String> readTextLines(String text) {
  final out = <String>[];
  var i = 0;
  while (i < text.length) {
    var j = i;
    while (j < text.length && text[j] != '\r' && text[j] != '\n') {
      j++;
    }
    out.add(text.substring(i, j));
    if (j < text.length && text[j] == '\r' && j + 1 < text.length && text[j + 1] == '\n') j++;
    i = j + 1;
  }
  return out;
}

/// Fields of one CSV line: quotes toggle quoting, `""` inside quotes is a quote.
List<String> parseCsvLine(String? line, String delimiter) {
  final out = <String>[];
  final cur = StringBuffer();
  var quoted = false;
  final s = line ?? '';
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '"') {
      if (quoted && i + 1 < s.length && s[i + 1] == '"') {
        cur.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == delimiter && !quoted) {
      out.add(cur.toString());
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  out.add(cur.toString());
  return out;
}

/// The delimiter (comma, semicolon or tab) that splits the header into the most fields; a comma wins ties.
String detectDelimiter(String header) {
  const ds = [',', ';', '\t'];
  var best = ',';
  var most = -1;
  for (final d in ds) {
    final n = parseCsvLine(header, d).length;
    if (n > most || (n == most && d == ',')) {
      best = d;
      most = n;
    }
  }
  return best;
}

final _letterOrDigit = RegExp(r'[\p{L}\p{Nd}]', unicode: true);
String _normalizeHeader(String? v) =>
    [
      for (final r in (v ?? '').runes)
        if (_letterOrDigit.hasMatch(String.fromCharCode(r))) String.fromCharCode(r).toLowerCase(),
    ].join();

int findTimeColumn(List<String> h) {
  for (var i = 0; i < h.length; i++) {
    final n = _normalizeHeader(h[i]);
    if (n == 'time' || n == 'timestamp' || n == 'seconds' || n == 'sec') return i;
  }
  return h.isNotEmpty ? 0 : -1;
}

int findMarkerColumn(List<String> h) {
  for (var i = 0; i < h.length; i++) {
    final n = _normalizeHeader(h[i]);
    if (n == 'marker' || n == 'mark' || n == 'event') return i;
  }
  return -1;
}

final _plainNumber = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$');

/// A log cell as a number; null when it isn't one (an overflow included).
double? tryParseLogNumber(String? value) {
  final t = _netTrim(value ?? '');
  switch (t) {
    case 'Infinity':
      return double.infinity;
    case '-Infinity':
      return double.negativeInfinity;
    case 'NaN':
      return double.nan;
  }
  if (!_plainNumber.hasMatch(t)) return null;
  final v = double.parse(t);
  return v.isFinite ? v : null;
}

enum CsvWarningKind {
  /// [CsvWarning.line] has an earlier time than the line before.
  timeBackwards,

  /// [CsvWarning.line] has [CsvWarning.columns] fields, not [CsvWarning.expected].
  columnCount,
  noRows,
}

final class CsvWarning {
  const CsvWarning(this.kind, {this.line = 0, this.columns = 0, this.expected = 0});
  final CsvWarningKind kind;
  final int line, columns, expected;
}

/// A CSV log's header, rows (NaN for cells that aren't numbers) and warnings.
final class CsvLog {
  CsvLog(this.delimiter, this.headers);
  final String delimiter;
  final List<String> headers;
  final rows = <List<double>>[];
  final warnings = <CsvWarning>[];
}

/// Reads a CSV log. Throws [FormatException] when there is no header row.
CsvLog readCsvLog(String text) {
  final lines = readTextLines(text.startsWith('﻿') ? text.substring(1) : text);
  final first = lines.isEmpty ? null : lines.first;
  if (_blank(first)) throw const FormatException('The CSV file does not contain a header row.');
  final delimiter = detectDelimiter(first!);
  final headers = [
    for (final (i, h) in parseCsvLine(first, delimiter).indexed) _blank(h) ? 'Column ${i + 1}' : _netTrim(h),
  ];
  final r = CsvLog(delimiter, headers);
  final tc = findTimeColumn(headers);
  var prev = double.nan;
  for (var k = 1; k < lines.length; k++) {
    final lineNo = k + 1;
    if (_blank(lines[k])) continue;
    final f = parseCsvLine(lines[k], delimiter);
    final row = [
      for (var i = 0; i < headers.length; i++) (i < f.length ? tryParseLogNumber(f[i]) : null) ?? double.nan,
    ];
    if (tc >= 0 && row[tc].isFinite) {
      if (prev.isFinite && row[tc] < prev) r.warnings.add(CsvWarning(CsvWarningKind.timeBackwards, line: lineNo));
      prev = row[tc];
    }
    if (f.length != headers.length) {
      r.warnings.add(CsvWarning(CsvWarningKind.columnCount, line: lineNo, columns: f.length, expected: headers.length));
    }
    r.rows.add(row);
  }
  if (r.rows.isEmpty) r.warnings.add(const CsvWarning(CsvWarningKind.noRows));
  return r;
}

/// Times in seconds from the first sample, and a value list per channel.
final class LogSampleSet {
  const LogSampleSet(this.times, this.values);
  static const empty = LogSampleSet([], []);
  final List<double> times;
  final List<List<double>> values;
  int get sampleCount => times.length;
  int get channelCount => values.length;

  double value(int ch, int i) =>
      ch < 0 || ch >= channelCount || i < 0 || i >= sampleCount || i >= values[ch].length ? double.nan : values[ch][i];

  /// The sample at [t], else the nearer neighbour (the earlier on a tie); -1 when there are none.
  int nearestIndex(double t) {
    if (sampleCount == 0) return -1;
    var lo = 0, hi = sampleCount - 1;
    while (lo <= hi) {
      final mid = lo + ((hi - lo) >> 1);
      final c = _compare(times[mid], t);
      if (c == 0) return mid;
      if (c < 0) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    final i = lo;
    if (i <= 0) return 0;
    if (i >= sampleCount) return sampleCount - 1;
    final d = (times[i] - t).abs();
    return (times[i - 1] - t).abs() > d ? i : i - 1;
  }

  static int _compare(double x, double y) =>
      x < y ? -1 : (x > y ? 1 : (x == y ? 0 : (x.isNaN ? (y.isNaN ? 0 : -1) : 1)));

  /// Indexes from the sample nearest the earlier time to the one nearest the later, inclusive.
  Iterable<int> range(double start, double end) sync* {
    if (sampleCount == 0) return;
    if (!(end >= start)) {
      (start, end) = (end, start);
    }
    final a = nearestIndex(start) < 0 ? 0 : nearestIndex(start);
    final b = nearestIndex(end) < 0 ? 0 : nearestIndex(end);
    for (var i = a; i <= b && i < sampleCount; i++) {
      yield i;
    }
  }
}

final class LogChannel {
  LogChannel(this.name, {this.sourceColumn = -1, this.isMarker = false, this.unit});
  final String? name, unit;
  final int sourceColumn;
  final bool isMarker;

  /// The range outside which a value is reported; none when they are equal.
  double minValue = 0, maxValue = 0;

  String get displayName => _blank(unit) ? name ?? '' : '${name ?? ''} ($unit)';
}

final class LogSession {
  LogSession(this.name);
  final String? name;
  final channels = <LogChannel>[];

  /// Sample times of the rows whose marker column was set.
  final markers = <double>[];
  final warnings = <CsvWarning>[];
  LogSampleSet samples = LogSampleSet.empty;
}

/// A session from a CSV log: every column but the time is a channel; times start at 0 (row numbers when there is no
/// usable time).
LogSession csvLogSession(String name, String text) {
  final r = readCsvLog(text);
  final tc = findTimeColumn(r.headers), mc = findMarkerColumn(r.headers);
  final s = LogSession(name)..warnings.addAll(r.warnings);
  for (var i = 0; i < r.headers.length; i++) {
    if (i != tc) s.channels.add(LogChannel(r.headers[i], sourceColumn: i, isMarker: i == mc));
  }
  if (r.rows.isEmpty) return s;
  final times = <double>[];
  final values = [for (final _ in s.channels) <double>[]];
  var first = double.nan;
  for (final (k, row) in r.rows.indexed) {
    final t = tc >= 0 && tc < row.length && row[tc].isFinite ? row[tc] : k.toDouble();
    if (!first.isFinite) first = t;
    times.add(t - first);
    for (final (j, c) in s.channels.indexed) {
      values[j].add(c.sourceColumn >= 0 && c.sourceColumn < row.length ? row[c.sourceColumn] : double.nan);
    }
    if (mc >= 0 && mc < row.length && row[mc].isFinite && row[mc].abs() > 5e-324) s.markers.add(times.last);
  }
  s.samples = LogSampleSet(times, values);
  return s;
}

final class ChannelStats {
  const ChannelStats(this.count, this.minimum, this.maximum, this.average, this.delta, this.rateOfChange);
  final int count;
  final double minimum, maximum, average, delta, rateOfChange;
}

/// Statistics of channel [ch] over the samples between [start] and [end]; NaN where there are none.
ChannelStats channelStats(LogSession s, int ch, double start, double end) {
  final ss = s.samples;
  if (ch < 0 || ch >= ss.channelCount) {
    return const ChannelStats(0, double.nan, double.nan, double.nan, double.nan, double.nan);
  }
  var mn = double.maxFinite, mx = -double.maxFinite, sum = 0.0;
  var n = 0;
  var first = double.nan, last = double.nan, t0 = double.nan, t1 = double.nan;
  for (final i in ss.range(start, end)) {
    final v = ss.value(ch, i);
    if (!v.isFinite) continue;
    if (!first.isFinite) {
      (first, t0) = (v, ss.times[i]);
    }
    (last, t1) = (v, ss.times[i]);
    if (v < mn) mn = v;
    if (v > mx) mx = v;
    sum += v;
    n++;
  }
  if (n == 0) return const ChannelStats(0, double.nan, double.nan, double.nan, double.nan, double.nan);
  final delta = last - first;
  final dt = t1 - t0;
  return ChannelStats(n, mn, mx, sum / n, delta, dt.abs() > 5e-324 ? delta / dt : double.nan);
}

enum LogEventKind {
  /// A missing or non-numeric value.
  dropout,

  /// [LogEvent.value] outside the channel's range.
  outOfRange,

  /// A rapid change from [LogEvent.previous] to [LogEvent.value].
  spike,

  /// The value unchanged for 50 samples running.
  flatline,
}

final class LogEvent {
  const LogEvent(this.time, this.kind, {this.value = 0, this.previous = 0});
  final double time, value, previous;
  final LogEventKind kind;
}

/// Anomalies in channel [ch].
List<LogEvent> detectLogEvents(LogSession s, int ch) {
  final out = <LogEvent>[];
  final ss = s.samples;
  if (ch < 0 || ch >= ss.channelCount) return out;
  final c = s.channels[ch];
  var prev = double.nan, prevT = double.nan;
  var flat = 0;
  for (var i = 0; i < ss.sampleCount; i++) {
    final t = ss.times[i], v = ss.value(ch, i);
    if (!v.isFinite) {
      out.add(LogEvent(t, LogEventKind.dropout));
      continue;
    }
    if (c.minValue != c.maxValue && (v < c.minValue || v > c.maxValue)) {
      out.add(LogEvent(t, LogEventKind.outOfRange, value: v));
    }
    if (prev.isFinite) {
      final dt = t - prevT;
      final limit = prev.abs() * 10 > 1000 ? prev.abs() * 10 : 1000;
      if (dt > 0 && (v - prev).abs() / dt > limit) out.add(LogEvent(t, LogEventKind.spike, value: v, previous: prev));
      if ((v - prev).abs() < 1e-6) {
        flat++;
        if (flat == 50) out.add(LogEvent(t, LogEventKind.flatline));
      } else {
        flat = 0;
      }
    }
    (prev, prevT) = (v, t);
  }
  return out;
}

enum DifferenceWarning { noMatchingChannels, firstSampleAlignmentOnly }

/// [compare] minus [baseline] for channels of the same name (ignoring case), aligned on the first sample. Only
/// [onlyNames] when given.
({LogSession session, List<DifferenceWarning> warnings}) differenceSession(
  LogSession baseline,
  LogSession compare, {
  List<String> onlyNames = const [],
  bool firstSampleAlignment = true,
}) {
  final r = LogSession('Difference: ${compare.name ?? ''} vs ${baseline.name ?? ''}');
  final warnings = <DifferenceWarning>[];
  final want = {for (final n in onlyNames) n.toLowerCase()};
  final pairs = <(int, int, LogChannel)>[];
  for (final (j, cc) in compare.channels.indexed) {
    if (want.isNotEmpty &&
        !want.contains((cc.name ?? '\u0000').toLowerCase()) &&
        !want.contains(cc.displayName.toLowerCase())) {
      continue;
    }
    final bi = baseline.channels.indexWhere(
      (b) =>
          (b.name == null && cc.name == null) ||
          (b.name != null && cc.name != null && b.name!.toLowerCase() == cc.name!.toLowerCase()),
    );
    if (bi < 0) continue;
    pairs.add((bi, j, LogChannel('${cc.name ?? ''} delta', unit: cc.unit)));
  }
  if (pairs.isEmpty) return (session: r, warnings: [DifferenceWarning.noMatchingChannels]);
  final b = baseline.samples, c = compare.samples;
  final n = b.sampleCount < c.sampleCount ? b.sampleCount : c.sampleCount;
  r.channels.addAll([for (final p in pairs) p.$3]);
  r.samples = LogSampleSet(c.times.sublist(0, n), [
    for (final (bi, ci, _) in pairs)
      [
        for (var i = 0; i < n; i++)
          c.value(ci, i).isFinite && b.value(bi, i).isFinite ? c.value(ci, i) - b.value(bi, i) : double.nan,
      ],
  ]);
  if (!firstSampleAlignment) warnings.add(DifferenceWarning.firstSampleAlignmentOnly);
  return (session: r, warnings: warnings);
}
