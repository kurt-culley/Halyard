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
      c.read<DefinitionLibrary>(),
      c.read<ValueNotifier<TransportOpener?>>(),
      c.read<Connection>(),
      c.read<Session>(),
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
    for (final f in files) {
      final ok = c.addDefinition(f.name, await f.readAsString());
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ConnectStrings.notADefinition(f.name))));
      }
    }
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
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _addDefinitions(c),
            icon: const Icon(Icons.add),
            label: const Text(ConnectStrings.addDefinitions),
          ),
        ),
        const SizedBox(height: 32),
        Text(ConnectStrings.demo, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(ConnectStrings.demoHint, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            DropdownButton<String>(
              value: demo,
              items: [for (final s in sources) DropdownMenuItem(value: s, child: Text(s))],
              onChanged: c.isConnected ? null : (s) => setState(() => _demoSource = s),
            ),
            const SizedBox(width: 16),
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
