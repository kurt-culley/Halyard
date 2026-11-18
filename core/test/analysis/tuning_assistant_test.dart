import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

String _f64(double v) => v.isNaN ? 'NaN' : toHex((ByteData(8)..setFloat64(0, v, Endian.little)).buffer.asUint8List());
double _num(String h) => h == 'NaN' ? double.nan : ByteData.sublistView(fromHex(h)).getFloat64(0, Endian.little);
List<double> _nums(dynamic l) => [for (final h in (l as List<dynamic>).cast<String>()) _num(h)];

TuningTable _table(Map<String, dynamic> t) =>
    TuningTable(t['rows'] as int, t['cols'] as int, _nums(t['x']), _nums(t['y']), _nums(t['out']));

String? _message(TuningResult r) => switch (r.problem) {
  TuningProblem.veNotAMap => 'Select a 2D VE/fuel table first.',
  TuningProblem.noTarget => 'Select a target AFR table first.',
  TuningProblem.stoichOutOfRange => 'Stoich AFR must be a sensible value.',
  TuningProblem.noSamples => 'No valid CSV rows are available for the selected columns.',
  null =>
    '${r.used} samples used, ${r.eligible.isNotEmpty ? '${r.eligible.length} suggestions ready.' : 'but no cells passed the confidence threshold.'}'
        ' Source: x.',
};

Future<void> main() async {
  final v = (await loadVectors('tuning_assistant.json')).first as Map<String, dynamic>;

  test('suggestions match the TypeScript analyser', () {
    for (final (i, c) in (v['cases'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
      final samples = [
        for (final s in (c['samples'] as List<dynamic>).cast<List<dynamic>>())
          LogSample(_num(s[0] as String), _num(s[1] as String), _num(s[2] as String)),
      ];
      final r = analyseTuning(
        TuningSettings(
          ve: _table(c['ve'] as Map<String, dynamic>),
          target: _table(c['target'] as Map<String, dynamic>),
          mode: MeasurementMode.values[c['mode'] as int],
          stoichAfr: (c['stoich'] as num).toDouble(),
          minimumHits: c['minHits'] as int,
          confidenceThreshold: (c['threshold'] as num).toDouble(),
          stabilityTolerancePercent: (c['stability'] as num).toDouble(),
          maxCorrectionPercent: (c['maxCorrection'] as num).toDouble(),
        ),
        samples,
      );
      expect(
        [r.considered, r.used, r.rejected, _message(r)],
        [c['considered'], c['used'], c['rejected'], c['message']],
        reason: 'case $i',
      );
      const notes = {
        SuggestionNote.needsMoreHits: 'Needs more repeated hits',
        SuggestionNote.lowConfidence: 'Low confidence / unstable samples',
        SuggestionNote.ready: 'Ready',
      };
      expect(
        [
          for (final row in r.suggestions)
            for (final g in row)
              [
                g.hitCount,
                _f64(g.weightedHits),
                _f64(g.averageFactor),
                _f64(g.standardDeviation),
                _f64(g.stability),
                _f64(g.confidence),
                _f64(g.suggestedValue),
                _f64(g.unclampedSuggestedValue),
                _f64(g.percentChange),
                _f64(g.averageMeasured),
                _f64(g.averageTarget),
                g.eligible,
                notes[g.note],
              ],
        ],
        c['suggestions'],
        reason: 'case $i',
      );
    }
  });

  test('CSV columns are found by name', () {
    for (final c in (v['columns'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      expect(
        findTuningColumn(
          (c['headers'] as List<dynamic>).cast<String>(),
          (c['candidates'] as List<dynamic>).cast<String?>(),
        ),
        c['index'],
        reason: '${c['headers']} ${c['candidates']}',
      );
    }
  });
}
