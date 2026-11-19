import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'calibration_controller.dart';
import 'strings.dart';

@RoutePage()
class CalibrationPage extends StatelessWidget {
  const CalibrationPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) =>
        CalibrationController(c.read<Session>(), c.read<WriteGate>(), c.read<SwitchablePolicy>(), c.read<FileSaver>()),
    child: const _CalibrationView(),
  );
}

class _CalibrationView extends StatelessWidget {
  const _CalibrationView();

  Future<void> _open(CalibrationController c) async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: CalibrationStrings.fileType, extensions: [calibrationFileExtension]),
      ],
    );
    if (f != null) c.open(f.name, await f.readAsString());
  }

  Future<void> _send(BuildContext context, CalibrationController c) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(CalibrationStrings.sendTitle),
        content: const Text(CalibrationStrings.sendQuestion),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(CalibrationStrings.no)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text(CalibrationStrings.yes)),
        ],
      ),
    );
    if (yes ?? false) await c.send();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CalibrationController>();
    final theme = Theme.of(context);
    if (!c.isOnline) return const Center(child: Text(CalibrationStrings.notOnline));
    final a = c.analysis;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(CalibrationStrings.save, style: theme.textTheme.titleLarge),
        Text(CalibrationStrings.saveHint, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        SizedBox(
          width: 640,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 640,
              child: TextFormField(
                initialValue: c.notes,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: CalibrationStrings.notes,
                  helperText: CalibrationStrings.notesHint,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => c.notes = v,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              onPressed: c.save,
              icon: const Icon(Icons.save_alt),
              label: const Text(CalibrationStrings.saveButton),
            ),
            const SizedBox(width: 12),
            if (c.message != null && a == null) Text(c.message!),
          ],
        ),
        const SizedBox(height: 32),
        Text(CalibrationStrings.load, style: theme.textTheme.titleLarge),
        Text(CalibrationStrings.loadHint, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => _open(c),
              icon: const Icon(Icons.folder_open),
              label: const Text(CalibrationStrings.open),
            ),
            if (a != null) ...[const SizedBox(width: 8), IconButton(onPressed: c.close, icon: const Icon(Icons.close))],
          ],
        ),
        if (a != null) ...[const SizedBox(height: 16), _Review(c, a, onSend: () => _send(context, c))],
      ],
    );
  }
}

class _Review extends StatelessWidget {
  const _Review(this.c, this.a, {required this.onSend});
  final CalibrationController c;
  final ImportAnalysis a;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = c.visible;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              CalibrationStrings.files(c.fileName ?? '', a.sourceInfo, a.targetInfo),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: a.hasDefinitionMismatch ? scheme.tertiaryContainer : scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(a.hasDefinitionMismatch ? Icons.warning_amber : Icons.info_outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      a.hasDefinitionMismatch ? CalibrationStrings.otherDefinition : CalibrationStrings.sameDefinition,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<ReviewFilter>(
                  segments: const [
                    ButtonSegment(value: ReviewFilter.all, label: Text(CalibrationStrings.all)),
                    ButtonSegment(value: ReviewFilter.drivers, label: Text(CalibrationStrings.drivers)),
                    ButtonSegment(value: ReviewFilter.tables, label: Text(CalibrationStrings.tables)),
                    ButtonSegment(value: ReviewFilter.attention, label: Text(CalibrationStrings.attention)),
                  ],
                  selected: {c.filter},
                  onSelectionChanged: (s) => c.setFilter(s.first),
                ),
                FilterChip(
                  label: const Text(CalibrationStrings.showUnchanged),
                  selected: c.showUnchanged,
                  onSelected: c.setShowUnchanged,
                ),
                TextButton(onPressed: () => c.checkAll(true), child: const Text(CalibrationStrings.selectAll)),
                TextButton(onPressed: () => c.checkAll(false), child: const Text(CalibrationStrings.selectNone)),
              ],
            ),
            const SizedBox(height: 8),
            if (visible.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text(CalibrationStrings.nothing))
            else
              for (final i in visible) ..._item(context, i),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(child: Text(c.summary, style: theme.textTheme.bodyMedium)),
                if (c.message != null) ...[Text(c.message!), const SizedBox(width: 12)],
                if (!c.canSend) ...[
                  Text(CalibrationStrings.readOnly, style: TextStyle(color: scheme.error)),
                  const SizedBox(width: 12),
                ],
                if (c.busy) const Padding(padding: EdgeInsets.only(right: 12), child: CircularProgressIndicator()),
                FilledButton.icon(
                  onPressed: c.canSend && c.checkedCount > 0 && !c.busy ? onSend : null,
                  icon: const Icon(Icons.upload),
                  label: Text(CalibrationStrings.apply(c.checkedCount)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _item(BuildContext context, ReviewItem i) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final open = c.expanded.contains(i.id);
    return [
      ListTile(
        dense: true,
        leading: Checkbox(value: i.checked, onChanged: i.selectable ? (v) => c.check(i, v ?? false) : null),
        title: Text(i.name),
        subtitle: Text(i.isTable ? CalibrationStrings.tables : CalibrationStrings.drivers),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i.needsAttention) Icon(Icons.warning_amber, color: scheme.error, size: 18),
            const SizedBox(width: 6),
            Chip(label: Text(i.badge), visualDensity: VisualDensity.compact),
            if (!i.isTable && i.candidates.length > 1)
              IconButton(
                onPressed: () => c.toggleExpanded(i.id),
                icon: Icon(open ? Icons.expand_less : Icons.expand_more),
              ),
          ],
        ),
        onTap: !i.isTable && i.candidates.length > 1 ? () => c.toggleExpanded(i.id) : null,
      ),
      if (i.isTable && i.table != null)
        Padding(
          padding: const EdgeInsets.only(left: 72, bottom: 4),
          child: Text(c.tableDetail(i.table!), style: theme.textTheme.bodySmall),
        ),
      if (open)
        for (final cand in i.candidates.where((x) => x.isChanged || !x.importable))
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: cand.selected && cand.importable,
              onChanged: cand.importable && cand.isChanged ? (_) => c.toggleCandidate(cand) : null,
              title: Text(c.candidateName(cand)),
              subtitle: Text(c.reason(cand)),
            ),
          ),
    ];
  }
}
