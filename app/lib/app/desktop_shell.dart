import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../features/logging/playback_strip.dart';
import '../workspace/choice_dialog.dart';
import '../workspace/page_layout.dart';
import '../workspace/strings.dart';
import '../workspace/tile_source.dart';
import '../workspace/workspace_controller.dart';
import 'desktop_router.dart';

/// The desktop frame: a navigation rail beside the current page, a status bar with the link and session state, and
/// the command palette (Ctrl+K, or ⌘K on a Mac).
@RoutePage()
class DesktopShellPage extends StatelessWidget {
  const DesktopShellPage({super.key});

  /// The rail, in order: label, icon and the page it opens.
  static const _destinations = <(String, IconData, PageRouteInfo)>[
    ('Connect', Icons.cable, ConnectRoute()),
    ('Live', Icons.speed, LiveRoute()),
    ('Tables', Icons.grid_on, TablesRoute()),
    ('Settings', Icons.tune, ParametersRoute()),
    ('Tuning', Icons.auto_fix_high, AssistRoute()),
    ('Calibration', Icons.description_outlined, CalibrationRoute()),
    (WorkspaceStrings.pages, Icons.dashboard_customize, WorkspaceRoute()),
    ('Logging', Icons.timeline, LoggingRoute()),
    ('Trigger', Icons.ssid_chart, TriggerScopeRoute()),
    ('Faults', Icons.report_problem_outlined, FaultsRoute()),
    ('ECU tools', Icons.build_outlined, EcuToolsRoute()),
    ('Bench test', Icons.fact_check, BenchRoute()),
  ];
  static final _pagesTab = _destinations.indexWhere((d) => d.$3 is WorkspaceRoute);

  /// Every place and action, then every item that can go in a tile.
  static Future<void> openPalette(BuildContext context, TabsRouter tabs) async {
    final w = context.read<WorkspaceController>();
    final commands = <(String, void Function())>[
      for (final (i, (label, _, _)) in _destinations.indexed) ('Go to $label', () => tabs.setActiveIndex(i)),
      (
        WorkspaceStrings.newPage,
        () {
          w.addPage();
          tabs.setActiveIndex(_pagesTab);
        },
      ),
      if (w.canUndo) ('${WorkspaceStrings.undo} (${w.page.name})', w.undo),
      if (w.canRedo) ('${WorkspaceStrings.redo} (${w.page.name})', w.redo),
      for (final source in context.read<List<TileSource>>())
        for (final ch in source.choices)
          (
            WorkspaceStrings.showInTile(ch.label),
            () {
              w.edit((p) => _addTile(p, ch.content));
              tabs.setActiveIndex(_pagesTab);
            },
          ),
    ];
    final run = await showChoiceDialog(context, title: WorkspaceStrings.palette, choices: commands);
    run?.call();
  }

  /// Fills the page's first empty tile, or splits the tile with the most room.
  static PageLayout _addTile(PageLayout p, TileContent content) {
    final empty = p.tiles.where((t) => t.content.isEmpty).firstOrNull;
    if (empty != null) return p.setContent(empty.id, content);
    final (id, side) = p.roomiest();
    return p.split(id, side, content);
  }

  @override
  Widget build(BuildContext context) => AutoTabsRouter(
    routes: [for (final d in _destinations) d.$3],
    builder: (context, child) {
      final tabs = AutoTabsRouter.of(context);
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => openPalette(context, tabs),
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => openPalette(context, tabs),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Row(
              children: [
                // The rail scrolls when the window is shorter than its destinations.
                LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: box.maxHeight),
                      child: IntrinsicHeight(
                        child: NavigationRail(
                          selectedIndex: tabs.activeIndex,
                          onDestinationSelected: tabs.setActiveIndex,
                          labelType: NavigationRailLabelType.all,
                          trailing: IconButton(
                            tooltip: '${WorkspaceStrings.palette} (Ctrl+K)',
                            icon: const Icon(Icons.search),
                            onPressed: () => openPalette(context, tabs),
                          ),
                          destinations: [
                            for (final (label, icon, _) in _destinations)
                              NavigationRailDestination(icon: Icon(icon), label: Text(label)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
            bottomNavigationBar: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [PlaybackStrip(), _StatusBar()],
            ),
          ),
        ),
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
