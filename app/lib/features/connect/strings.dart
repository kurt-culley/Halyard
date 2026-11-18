abstract final class ConnectStrings {
  static const definitions = 'Definitions';
  static const definitionsHint =
      'Add the definition files for your ECU. Halyard ships none; it finds the one that matches the ECU it connects to.';
  static const addDefinitions = 'Add definitions…';
  static const remove = 'Remove';
  static const noDefinitions = 'No definitions yet.';
  static const serial = 'Serial port';
  static const serialHint = 'Connect to the ECU over USB. Halyard only reads from it until editing arrives.';
  static const noPorts = 'No ports found.';
  static const choosePort = 'Choose a port…';
  static const refresh = 'Refresh';
  static const connect = 'Connect';
  static const demo = 'Demo';
  static const demoHint = 'Runs a simulated ECU built from one of your definitions, with live data.';
  static const startDemo = 'Start demo';
  static const disconnect = 'Disconnect';
  static const fileTypeLabel = 'Definitions';
  static String notADefinition(String name) => '$name is not a definition file.';
}
