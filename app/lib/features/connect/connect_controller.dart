import 'dart:async';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

/// The definition library and the demo link. Serial ports come with the platform transports.
class ConnectController extends ChangeNotifier {
  ConnectController(this._definitions, this._link, this._connection, this._session) {
    _sub = _session.states.listen((_) => notifyListeners());
  }

  final DefinitionLibrary _definitions;
  final ValueNotifier<TransportOpener?> _link;
  final Connection _connection;
  final Session _session;
  late final StreamSubscription<SessionState> _sub;

  List<String> get sources => _definitions.sources.toList();
  DeviceInfo? infoOf(String source) => _definitions[source]?.definition.info;
  SessionPhase get phase => _session.state.phase;
  bool get isConnected => phase != SessionPhase.offline;

  /// Adds a definition file's text; false when it isn't a definition.
  bool addDefinition(String name, String text) {
    try {
      _definitions.add(name, text);
    } on DeviceFileError {
      return false;
    }
    notifyListeners();
    return true;
  }

  void removeDefinition(String source) {
    _definitions.remove(source);
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
