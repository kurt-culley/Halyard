abstract final class FaultsStrings {
  static const notOnline = 'Connect to an ECU to read its fault log.';
  static const noLog = 'This ECU has no fault log.';
  static const read = 'Read the fault log';
  static const reading = 'Reading…';
  static const history = 'Read the history';
  static const summary = 'Codes';
  static const records = 'History, newest first';
  static const noCodes = 'No codes have been logged.';
  static const readOnly = 'Clearing the log is a write: it arrives with the write gate.';
  static const columns = ['Code', 'Name', 'Severity', 'State', 'Count', 'Lifetime', 'Last seen'];
  static const severities = ['Info', 'Warning', 'Fault', 'Critical'];
  static const states = ['Idle', 'Pending', 'Active', 'Active (cooling down)', 'Stored'];
  static const recordTypes = {1: 'Occurrence', 2: 'Checkpoint', 3: 'Cleared', 4: 'Configuration'};
  static String hours(double h) => '${h.toStringAsFixed(2)} h';
  static String usage(int used, int capacity) => 'Log space used: $used of $capacity';
  static String failed(String what) => 'The ECU stopped answering ($what).';
}
