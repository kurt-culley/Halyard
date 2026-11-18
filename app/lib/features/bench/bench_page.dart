import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'bench_controller.dart';
import 'strings.dart';

@RoutePage()
class BenchPage extends StatelessWidget {
  const BenchPage({super.key});

  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider(create: (c) => BenchController(c.read<Session>()), child: const _BenchView());
}

const _icons = {
  BenchStatus.pass: Icons.check_circle,
  BenchStatus.fail: Icons.error,
  BenchStatus.skip: Icons.remove_circle,
};

class _BenchView extends StatelessWidget {
  const _BenchView();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BenchController>();
    final theme = Theme.of(context);
    final report = c.report;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(BenchStrings.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(BenchStrings.hint, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton(
              onPressed: c.running || !c.isOnline ? null : c.run,
              child: Text(c.running ? BenchStrings.running : BenchStrings.run),
            ),
            const SizedBox(width: 12),
            if (report != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text(BenchStrings.copyReport),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: report));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(BenchStrings.copied)));
                  }
                },
              ),
            if (!c.isOnline) ...[const SizedBox(width: 12), const Text(BenchStrings.notOnline)],
          ],
        ),
        const SizedBox(height: 12),
        for (final r in c.results)
          ListTile(
            leading: Icon(_icons[r.status], color: r.status == BenchStatus.fail ? theme.colorScheme.error : null),
            title: Text(r.check.title),
            subtitle: Text(r.details.entries.map((e) => '${e.key}: ${e.value}').join('   ')),
            trailing: Text('${r.took.inMilliseconds} ms'),
          ),
      ],
    );
  }
}
