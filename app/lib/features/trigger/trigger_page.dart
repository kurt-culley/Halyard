import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../instruments/trigger_scope.dart';
import 'strings.dart';
import 'trigger_controller.dart';

@RoutePage()
class TriggerPage extends StatelessWidget {
  const TriggerPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => TriggerController(c.read<Session>(), c.read<FileSaver>()),
    child: const _TriggerView(),
  );
}

class _TriggerView extends StatelessWidget {
  const _TriggerView();

  Future<void> _open(TriggerController c) async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: TriggerStrings.fileType, extensions: ['metlg']),
      ],
    );
    if (f != null) c.open(await f.readAsString());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TriggerController>();
    final theme = Theme.of(context);
    final pts = c.log.points;
    final channels = c.log.enabledChannels;
    final available = c.available;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(TriggerStrings.title, style: theme.textTheme.titleLarge),
          Text(TriggerStrings.hint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!c.running)
                FilledButton.icon(
                  onPressed: c.isOnline && (available?.isNotEmpty ?? false) ? c.startLog : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text(TriggerStrings.start),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: c.stopLog,
                  icon: const Icon(Icons.stop),
                  label: const Text(TriggerStrings.stop),
                ),
              for (final id in c.log.enabled.keys)
                if (available == null || available.isEmpty || available.contains(id) || (c.log.enabled[id] ?? false))
                  FilterChip(
                    label: Text(TriggerStrings.channels[id]),
                    selected: c.log.enabled[id] ?? false,
                    onSelected: c.running ? null : (v) => c.setChannel(id, v),
                  ),
              const SizedBox(width: 8),
              FilterChip(label: const Text(TriggerStrings.follow), selected: c.follow, onSelected: c.setFollow),
              OutlinedButton(onPressed: pts.isEmpty ? null : c.fit, child: const Text(TriggerStrings.fit)),
              OutlinedButton.icon(
                onPressed: () => _open(c),
                icon: const Icon(Icons.folder_open),
                label: const Text(TriggerStrings.open),
              ),
              OutlinedButton.icon(
                onPressed: pts.isEmpty ? null : c.save,
                icon: const Icon(Icons.save_alt),
                label: const Text(TriggerStrings.save),
              ),
              if (c.selection != null)
                OutlinedButton(onPressed: () => c.save(span: true), child: const Text(TriggerStrings.saveSpan)),
            ],
          ),
          if (!c.isOnline && pts.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 8), child: Text(TriggerStrings.notOnline)),
          if (c.isOnline && available != null && available.isEmpty && !c.running)
            const Padding(padding: EdgeInsets.only(top: 8), child: Text(TriggerStrings.notSupported)),
          if (c.message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(c.message!)),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: pts.isEmpty
                  ? const Center(child: Text(TriggerStrings.empty))
                  : Padding(
                      padding: const EdgeInsets.all(8),
                      child: TriggerScope(
                        times: [for (final p in pts) p.timestamp],
                        lanes: [
                          for (final id in channels)
                            (name: TriggerStrings.channels[id], levels: [for (final p in pts) p.values[id]]),
                        ],
                        sync: [for (final p in pts) p.syncState],
                        simulated: [for (final p in pts) p.simulated],
                        syncNames: TriggerStrings.syncStates,
                        start: c.start,
                        end: c.end,
                        selection: c.selection,
                        onWindow: c.setWindow,
                        onSelect: c.select,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 24,
            children: [
              Text(TriggerStrings.points(pts.length), style: theme.textTheme.bodySmall),
              for (final m in c.measures) Text(m, style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
