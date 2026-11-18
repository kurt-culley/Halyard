import 'dart:convert';
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

String? _bits(double? v) =>
    v == null ? null : toHex((ByteData(4)..setFloat32(0, v, Endian.little)).buffer.asUint8List());

/// The TypeScript project's wording, to compare typed reasons with its vectors.
String _reason(ImportCandidate c, Calibration source) {
  String changes() {
    final parts = [
      if (c.changedCells > 0) '${c.changedCells}${c.changedCells == 1 ? ' cell differs' : ' cells differ'}',
      if (c.changedAxis > 0)
        '${c.changedAxis}${c.changedAxis == 1 ? ' axis breakpoint moved' : ' axis breakpoints moved'}',
      if (c.enabledChanged) 'enabled state differs',
    ];
    return parts.join(' · ');
  }

  String usedName() {
    final p = source.definition.drivers[c.sourceId]!.params[c.sourceIndex];
    return p.displayName == null || p.displayName!.isEmpty ? p.name ?? '' : p.displayName!;
  }

  return switch (c.reason) {
    CandidateReason.calibrationMissing => 'Calibration or target DEF is missing.',
    CandidateReason.missingDriver => 'Missing driver',
    CandidateReason.exactParameter => 'Exact parameter match',
    CandidateReason.reorderedParameter => 'Same parameter at a different position',
    CandidateReason.seededParameter => 'taken from ${usedName()}',
    CandidateReason.parameterNotInFile => 'Not in file, keeps current value',
    CandidateReason.fixedLinkDiffers => 'Fixed connection, differs in file',
    CandidateReason.linkImportable => 'Can be imported',
    CandidateReason.linkUnavailable => 'Input not available on this firmware',
    CandidateReason.missingTable => 'Missing table',
    CandidateReason.condensed => '16 points reduced to first and last',
    CandidateReason.expanded => '2 points spread over 16 (straight line)',
    CandidateReason.rescaled => '16x16 interpolated to 8x8',
    CandidateReason.sameShape => c.isChanged ? changes() : 'Identical values',
    CandidateReason.differentSize => 'Different table size',
  };
}

Map<String, Object?> _fields(ImportCandidate c, Calibration source) => {
  'kind': c.kind.index,
  'matchType': c.matchType.index,
  'importable': c.importable,
  'selected': c.selected,
  'safeDefault': c.safeDefault,
  'changed': c.isChanged,
  'targetId': c.targetId,
  'sourceId': c.sourceId,
  'targetIndex': c.targetIndex,
  'sourceIndex': c.sourceIndex,
  'delta': _bits(c.valueDelta),
  'cells': c.changedCells,
  'axis': c.changedAxis,
  'minDelta': _bits(c.minCellDelta),
  'maxDelta': _bits(c.maxCellDelta),
  'enabledChanged': c.enabledChanged,
  'reason': _reason(c, source),
};

Map<String, Object?> _state(Calibration c) => {
  'tables': [
    for (final t in c.definition.tables.values) [t.id, toHex(tableBlob(t, c.tables[t.id]!))],
  ],
  'drivers': [
    for (final d in c.definition.drivers.values) [d.id, toHex(driverBlob(d, c.drivers[d.id]!))],
  ],
};

Future<void> main() async {
  final cases = (await loadVectors('calibration_import.json')).cast<Map<String, dynamic>>();

  test('the analysis finds the same candidates as the TypeScript service (${cases.length} cases)', () {
    for (final (i, v) in cases.indexed) {
      final target = readDeviceFile(v['targetXml'] as String).calibration;
      final source = readDeviceFile(v['sourceXml'] as String).calibration;
      final a = analyseImport(target, source);
      expect(a.hasDefinitionMismatch, v['defMismatch'], reason: 'case $i');
      // Order is presentation (the app sorts); compare as sorted lists of field maps, before any toggling.
      final want = [
        for (final c in (v['candidates'] as List<dynamic>).cast<Map<String, dynamic>>())
          jsonEncode({...c, 'selected': c['safeDefault']}),
      ]..sort();
      final got = [for (final c in a.candidates) jsonEncode(_fields(c, source))]..sort();
      expect(got, want, reason: 'case $i');
    }
  });

  test('applying the selection gives the same target', () {
    for (final (i, v) in cases.indexed) {
      final target = readDeviceFile(v['targetXml'] as String).calibration;
      final source = readDeviceFile(v['sourceXml'] as String).calibration;
      final a = analyseImport(target, source);
      // Select exactly what the TypeScript run selected: match candidates by their identifying fields.
      final chosen = <String, int>{};
      for (final c in (v['candidates'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        if (c['selected'] == true) {
          final k = '${c['kind']}/${c['targetId']}/${c['targetIndex']}';
          chosen[k] = (chosen[k] ?? 0) + 1;
        }
      }
      for (final c in a.candidates) {
        final k = '${c.kind.index}/${c.targetId}/${c.targetIndex}';
        c.selected = (chosen[k] ?? 0) > 0;
        if (c.selected) chosen[k] = chosen[k]! - 1;
      }
      expect(_state(applyImport(target, source, a.candidates)), v['applied'], reason: 'case $i');
    }
  });

  test('a file applied onto the target definition', () {
    for (final (i, v) in cases.indexed) {
      final target = readDeviceFile(v['targetXml'] as String).calibration;
      final source = readDeviceFile(v['sourceXml'] as String).calibration;
      expect(_state(applyCalibrationFile(target, source)), v['onto'], reason: 'case $i');
    }
  });

  test('items without a category are analysed (docs/behaviour-changes.md)', () {
    final xml = (cases.first['targetXml'] as String).replaceAll(RegExp('<category>[^<]*</category>'), '');
    final c = readDeviceFile(xml).calibration;
    expect(analyseImport(c, c).candidates, isNotEmpty);
  });

  test('a driver of another shape in the file keeps the definition\'s values (docs/behaviour-changes.md)', () {
    for (final v in cases) {
      final target = readDeviceFile(v['targetXml'] as String).calibration;
      final source = readDeviceFile(v['sourceXml'] as String).calibration;
      for (final d in target.definition.drivers.values) {
        final s = source.definition.drivers[d.id];
        if (s == null || s.configCount == d.configCount) continue;
        final onto = applyCalibrationFile(target, source);
        expect(driverBlob(d, onto.drivers[d.id]!), driverBlob(d, target.drivers[d.id]!));
        return;
      }
    }
    fail('no case with a reshaped driver');
  });

  test('without a target or a source there is one warning', () {
    final a = analyseImport(null, null);
    expect(a.candidates.single.reason, CandidateReason.calibrationMissing);
    expect(a.candidates.single.importable, isFalse);
  });

  test('spreading and interpolation', () {
    expect(spreadAxis([0, 99, 10], 6), [0, 2, 4, 6, 8, 10]);
    expect(findSegment([0, 10, 20], 15), (lo: 1, hi: 2, t: 0.5));
    expect(findSegment([20, 10, 0], 25), (lo: 0, hi: 0, t: 0.0));
    expect(sampleBilinear([0, 10], [0, 10], [0, 10, 20, 30], 2, 5, 5), 15);
  });
}
