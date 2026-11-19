import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../instruments/map_grid.dart';
import 'strings.dart';
import 'tuning_controller.dart';

@RoutePage()
class TuningPage extends StatelessWidget {
  const TuningPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => TuningController(c.read<Session>(), c.read<WriteGate>(), c.read<SwitchablePolicy>()),
    child: const _TuningView(),
  );
}

class _TuningView extends StatelessWidget {
  const _TuningView();

  Future<void> _openCsv(TuningController c) async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: TuningStrings.csvType, extensions: ['csv']),
      ],
    );
    if (f != null) c.openCsv(f.name, await f.readAsString());
  }

  Future<void> _apply(BuildContext context, TuningController c, List<TuningSuggestion> items) async {
    if (items.isEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(TuningStrings.title),
        content: Text(TuningStrings.applyPrompt(items.length)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(TuningStrings.no)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text(TuningStrings.yes)),
        ],
      ),
    );
    if (yes ?? false) await c.apply(items);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TuningController>();
    if (!c.isOnline) return const Center(child: Text(TuningStrings.notOnline));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 340, child: _Settings(c, onOpenCsv: () => _openCsv(c))),
        const VerticalDivider(width: 1),
        Expanded(child: _Results(c, onApply: (items) => _apply(context, c, items))),
      ],
    );
  }
}

class _Settings extends StatelessWidget {
  const _Settings(this.c, {required this.onOpenCsv});
  final TuningController c;
  final VoidCallback onOpenCsv;

