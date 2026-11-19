import 'package:auto_route/auto_route.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../instruments/readout.dart';
import 'live_controller.dart';
import 'live_dial.dart';
import 'strings.dart';

@RoutePage()
class LivePage extends StatelessWidget {
  const LivePage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => LiveController(c.read<Session>(), c.read<AppStorage>()),
    child: Consumer<LiveController>(
      builder: (context, c, _) {
        if (!c.isOnline) return const Center(child: Text(LiveStrings.notOnline));
        final session = context.read<Session>();
        final dials = c.dials;
        final rows = c.rows;
        final theme = Theme.of(context);
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: dials.isEmpty
                    ? Text(LiveStrings.dialsHint, style: theme.textTheme.bodyMedium)
                    : LayoutBuilder(
                        builder: (context, box) {
                          final size = (box.maxWidth / dials.length.clamp(3, 6) - 12).clamp(140.0, 240.0);
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final id in dials)
                                SizedBox(
                                  width: size,
                                  height: size,
                                  child: LiveDial(key: ValueKey(id), session: session, id: id),
                                ),
                            ],
                          );
                        },
                      ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  width: 320,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 320,
                      child: TextField(
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search),
                          hintText: LiveStrings.find,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: c.setFilter,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid.extent(
                maxCrossAxisExtent: 240,
                childAspectRatio: 1.45,
                children: [
                  for (final r in rows)
                    Readout(
                      label: r.label,
                      unit: r.unit,
                      value: r.value,
                      stale: r.stale,
                      alarm: r.alarm,
                      history: r.history,
                      fraction: r.fraction,
                      action: IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        tooltip: r.pinned ? LiveStrings.unpin : LiveStrings.pin,
                        onPressed: () => c.togglePin(r.id),
                        icon: Icon(r.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
