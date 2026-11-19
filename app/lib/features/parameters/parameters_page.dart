import 'package:auto_route/auto_route.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'parameters_controller.dart';
import 'strings.dart';

@RoutePage()
class ParametersPage extends StatelessWidget {
  const ParametersPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => ParametersController(c.read<Session>()),
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
                        Text(ParametersStrings.readOnly, style: theme.textTheme.bodySmall),
                        for (final (i, r) in rows.indexed) ...[
                          if (i == 0 || rows[i - 1].section != r.section)
                            Padding(
                              padding: const EdgeInsets.only(top: 16, bottom: 4),
                              child: Text(r.section, style: theme.textTheme.titleMedium),
                            ),
                          ListTile(
                            dense: true,
                            enabled: r.enabled,
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
