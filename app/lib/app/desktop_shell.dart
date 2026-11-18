import 'package:auto_route/auto_route.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'desktop_router.dart';

/// The desktop frame: a navigation rail beside the current page, and a status bar with the link and session state.
@RoutePage()
class DesktopShellPage extends StatelessWidget {
  const DesktopShellPage({super.key});

  @override
  Widget build(BuildContext context) => AutoTabsRouter(
    routes: const [ConnectRoute(), LiveRoute(), BenchRoute()],
    builder: (context, child) {
      final tabs = AutoTabsRouter.of(context);
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: tabs.activeIndex,
              onDestinationSelected: tabs.setActiveIndex,
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.cable), label: Text('Connect')),
                NavigationRailDestination(icon: Icon(Icons.speed), label: Text('Live')),
                NavigationRailDestination(icon: Icon(Icons.fact_check), label: Text('Bench test')),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
        bottomNavigationBar: const _StatusBar(),
      );
    },
  );
}

const _phaseText = {
  SessionPhase.offline: 'Offline',
  SessionPhase.connecting: 'Connecting',
  SessionPhase.identifying: 'Identifying the ECU',
  SessionPhase.loadingDefinition: 'Loading the definition',
  SessionPhase.readingCalibration: 'Reading the calibration',
  SessionPhase.online: 'Online',
  SessionPhase.flashing: 'Updating firmware',
};

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    return StreamBuilder<SessionState>(
      stream: session.states,
      initialData: session.state,
      builder: (context, snap) {
        final s = snap.data!;
        final ecu = session.ecu;
        final parts = [
          _phaseText[s.phase]!,
          if (s.total > 0 && s.phase == SessionPhase.readingCalibration) '${s.done} of ${s.total}',
          if (s.problem == SessionProblem.noDefinition) 'no definition for this ECU',
          if (s.problem == SessionProblem.noAnswer) 'no answer',
          if (ecu != null && s.phase != SessionPhase.offline) '${ecu.productName} ${ecu.modelName} v${ecu.version}',
        ];
        return Material(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(parts.join('  ·  '), style: Theme.of(context).textTheme.bodySmall),
          ),
        );
      },
    );
  }
}
