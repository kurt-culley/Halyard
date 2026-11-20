import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

Future<void> main() async {
  final v = (await loadVectors('custom_can_dbc.json')).single as Map<String, dynamic>;

  test('DBC imports fill the same message slots, notes and summary as the original', () async {
    final imports = v['imports'] as List<dynamic>;
    expect(imports, isNotEmpty);
    for (final (n, raw) in imports.indexed) {
      final c = raw as Map<String, dynamic>;
      final messages = parseDbc(c['text'] as String);
      final selection = [
        for (final s in c['selection'] as List<dynamic>)
          (
            messages[(s as List<dynamic>)[0] as int],
            [for (final k in s[1] as List<dynamic>) messages[s[0] as int].signals[k as int]],
          ),
      ];
      final config = CustomCanConfig.decode(fromHex(c['before'] as String));
      final answers = (c['answers'] as List<dynamic>).cast<bool>().iterator;
      Future<bool> ask(String text, String title) async => answers.moveNext() && answers.current;
      final reserved = {for (final r in c['reserved'] as List<dynamic>) r as int};
      final r =
          c['tx'] as bool
              ? await importTx(config, selection, ask: ask, reserved: reserved)
              : await importRx(config, selection, ask: ask, reserved: reserved);
      expect(toHex(config.encode()), c['after'], reason: 'case $n');
      expect((r.added, r.skipped), (c['added'], c['skipped']), reason: 'case $n');
      expect(r.notes, c['notes'], reason: 'case $n');
      expect(dbcImportSummary(r), c['summary'], reason: 'case $n');
    }
  });

  test('DBC exports match the original text', () {
    for (final (n, raw) in (v['exports'] as List<dynamic>).indexed) {
      final c = raw as Map<String, dynamic>;
      final config = CustomCanConfig.decode(fromHex(c['config'] as String));
      final names = (c['linkNames'] as Map<String, dynamic>).map((k, v) => MapEntry(int.parse(k), v as String?));
      expect(exportRxDbc(config.rx, (id) => names[id]), c['rx'], reason: 'case $n');
      expect(exportTxDbc(config.tx, (id) => names[id]), c['tx'], reason: 'case $n');
    }
  });
}
