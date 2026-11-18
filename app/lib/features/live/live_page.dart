import 'package:auto_route/auto_route.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../instruments/readout.dart';
import 'live_controller.dart';
import 'strings.dart';

@RoutePage()
class LivePage extends StatelessWidget {
  const LivePage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => LiveController(c.read<Session>()),
    child: Consumer<LiveController>(
      builder: (context, c, _) {
        if (!c.isOnline) return const Center(child: Text(LiveStrings.notOnline));
        final rows = c.rows;
        return GridView.extent(
          maxCrossAxisExtent: 220,
          childAspectRatio: 2.2,
          padding: const EdgeInsets.all(16),
          children: [
            for (final r in rows) Readout(label: r.label, unit: r.unit, value: r.value, stale: r.stale, alarm: r.alarm),
          ],
        );
      },
    ),
  );
}
