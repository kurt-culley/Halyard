import 'package:halyard_core/halyard_core.dart';

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

abstract final class OnboardStrings {
  static const thisComputer = 'On this computer';
  static const onEcu = 'On the ECU';
  static const notSupported = 'This ECU has no onboard logging.';
  static const notOnline = 'Connect to an ECU to reach its logs.';
  static const idle = 'Idle';
  static const logging = 'Logging';
  static const unknown = 'Waiting for the ECU';
  static String state(String s, int? entries) => entries == null ? s : '$s, $entries entries';
  static const start = 'Start Logging';
  static const stop = 'Stop Logging';
  static const configuration = 'Configuration';
  static const rate = 'Rate';
  static String hz(int f) => '$f Hz';
  static String channelCount(int n, int max) => '$n of $max channels';
  static const standard = 'Standard';
  static const none = 'None';
  static const saveConfig = 'Save configuration';
  static const saved = 'Configuration saved.';
  static const invalid = 'Invalid configuration! Only valid configurations will be saved.';
  static const logs = 'Logs';
  static const refresh = 'Refresh';
  static const download = 'Download';
  static const cancel = 'Cancel';
  static const erase = 'Erase selected';
  static const format = 'Erase all';
  static const formatQuestion = 'Erase every log on the ECU?';
  static const eraseQuestion = 'Erase the selected logs from the ECU?';
  static const yes = 'Yes';
  static const no = 'No';
  static const noLogs = 'No logs on the ECU.';
  static const readOnly = 'Read only is on: logs can be listed and downloaded; turn it off to change anything.';
  static const complete = 'Download Complete!';
  static String progress(int done, int total) => 'Downloaded $done\\$total';
  static const cannotFormat = 'Cannot format while logging is in progress';
  static const cannotDownload = 'Cannot download log while logging is in progress';
  static const cannotErase = 'Cannot erase while logging is in progress';
  static const cannotStart = 'Cannot start logging while a download is in progress';
  static String failed(OnboardLogError e) =>
      'The ECU did not answer as expected (${e.toString().replaceFirst('OnboardLogError', '')}).';

  static String when(LogInfo l) {
    final t = l.timestamp;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  static String duration(double s) =>
      s >= 60 ? '${(s / 60).floor()} min ${(s % 60).round()} s' : '${s.toStringAsFixed(1)} s';

  /// The original's name: `OnBoardLog_yyyy_dd_M_HH_mm_No<id>.csv`.
  static String fileName(LogInfo l) {
    final t = l.timestamp;
    String two(int n) => n.toString().padLeft(2, '0');
    return 'OnBoardLog_${t.year.toString().padLeft(4, '0')}_${two(t.day)}_${t.month}_${two(t.hour)}_${two(t.minute)}_No${l.id}.csv';
  }
}
