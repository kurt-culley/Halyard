import 'package:auto_route/auto_route.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../instruments/map_grid.dart';
import 'strings.dart';
import 'tables_controller.dart';

@RoutePage()
class TablesPage extends StatelessWidget {
  const TablesPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => TablesController(c.read<Session>()),
    child: Consumer<TablesController>(
      builder: (context, c, _) {
        if (!c.isOnline) return const Center(child: Text(TablesStrings.notOnline));
        final theme = Theme.of(context);
        final tables = c.tables;
        final view = c.view;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 260,
              child: ListView(
                children: [
                  for (final (i, t) in tables.indexed) ...[
                    if (i == 0 || tables[i - 1].category != t.category)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(t.category, style: theme.textTheme.labelLarge),
                      ),
                    ListTile(
                      dense: true,
                      title: Text(t.name),
                      selected: t.id == c.selected,
                      onTap: () => c.select(t.id),
                    ),
                  ],
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: view == null
                  ? const Center(child: Text(TablesStrings.choose))
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(view.name, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text(
                            [
                              TablesStrings.axes(view.across, view.down),
                              if (!view.enabled) TablesStrings.disabled,
                              TablesStrings.readOnly,
                            ].where((s) => s.isNotEmpty).join('   ·   '),
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: MapGrid(
                              columns: view.columns,
                              rows: view.rows,
                              cells: view.cells,
                              shades: view.shades,
                              live: view.live,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    ),
  );
}
