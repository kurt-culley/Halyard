abstract final class PlaybackStrings {
  static const live = 'Live';
  static const notLive = 'Not Live';
  static const goLive = 'Go live';
  static const play = 'Play';
  static const pause = 'Pause';
  static const back = 'Back 0.1 s';
  static const backMore = 'Back 1 s';
  static const forward = 'Forward 0.1 s';
  static const forwardMore = 'Forward 1 s';
  static const load = 'Load a recording…';
  static const save = 'Save the history…';
  static const fileType = 'Live data recordings';
  static const askTitle = 'Live Mode';
  static const ask = 'Go to live mode?';
  static const dontAsk = "Don't show this again.";
  static const yes = 'Yes';
  static const no = 'No';
  static String unreadable(String why) => 'The recording could not be read: $why';
  static const partly = 'Part of the recording could not be read; what came before it is shown.';

  /// The original's track label: time back from the newest report, `-mm:ss:fff`.
  static String label(int steps) {
    final ms = steps * 100;
    String two(int n) => n.toString().padLeft(2, '0');
    return '-${two(ms ~/ 60000 % 60)}:${two(ms ~/ 1000 % 60)}:${(ms % 1000).toString().padLeft(3, '0')}';
  }
}
