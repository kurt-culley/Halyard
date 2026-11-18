import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../platform/serial.dart';
import 'desktop_router.dart';

/// The desktop and web composition root: one connection and session for the app's life, the definition library,
/// and the link the connect feature chooses. Until the write gate exists the link only lets reads through.
class DesktopRoot extends StatefulWidget {
  const DesktopRoot({super.key, this.ports});

  /// The serial ports; the platform's when null.
  final PortFinder? ports;

  @override
  State<DesktopRoot> createState() => _DesktopRootState();
}

class _DesktopRootState extends State<DesktopRoot> {
  final _definitions = DefinitionLibrary();
  late final _ports = widget.ports ?? platformPorts();
  final _link = ValueNotifier<TransportOpener?>(null);
  late final _connection = Connection((baud) {
    final open = _link.value;
    if (open == null) throw StateError('No link has been chosen.');
    return open(baud);
  }, policy: const ReadOnlyPolicy());
  late final _session = Session(_connection, definitions: _definitions.lookup);
  final _router = DesktopRouter();

  @override
  void dispose() {
    _session.dispose();
    _connection.disconnect();
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      Provider.value(value: _definitions),
      Provider.value(value: _ports),
      ChangeNotifierProvider.value(value: _link),
      Provider.value(value: _connection),
      Provider.value(value: _session),
    ],
    child: MaterialApp.router(title: 'Halyard', routerConfig: _router.config()),
  );
}
