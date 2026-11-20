abstract final class FaultsStrings {
  static const notOnline = 'Connect to an ECU to read its fault log.';
  static const noLog = 'This ECU has no fault log.';
  static const read = 'Read the fault log';
  static const reading = 'Reading…';
  static const history = 'Read the history';
  static const summary = 'Codes';
  static const records = 'History, newest first';
  static const noCodes = 'No codes have been logged.';
  static const readOnly = 'Read only is on: turn it off on the connect page to clear or erase.';
  // The original's words.
  static const clear = 'Clear';
  static const clearTip = 'Zero the clearable counters. Lifetime counts and the history are kept.';
  static const clearConfirm = 'Zero the clearable counters of every code?\n\nLifetime counts and the history are kept.';
  static const erase = 'Erase history';
  static const eraseTip = 'Wipe the whole fault log (records, counters and lifetime counts). Engine hours are kept.';
  static const eraseTipRunning = 'Wipe the whole fault log. The engine must be stopped.';
  static const eraseConfirm =
      'Erase the whole fault log?\n\nEvery record, counter and lifetime count is lost. Engine hours are kept. '
      'Consider saving a diagnostic report first.';
  static const caption = 'Fault log';
  static const engineRunning = 'The engine must be stopped to erase the fault log history.';
  static const busy = 'The ECU is busy writing the fault log; try again in a moment.';
  static const noAnswer = 'The ECU did not answer the fault log request.';
  static String clearRefused(int status) => 'Clear refused: status $status';
  static String eraseRefused(int status) => 'Erase refused: status $status';
  static const cleared = 'Fault counters cleared.';
  static const erased = 'Fault log erased.';
  static const yes = 'Yes';
  static const no = 'No';
  static const columns = ['Code', 'Name', 'Severity', 'State', 'Count', 'Lifetime', 'Last seen'];
  static const severities = ['Info', 'Warning', 'Fault', 'Critical'];
  static const states = ['Idle', 'Pending', 'Active', 'Active (cooling down)', 'Stored'];
  static const recordTypes = {1: 'Occurrence', 2: 'Checkpoint', 3: 'Cleared', 4: 'Configuration'};
  static String hours(double h) => '${h.toStringAsFixed(2)} h';
  static String usage(int used, int capacity) => 'Log space used: $used of $capacity';
  static String failed(String what) => 'The ECU stopped answering ($what).';
}
