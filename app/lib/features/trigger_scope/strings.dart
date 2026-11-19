abstract final class TriggerScopeStrings {
  static const title = 'Trigger scope';
  static const hint =
      'Captures crank and cam edges as the ECU sees them. Live data pauses while it runs. Scroll to zoom, drag to '
      'pan, Shift-drag to measure.';
  static const notOnline = 'Connect to an ECU to capture, or open a saved capture.';
  static const notSupported = 'This ECU has no trigger logger.';
  static const start = 'Start';
  static const stop = 'Stop';
  static const save = 'Save…';
  static const saveSpan = 'Save span…';
  static const open = 'Open…';
  static const fileType = 'Trigger logs';
  static const follow = 'Follow';
  static const fit = 'Fit';
  static const empty = 'No edges yet.';
  static String unreadable(String why) => 'The trigger log could not be read: $why';
  static const channels = ['Crank', 'Cam A', 'Cam B', 'Cam C', 'Cam D'];
  static const syncStates = [
    'Not synced',
    'Crank half synced',
    'Crank synced',
    'Crank and cam synced, waiting',
    'Fully synced',
  ];
  static String span(double ms) => 'Span ${ms.toStringAsFixed(ms >= 100 ? 1 : 3)} ms';
  static String edges(String channel, int rising, int falling) => '$channel: $rising rising, $falling falling';
  static String points(int n) => '$n points';
}