  Widget _pick(String label, int? value, List<Choice> items, void Function(int?) onChanged) =>
      DropdownButtonFormField<int>(
        initialValue: items.any((i) => i.id == value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          for (final i in items)
            DropdownMenuItem(
              value: i.id,
              child: Text(i.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      );

  Widget _slider(String label, double value, double min, double max, String unit, void Function(double) on) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label: ${value.round()}$unit'),
      Slider(value: value, min: min, max: max, divisions: (max - min).round(), onChanged: on),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final columns = [for (final (i, h) in c.columns.indexed) (id: i, name: h)];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(TuningStrings.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(TuningStrings.intro, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        _pick(TuningStrings.veTable, c.ve, c.maps, (v) => c.update((c) => c.ve = v)),
        const SizedBox(height: 8),
        _pick(TuningStrings.targetTable, c.target, c.maps, (v) => c.update((c) => c.target = v)),
        const SizedBox(height: 16),
        Text(TuningStrings.source, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        SegmentedButton<bool>(
          segments: [
            const ButtonSegment(value: false, label: Text(TuningStrings.live)),
            ButtonSegment(value: true, label: const Text(TuningStrings.csv), enabled: c.csvLog != null),
          ],
          selected: {c.useCsv},
          onSelectionChanged: (s) => c.update((c) => c.useCsv = s.first),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onOpenCsv,
          icon: const Icon(Icons.folder_open),
          label: Text(c.csvName ?? TuningStrings.openCsv),
        ),
        const SizedBox(height: 8),
        if (c.useCsv) ...[
          _pick(TuningStrings.rpm, c.csvRpm, columns, (v) => c.update((c) => c.csvRpm = v ?? -1)),
          const SizedBox(height: 8),
          _pick(TuningStrings.load, c.csvLoad, columns, (v) => c.update((c) => c.csvLoad = v ?? -1)),
          const SizedBox(height: 8),
          _pick(TuningStrings.measured, c.csvMeasured, columns, (v) => c.update((c) => c.csvMeasured = v ?? -1)),
        ] else ...[
          _pick(TuningStrings.rpm, c.rpm, c.links, (v) => c.update((c) => c.rpm = v)),
          const SizedBox(height: 8),
          _pick(TuningStrings.load, c.load, c.links, (v) => c.update((c) => c.load = v)),
          const SizedBox(height: 8),
          _pick(TuningStrings.measured, c.measured, c.links, (v) => c.update((c) => c.measured = v)),
        ],
        const SizedBox(height: 16),
        Text(TuningStrings.mode, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        SegmentedButton<MeasurementMode>(
          segments: const [
            ButtonSegment(value: MeasurementMode.afr, label: Text(TuningStrings.afr)),
            ButtonSegment(value: MeasurementMode.lambda, label: Text(TuningStrings.lambda)),
          ],
          selected: {c.mode},
          onSelectionChanged: (s) => c.update((c) => c.mode = s.first),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: c.stoich.toString(),
          decoration: const InputDecoration(labelText: TuningStrings.stoich, isDense: true),
          onChanged: (v) => c.update((c) => c.stoich = double.tryParse(v) ?? c.stoich),
        ),
        const SizedBox(height: 16),
        _slider(TuningStrings.minHits, c.minHits.toDouble(), 1, 20, '', (v) => c.update((c) => c.minHits = v.round())),
        _slider(TuningStrings.confidence, c.confidence, 0, 100, '%', (v) => c.update((c) => c.confidence = v)),
        _slider(TuningStrings.stability, c.stability, 1, 50, '%', (v) => c.update((c) => c.stability = v)),
        _slider(TuningStrings.maxChange, c.maxChange, 1, 50, '%', (v) => c.update((c) => c.maxChange = v)),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: c.analyse,
          icon: const Icon(Icons.auto_graph),
          label: const Text(TuningStrings.analyse),
        ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results(this.c, {required this.onApply});
  final TuningController c;
  final void Function(List<TuningSuggestion>) onApply;

  /// The original's shading: towards green to add fuel, red to remove, by the change and its confidence.
  static Color? _colour(TuningSuggestion s, ColorScheme scheme) {
    if (!(s.weightedHits > 0.01)) return null;
    final amt = ((s.percentChange.abs() / 10).clamp(0.0, 1.0) * (s.confidence < 0.18 ? 0.18 : s.confidence)).clamp(
      0.0,
      1.0,
    );
    final to = s.percentChange < 0 ? const Color(0xFFD6444E) : const Color(0xFF00AA82);
    return Color.lerp(scheme.surfaceContainerHigh, to, amt);
  }

  static String _signed(double v, int places) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(places)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = c.result;
    final cal = context.read<Session>().calibration;
    final v = c.ve == null ? null : cal?.tables[c.ve];
    final s = c.selected;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: c.analyse,
                icon: const Icon(Icons.auto_graph),
                label: const Text(TuningStrings.analyse),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(c.status, style: theme.textTheme.bodyMedium)),
            ],
          ),
          if (r != null) ...[
            const SizedBox(height: 4),
            Text(TuningStrings.counts(r.considered, r.used, r.rejected), style: theme.textTheme.bodySmall),
            Text(TuningStrings.legend, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          if (r != null && v != null && r.suggestions.isNotEmpty) ...[
            Expanded(
              child: MapGrid(
                columns: [for (final x in v.x) formatDecimals(x, 0, 1)],
                rows: [for (final y in v.y) formatDecimals(y, 0, 1)],
                cells: [
                  for (final row in r.suggestions)
                    for (final t in row) t.weightedHits > 0.01 ? '${_signed(t.percentChange, 0)}%' : '',
                ],
                shades: [
                  for (final row in r.suggestions)
                    for (final _ in row) 0.5,
                ],
                colours: [
                  for (final row in r.suggestions)
                    for (final t in row) _colour(t, scheme),
                ],
                tuned: {
                  for (final row in r.suggestions)
                    for (final t in row)
                      if (t.eligible) t.row * v.x.length + t.col,
                },
                selected: {if (c.cell case final cell?) (cell.$1 + 1, cell.$2 + 1)},
                onPress: (cell, _) {
                  if (cell.$1 > 0 && cell.$2 > 0) c.select(cell.$1 - 1, cell.$2 - 1);
                },
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: s == null
                    ? const Text(TuningStrings.detailIntro)
                    : Wrap(
                        spacing: 24,
                        runSpacing: 4,
                        children: [
                          Text('Cell R${s.row} C${s.col}', style: theme.textTheme.titleSmall),
                          Text('Current VE: ${s.currentValue.toStringAsFixed(3)}'),
                          Text('Suggested VE: ${s.suggestedValue.toStringAsFixed(3)}'),
                          Text('Change: ${_signed(s.percentChange, 1)}%'),
                          Text('Hits: ${s.hitCount}'),
                          Text('Weighted hits: ${s.weightedHits.toStringAsFixed(1)}'),
                          Text('Confidence: ${(s.confidence * 100).round()}%'),
                          Text('Stability: ${(s.stability * 100).round()}%'),
                          Text('Measured: ${s.averageMeasured.toStringAsFixed(3)}'),
                          Text('Target: ${s.averageTarget.toStringAsFixed(3)}'),
                          Text('Status: ${TuningStrings.note(s.note)}'),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (!c.canApply)
                  Expanded(
                    child: Text(TuningStrings.readOnly, style: TextStyle(color: scheme.error)),
                  ),
                if (c.canApply) const Spacer(),
                OutlinedButton(
                  onPressed: c.canApply && c.selectedForApply.isNotEmpty ? () => onApply(c.selectedForApply) : null,
                  child: const Text(TuningStrings.applySelected),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: c.canApply && r.eligible.isNotEmpty ? () => onApply(r.eligible) : null,
                  child: const Text(TuningStrings.applyHigh),
                ),
              ],
            ),
          ] else
            const Expanded(child: Center(child: Text(TuningStrings.detailIntro))),
        ],
      ),
    );
  }
}
