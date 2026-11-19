import 'package:auto_route/auto_route.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'faults_controller.dart';
import 'strings.dart';

@RoutePage()
class FaultsPage extends StatelessWidget {
  const FaultsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider(create: (c) => FaultsController(c.read<Session>()), child: const _FaultsView());
}

class _FaultsView extends StatelessWidget {
  const _FaultsView();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FaultsController>();
    final theme = Theme.of(context);
    if (!c.isOnline) return const Center(child: Text(FaultsStrings.notOnline));
    final codes = c.codes;
    final records = c.records;
    final info = c.info;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              onPressed: c.busy ? null : c.read,
              child: Text(c.busy ? FaultsStrings.reading : FaultsStrings.read),
            ),
            OutlinedButton(
              onPressed: c.busy || c.hasLog != true ? null : () => c.read(history: true),
              child: const Text(FaultsStrings.history),
            ),
            if (info != null) Text(FaultsStrings.usage(info.logUsed, info.logCapacity)),
          ],
        ),
        const SizedBox(height: 4),
        Text(FaultsStrings.readOnly, style: theme.textTheme.bodySmall),
        if (c.error != null) Text(c.error!, style: TextStyle(color: theme.colorScheme.error)),
        if (c.hasLog == false) const Padding(padding: EdgeInsets.only(top: 16), child: Text(FaultsStrings.noLog)),
        if (c.hasLog == true) ...[
          const SizedBox(height: 24),
          Text(FaultsStrings.summary, style: theme.textTheme.titleMedium),
          if (codes.isEmpty)
            const Text(FaultsStrings.noCodes)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [for (final h in FaultsStrings.columns) DataColumn(label: Text(h))],
                rows: [
                  for (final r in codes)
                    DataRow(
                      cells: [
                        DataCell(Text('${r.code}')),
                        DataCell(Text(r.name)),
                        DataCell(Text(r.severity)),
                        DataCell(
                          Text(
                            r.state,
                            style: r.active
                                ? TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)
                                : null,
                          ),
                        ),
                        DataCell(Text('${r.count}')),
                        DataCell(Text('${r.lifetime}')),
                        DataCell(Text(r.last)),
                      ],
                    ),
                ],
              ),
            ),
          if (records.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(FaultsStrings.records, style: theme.textTheme.titleMedium),
            for (final r in records)
              ListTile(
                dense: true,
                title: Text(r.code.isEmpty ? r.type : r.code),
                subtitle: Text('${r.type}  ·  ${r.when}'),
              ),
          ],
        ],
      ],
    );
  }
}
