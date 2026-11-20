import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'connect_controller.dart';
import 'strings.dart';

@RoutePage()
class ConnectPage extends StatelessWidget {
  const ConnectPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => ConnectController(
      c.read<SavedDefinitions>(),
      c.read<FolderPicker>(),
      c.read<PortFinder>(),
      c.read<ValueNotifier<TransportOpener?>>(),
      c.read<Connection>(),
      c.read<Session>(),
      c.read<SwitchablePolicy>(),
      c.read<DemoDefinitionSource?>(),
    ),
    child: const _ConnectView(),
  );
}

class _ConnectView extends StatefulWidget {
  const _ConnectView();

  @override
  State<_ConnectView> createState() => _ConnectViewState();
}

class _ConnectViewState extends State<_ConnectView> {
  String? _demoSource;

  Future<void> _addDefinitions(ConnectController c) async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(label: ConnectStrings.fileTypeLabel, extensions: ['medef']),
      ],
    );
    final refused = <String>[];
    for (final f in files) {
      if (!await c.addDefinition(f.name, await f.readAsString())) refused.add(f.name);
    }
    _refused(refused);
  }

  void _refused(List<String> names) {
    if (names.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ConnectStrings.notDefinitions(names))));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ConnectController>();
    final theme = Theme.of(context);
    final sources = c.sources;
    final demo = sources.contains(_demoSource) ? _demoSource : (sources.isEmpty ? null : sources.first);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(ConnectStrings.definitions, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(ConnectStrings.definitionsHint, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        if (sources.isEmpty) const Text(ConnectStrings.noDefinitions),
        for (final s in sources)
          ListTile(
            title: Text(s),
            subtitle: Text('${c.infoOf(s) ?? ''}'),
            trailing: IconButton(
              tooltip: ConnectStrings.remove,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => c.removeDefinition(s),
            ),
          ),
        Wrap(
          spacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: () => _addDefinitions(c),
              icon: const Icon(Icons.add),
              label: const Text(ConnectStrings.addDefinitions),
            ),
            if (c.canAddFolder)
              OutlinedButton.icon(
                onPressed: () async => _refused(await c.addFolder()),
                icon: const Icon(Icons.folder_open),
                label: const Text(ConnectStrings.addFolder),
              ),
          ],
        ),
        const SizedBox(height: 32),
        Text(ConnectStrings.serial, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(ConnectStrings.serialHint, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (c.ports.isEmpty)
              const Text(ConnectStrings.noPorts)
            else
              DropdownButton<String>(
                value: c.portId,
                items: [for (final p in c.ports) DropdownMenuItem(value: p.id, child: Text(p.label))],
                onChanged: c.isConnected ? null : c.choosePort,
              ),
            if (c.canAskForPort)
              OutlinedButton(
                onPressed: c.isConnected ? null : c.askForPort,
                child: const Text(ConnectStrings.choosePort),
              )
            else
              IconButton(
                tooltip: ConnectStrings.refresh,
                onPressed: c.isConnected ? null : c.refreshPorts,
                icon: const Icon(Icons.refresh),
              ),
            if (!c.isConnected)
              FilledButton(onPressed: c.port == null ? null : c.connectPort, child: const Text(ConnectStrings.connect)),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(ConnectStrings.readOnly),
          subtitle: const Text(ConnectStrings.readOnlyHint),
          value: c.readOnly,
          onChanged: (v) => c.readOnly = v,
        ),
        const SizedBox(height: 32),
        Text(ConnectStrings.demo, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(ConnectStrings.demoHint, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        if (!c.isConnected && context.read<DemoDefinitionSource?>() != null) ...[
          OutlinedButton.icon(
            onPressed: () async {
              if (!await c.startSampleDemo() && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(ConnectStrings.noSample)));
              }
            },
            icon: const Icon(Icons.play_circle_outline),
            label: const Text(ConnectStrings.sampleDemo),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              value: demo,
              items: [for (final s in sources) DropdownMenuItem(value: s, child: Text(s))],
              onChanged: c.isConnected ? null : (s) => setState(() => _demoSource = s),
            ),
            if (!c.isConnected)
              FilledButton(
                onPressed: demo == null ? null : () => c.startDemo(demo),
                child: const Text(ConnectStrings.startDemo),
              )
            else
              FilledButton.tonal(onPressed: c.disconnect, child: const Text(ConnectStrings.disconnect)),
          ],
        ),
      ],
    );
  }
}
