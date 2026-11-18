import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

String _f64(double v) => v.isNaN ? 'NaN' : toHex((ByteData(8)..setFloat64(0, v, Endian.little)).buffer.asUint8List());
double _num(String h) => h == 'NaN' ? double.nan : ByteData.sublistView(fromHex(h)).getFloat64(0, Endian.little);

String _warning(CsvWarning w) => switch (w.kind) {
  CsvWarningKind.timeBackwards => 'Time goes backwards at line ${w.line}.',
  CsvWarningKind.columnCount => 'Line ${w.line} has ${w.columns} columns; expected ${w.expected}.',
  CsvWarningKind.noRows => 'No usable data rows were found.',
};

List<Object> _event(LogEvent e) {
  String d(double v) => formatFixed(v, 3, isFloat: false);
  return switch (e.kind) {
    LogEventKind.dropout => [_f64(e.time), 'Dropout', 'Missing or non-numeric value.'],
    LogEventKind.outOfRange => [_f64(e.time), 'Out of range', '${d(e.value)} outside {range}.'],
    LogEventKind.spike => [_f64(e.time), 'Spike', 'Rapid change from ${d(e.previous)} to ${d(e.value)}.'],
    LogEventKind.flatline => [_f64(e.time), 'Flatline', 'Value unchanged for 50 consecutive samples.'],
  };
}

Map<String, Object?> _session(LogSession s) => {
  'channels': [
    for (final c in s.channels) [c.name, c.sourceColumn, c.isMarker, c.displayName],
  ],
  'times': [for (final t in s.samples.times) _f64(t)],
  'values': [
    for (final v in s.samples.values) [for (final x in v) _f64(x)],
  ],
  'markers': [for (final m in s.markers) _f64(m)],
  'warnings': [for (final w in s.warnings) _warning(w)],
};

Future<void> main() async {
  final cases = (await loadVectors('log_review.json')).cast<Map<String, dynamic>>();

  test('CSV logs read into the same sessions (${cases.length} files)', () {
    for (final (i, c) in cases.indexed) {
      expect(_session(csvLogSession('run_$i', c['text'] as String)), c['session'], reason: 'file $i');
    }
  });

  test('statistics, events and differences match the TypeScript model', () {
    for (final (i, c) in cases.indexed) {
      final s = csvLogSession('run_$i', c['text'] as String);
      for (final st in (c['stats'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final r = channelStats(s, st['ch'] as int, _num(st['a'] as String), _num(st['b'] as String));
        expect(
          [r.count, _f64(r.minimum), _f64(r.maximum), _f64(r.average), _f64(r.delta), _f64(r.rateOfChange)],
          [st['count'], st['min'], st['max'], st['avg'], st['delta'], st['roc']],
          reason: 'file $i stats ${st['ch']}',
        );
      }
      for (final ev in (c['events'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final ch = ev['ch'] as int;
        final (min, max) = ((ev['min'] as num).toDouble(), (ev['max'] as num).toDouble());
        s.channels[ch]
          ..minValue = min
          ..maxValue = max;
        final range = '${formatFixed(min, 3)}..${formatFixed(max, 3)}';
        expect(
          [
            for (final e in detectLogEvents(s, ch))
              [for (final x in _event(e)) x is String ? x.replaceFirst('{range}', range) : x],
          ],
          ev['events'],
          reason: 'file $i events $ch',
        );
      }
      final other = csvLogSession('b', c['otherText'] as String);
      final d = differenceSession(s, other, firstSampleAlignment: c['alignment'] == 1);
      final want = c['diff'] as Map<String, dynamic>;
      expect(d.session.channels.map((x) => x.name), want['channels'], reason: 'file $i diff');
      expect(d.session.samples.times.map(_f64), want['times'], reason: 'file $i diff');
      expect([for (final v in d.session.samples.values) v.map(_f64).toList()], want['values'], reason: 'file $i diff');
      expect(
        [
          for (final w in d.warnings)
            switch (w) {
              DifferenceWarning.noMatchingChannels => 'No matching channels were found between the sessions.',
              DifferenceWarning.firstSampleAlignmentOnly =>
                'Initial comparison uses first-sample alignment; advanced alignment modes are reserved in the model.',
            },
        ],
        want['warnings'],
        reason: 'file $i diff',
      );
    }
  });

  test('a file without a header is refused', () {
    expect(() => readCsvLog(' \r\n1,2'), throwsFormatException);
  });
}
