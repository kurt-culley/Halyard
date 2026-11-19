import 'dart:async';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

/// The definition library, the serial ports and the demo link.
class ConnectController extends ChangeNotifier {
  ConnectController(this._saved, this._folders, this._ports, this._link, this._connection, this._session) {
    _sub = _session.states.listen((_) => notifyListeners());
    unawaited(refreshPorts());
  }

  final SavedDefinitions _saved;
  final FolderPicker _folders;
  DefinitionLibrary get _definitions => _saved.library;
  final PortFinder _ports;
  final ValueNotifier<TransportOpener?> _link;
  final Connection _connection;
  final Session _session;
  late final StreamSubscription<SessionState> _sub;

  List<String> get sources => _definitions.sources.toList();
  DeviceInfo? infoOf(String source) => _definitions[source]?.definition.info;
  SessionPhase get phase => _session.state.phase;
  bool get isConnected => phase != SessionPhase.offline;

  List<PortEntry> ports = const [];
  String? portId;
  bool get canAskForPort => _ports.canAsk;
  PortEntry? get port => ports.where((p) => p.id == portId).firstOrNull;

  Future<void> refreshPorts() async {
    ports = await _ports.list();
    if (port == null) portId = ports.firstOrNull?.id;
    notifyListeners();
  }

  /// The browser's port picker; must follow a click.
  Future<void> askForPort() async {
    final p = await _ports.ask();
    if (p == null) return;
    await refreshPorts();
    if (!ports.any((x) => x.id == p.id)) ports = [...ports, p];
    portId = p.id;
    notifyListeners();
  }

  void choosePort(String? id) {
    portId = id;
    notifyListeners();
  }

  /// Connects through the chosen port.
  void connectPort() {
    final p = port;
    if (p == null) return;
    _link.value = p.open;
    _connection.connect();
  }

  bool get canAddFolder => _folders.available;

  /// Adds and keeps a definition file's text; false when it isn't a definition.
  Future<bool> addDefinition(String name, String text) async {
    try {
      await _saved.add(name, text);
    } on DeviceFileError {
      return false;
    }
    notifyListeners();
    return true;
  }

  /// Adds every definition in a folder the user picks; returns the files that weren't definitions.
  Future<List<String>> addFolder() async {
    final files = await _folders.pick('.medef');
    if (files == null) return const [];
    final refused = <String>[];
    for (final (name, text) in files) {
      if (!await addDefinition(name, text)) refused.add(name);
    }
    return refused;
  }

  Future<void> removeDefinition(String source) async {
    await _saved.remove(source);
    notifyListeners();
  }

  /// Connects to a simulated ECU holding the definition from [source], answering at the usual baud rate.
  void startDemo(String source) {
    final file = _definitions[source];
    if (file == null) return;
    final ecu = SimEcu(file.calibration.copy(), reportPeriod: const Duration(milliseconds: 100));
    _link.value = (baud) => openSimulator(ecu, baud);
    _connection.connect();
  }

  Future<void> disconnect() => _connection.disconnect();

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}
