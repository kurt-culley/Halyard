import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../instruments/trigger_scope.dart';
import 'strings.dart';
import 'trigger_scope_controller.dart';

@RoutePage()
class TriggerScopePage extends StatelessWidget {
  const TriggerScopePage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => TriggerScopeController(c.read<Session>(), c.read<FileSaver>()),
    child: const _TriggerScopeView(),
  );
}

class _TriggerScopeView extends StatelessWidget {
  const _TriggerScopeView();

  Future<void> _open(TriggerScopeController c) async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: TriggerScopeStrings.fileType, extensions: ['metlg']),
      ],
    );
    if (f != null) c.open(await f.readAsString());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TriggerScopeController>();
    final theme = Theme.of(context);
    final pts = c.log.points;
    final channels = c.log.enabledChannels;
    final available = c.available;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(TriggerScopeStrings.title, style: theme.textTheme.titleLarge),
          Text(TriggerScopeStrings.hint, style: theme.textTheme.bodyMedium),
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
                  label: const Text(TriggerScopeStrings.start),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: c.stopLog,
                  icon: const Icon(Icons.stop),
                  label: const Text(TriggerScopeStrings.stop),
                ),
              for (final id in c.log.enabled.keys)
                if (available == null || available.isEmpty || available.contains(id) || (c.log.enabled[id] ?? false))
                  FilterChip(
                    label: Text(TriggerScopeStrings.channels[id]),
                    selected: c.log.enabled[id] ?? false,
                    onSelected: c.running ? null : (v) => c.setChannel(id, v),
                  ),
              const SizedBox(width: 8),
              FilterChip(label: const Text(TriggerScopeStrings.follow), selected: c.follow, onSelected: c.setFollow),
              OutlinedButton(onPressed: pts.isEmpty ? null : c.fit, child: const Text(TriggerScopeStrings.fit)),
              OutlinedButton.icon(
                onPressed: () => _open(c),
                icon: const Icon(Icons.folder_open),
                label: const Text(TriggerScopeStrings.open),
              ),
              OutlinedButton.icon(
                onPressed: pts.isEmpty ? null : c.save,
                icon: const Icon(Icons.save_alt),
                label: const Text(TriggerScopeStrings.save),
              ),
              if (c.selection != null)
                OutlinedButton(onPressed: () => c.save(span: true), child: const Text(TriggerScopeStrings.saveSpan)),
            ],
          ),
          if (!c.isOnline && pts.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 8), child: Text(TriggerScopeStrings.notOnline)),
          if (c.isOnline && available != null && available.isEmpty && !c.running)
            const Padding(padding: EdgeInsets.only(top: 8), child: Text(TriggerScopeStrings.notSupported)),
          if (c.message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(c.message!)),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: pts.isEmpty
                  ? const Center(child: Text(TriggerScopeStrings.empty))
                  : Padding(
                      padding: const EdgeInsets.all(8),
                      child: TriggerScope(
                        times: [for (final p in pts) p.timestamp],
                        lanes: [
                          for (final id in channels)
                            (name: TriggerScopeStrings.channels[id], levels: [for (final p in pts) p.values[id]]),
                        ],
                        sync: [for (final p in pts) p.syncState],
                        simulated: [for (final p in pts) p.simulated],
                        syncNames: TriggerScopeStrings.syncStates,
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
              Text(TriggerScopeStrings.points(pts.length), style: theme.textTheme.bodySmall),
              for (final m in c.measures) Text(m, style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
