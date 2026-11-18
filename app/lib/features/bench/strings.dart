abstract final class BenchStrings {
  static const title = 'Read-only bench test';
  static const hint =
      'Runs a checklist of reads against the connected ECU. Nothing is written: the link refuses every request that '
      'would change the ECU, and the report lists any that were attempted.';
  static const run = 'Run the checks';
  static const running = 'Running…';
  static const copyReport = 'Copy the report';
  static const copied = 'Report copied.';
  static const notOnline = 'Connect to an ECU first.';
}
