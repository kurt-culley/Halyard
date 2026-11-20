abstract final class ConnectStrings {
  static const definitions = 'Definitions';
  static const definitionsHint =
      'Add the definition files for your ECU. Halyard ships none; it keeps the ones you add and finds the one that '
      'matches the ECU it connects to.';
  static const addDefinitions = 'Add definitions…';
  static const remove = 'Remove';
  static const noDefinitions = 'No definitions yet.';
  static const serial = 'Serial port';
  static const serialHint = 'Connect to the ECU over USB.';
  static const readOnly = 'Read only';
  static const readOnlyHint =
      'Nothing can be changed on the ECU while this is on. Run the bench test first, then turn it off to edit.';
  static const noPorts = 'No ports found.';
  static const choosePort = 'Choose a port…';
  static const refresh = 'Refresh';
  static const connect = 'Connect';
  static const demo = 'Demo';
  static const demoHint = 'Runs a simulated ECU built from one of your definitions, with live data.';
  static const startDemo = 'Start demo';
  static const sampleDemo = 'Try the demo with the sample definition';
  static const noSample = 'The sample definition could not be fetched.';
  static const disconnect = 'Disconnect';
  static const fileTypeLabel = 'Definitions';
  static const addFolder = 'Add a folder…';
  static String notDefinitions(List<String> names) => names.length == 1
      ? '${names.first} is not a definition file.'
      : 'These are not definition files: ${names.join(', ')}';
}
