import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

String _trim(double v, int d) {
  var s = formatFixed(v, d, isFloat: false);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s == '-0' ? '0' : s;
}

/// The original's read-out for a selected area.
String _areaText(({int rising, int falling}) e, double a, double b) =>
    'Rising edges : ${e.rising} | Falling edges: ${e.falling} | Start time: ${_trim(a, 5)} s | End time: '
    '${_trim(b, 5)} s | Time Diff: ${_trim((b - a).abs() * 1000, 2)} ms';

/// JavaScript's `String(number)` for the values the vectors hold.
String _js(double v) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v > 0 ? 'Infinity' : '-Infinity';
  if (v == v.truncateToDouble() && v.abs() < 1e21) return v.toInt().toString();
  return v.toString();
}

List<Object> _point(TriggerPoint p) => [_js(p.timestamp), p.syncState, p.simulated, p.values];

Future<void> main() async {
  final cases = (await loadVectors('trigger_log.json')).cast<Map<String, dynamic>>();

  test('trigger logs follow the TypeScript engine (${cases.length} cases)', () {
    for (final (n, c) in cases.indexed) {
      final log = TriggerLog();
      for (final (k, s) in (c['steps'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
        final why = 'case $n step $k (${s['op']})';
        switch (s['op']) {
          case 'state':
            log.applyState(TriggerStateReply(s['status'] as int, true, const [], s['freq'] as int));
          case 'clear':
            log.clear();
          case 'report':
            log.addReport([
              for (final e in (s['entries'] as List<dynamic>).cast<List<dynamic>>())
                TriggerEvent(e[0] as int, e[1] as bool, e[2] as int, e[3] as int),
            ]);
            expect(log.points.length, s['points'], reason: why);
            final tail = log.points.skip(log.points.length < 5 ? 0 : log.points.length - 5);
            expect([for (final p in tail) _point(p)], s['tail'], reason: why);
        }
      }
      final why = 'case $n';
      expect(log.toText(), c['saved'], reason: why);
      final part = c['part'] as List<dynamic>;
      final (from, to) = (double.parse(part[0] as String), double.parse(part[1] as String));
      expect(log.toText(from: from, to: to), part[2], reason: why);
      for (final a in (c['areas'] as List<dynamic>).cast<List<dynamic>>()) {
        final (x, y) = (double.parse(a[1] as String), double.parse(a[2] as String));
        expect(_areaText(edgesBetween(log.points, a[0] as int, x, y), x, y), a[3], reason: why);
      }
      for (final sp in (c['spans'] as List<dynamic>).cast<List<dynamic>>()) {
        final e = edgesAround(log.points, sp[0] as int, double.parse(sp[1] as String));
        final want = sp[2] as List<dynamic>?;
        expect(
          e == null ? null : [_js(e.from), _js(e.to), '${_trim((e.to - e.from) * 1000, 2)} ms'],
          want,
          reason: why,
        );
      }
      final load = c['load'] as Map<String, dynamic>;
      final loaded = TriggerLog();
      if (load['error'] == true) {
        expect(() => loaded.readText(load['text'] as String), throwsFormatException, reason: why);
      } else {
        loaded.readText(load['text'] as String);
        expect(
          [
            for (final p in loaded.points) [_js(p.timestamp), p.syncState, p.simulated, p.values.map(_js).toList()],
          ],
          load['points'],
          reason: why,
        );
      }
      expect(loaded.enabled.values.toList(), load['enabled'], reason: why);
    }
  });
}
