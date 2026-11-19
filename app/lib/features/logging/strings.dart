abstract final class LoggingStrings {
  static const record = 'Record';
  static const recordHint = 'Logs every live channel to CSV at 10 samples a second while the ECU is connected.';
  static const start = 'Start';
  static const stop = 'Stop';
  static const mark = 'Mark';
  static const save = 'Save the log…';
  static const notOnline = 'Connect to an ECU to record.';
  static String recorded(int lines, double seconds) => '$lines samples, ${seconds.toStringAsFixed(1)} s';
  static const review = 'Review';
  static const open = 'Open a log…';
  static const fileType = 'CSV logs';
  static String opened(String name, int samples, int channels) => '$name: $samples samples, $channels channels';
  static const choose = 'Choose channels to plot.';
}
