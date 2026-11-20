import 'package:auto_route/auto_route.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'parameters_controller.dart';
import 'strings.dart';

/// Asks for a new value, checks it the original's way, and sends the page when it is made.
Future<void> _edit(BuildContext context, ParametersController c, int index) async {
  final options = c.optionsOf(index);
  final text = TextEditingController(text: c.textOf(index));
  final raw = await showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(c.nameOf(index)),
      content: options != null
          ? SizedBox(
              width: 320,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (v, label) in options)
                    ListTile(title: Text(label), onTap: () => Navigator.of(context).pop(v)),
                ],
              ),
            )
          : TextField(
              controller: text,
              autofocus: true,
              onSubmitted: (t) => Navigator.of(context).pop(c.parse(index, t)),
            ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text(ParametersStrings.cancel)),
        if (options == null)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(c.parse(index, text.text)),
            child: const Text(ParametersStrings.ok),
          ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (raw == null) {
    if (options == null && text.text != c.textOf(index)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(ParametersStrings.notValid)));
    }
    return;
  }
  final check = c.check(index, raw);
  switch (check.verdict) {
    case SettingVerdict.valid:
      await c.send();
    case SettingVerdict.invalid:
      final why = ParametersStrings.problem(check, c.nameOf(index));
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(why.isEmpty ? ParametersStrings.notValid : why),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text(ParametersStrings.ok))],
        ),
      );
    case SettingVerdict.warning || SettingVerdict.needsApproval:
      final duplicates = [for (final i in check.duplicates) c.nameOf(i)];
      final why = check.problem == SettingProblem.duplicate
          ? ParametersStrings.duplicates(duplicates, formatGeneral(check.defaultValue?.$2 ?? 0))
          : ParametersStrings.problem(check, c.nameOf(index));
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(why),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(ParametersStrings.cancel)),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                check.verdict == SettingVerdict.needsApproval
                    ? ParametersStrings.resetOthers
                    : ParametersStrings.setAnyway,
              ),
            ),
          ],
        ),
      );
      if (go ?? false) {
        c.approve(index, raw, check);
        await c.send();
      }
  }
}

@RoutePage()
class ParametersPage extends StatelessWidget {
  const ParametersPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => ParametersController(
      c.read<Session>(),
      c.read<WriteGate>(),
      c.read<SwitchablePolicy>(),
      units: c.read<ValueNotifier<UnitPreferences>>(),
    ),
    child: Consumer<ParametersController>(
      builder: (context, c, _) {
        if (!c.isOnline) return const Center(child: Text(ParametersStrings.notOnline));
        final theme = Theme.of(context);
        final rows = c.rows;
        final links = c.linkChoices;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 260,
              child: ListView(
                children: [
                  for (final (id, name) in c.drivers)
                    ListTile(dense: true, title: Text(name), selected: id == c.selected, onTap: () => c.select(id)),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: c.selected == null
                  ? const Center(child: Text(ParametersStrings.choose))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (!c.canEdit)
                          Text(ParametersStrings.readOnly, style: theme.textTheme.bodySmall)
                        else
                          Row(
                            children: [
                              OutlinedButton(
                                onPressed: () => c.send(store: true),
                                child: const Text(ParametersStrings.store),
                              ),
                              const SizedBox(width: 12),
                              if (c.message != null) Text(c.message!),
                            ],
                          ),
                        for (final (i, r) in rows.indexed) ...[
                          if (i == 0 || rows[i - 1].section != r.section)
                            Padding(
                              padding: const EdgeInsets.only(top: 16, bottom: 4),
                              child: Text(r.section, style: theme.textTheme.titleMedium),
                            ),
                          ListTile(
                            dense: true,
                            enabled: r.enabled,
                            onTap: c.canEdit && r.editable ? () => _edit(context, c, r.index) : null,
                            title: Text(r.name),
                            subtitle: r.enabled
                                ? (r.tip == null ? null : Text(r.tip!))
                                : const Text(ParametersStrings.doesNotApply),
                            trailing: Text(
                              r.unit == null ? r.value : '${r.value} ${r.unit}',
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                        ],
                        if (links.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 4),
                            child: Text(ParametersStrings.links, style: theme.textTheme.titleMedium),
                          ),
                          for (final l in links) ListTile(dense: true, title: Text(l.name), trailing: Text(l.value)),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    ),
  );
}
