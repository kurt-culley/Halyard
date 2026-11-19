import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../features/live/live_tiles.dart';
import '../platform/serial.dart';
import '../platform/storage.dart';
import '../workspace/tile_source.dart';
import '../workspace/workspace_controller.dart';
import 'desktop_router.dart';

/// The desktop and web composition root: one connection and session for the app's life, the user's saved
/// definitions, and the link the connect feature chooses. Until the write gate exists the link only lets reads through.
class DesktopRoot extends StatefulWidget {
  const DesktopRoot({super.key, this.ports, this.storage, this.folders});

  /// The platform's when null; tests pass their own.
  final PortFinder? ports;
  final AppStorage? storage;
  final FolderPicker? folders;

  @override
  State<DesktopRoot> createState() => _DesktopRootState();
}

class _DesktopRootState extends State<DesktopRoot> {
  final _definitions = DefinitionLibrary();
  late final _ports = widget.ports ?? platformPorts();
  late final _folders = widget.folders ?? platformFolders();
  final _link = ValueNotifier<TransportOpener?>(null);
  late final _connection = Connection((baud) {
    final open = _link.value;
    if (open == null) throw StateError('No link has been chosen.');
    return open(baud);
  }, policy: const ReadOnlyPolicy());
  late final _session = Session(_connection, definitions: _definitions.lookup);
  final _router = DesktopRouter();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  SavedDefinitions? _saved;
  WorkspaceController? _workspace;
  late final List<TileSource> _tiles = [LiveTiles(_session), LiveTiles(_session, trace: true)];

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final storage = widget.storage ?? await platformStorage();
    final saved = SavedDefinitions(storage, _definitions);
    final failed = await saved.restore();
    final workspace = WorkspaceController(storage);
    await workspace.load();
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _workspace = workspace;
    });
    if (failed.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _messenger.currentState?.showSnackBar(
          SnackBar(content: Text('These saved definitions could not be read: ${failed.join(', ')}')),
        ),
      );
    }
  }

  @override
  void dispose() {
    _session.dispose();
    _connection.disconnect();
    _link.dispose();
    _workspace?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved, workspace = _workspace;
    if (saved == null || workspace == null) return const ColoredBox(color: Colors.white);
    return MultiProvider(
      providers: [
        Provider.value(value: saved),
        ChangeNotifierProvider.value(value: workspace),
        Provider.value(value: _tiles),
        Provider.value(value: _ports),
        Provider.value(value: _folders),
        ChangeNotifierProvider.value(value: _link),
        Provider.value(value: _connection),
        Provider.value(value: _session),
      ],
      child: MaterialApp.router(title: 'Halyard', scaffoldMessengerKey: _messenger, routerConfig: _router.config()),
    );
  }
}
