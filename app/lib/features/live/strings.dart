abstract final class LiveStrings {
  static const notOnline = 'Connect to an ECU to see live data.';
  static const find = 'Find a channel';
  static const pin = 'Show as a dial';
  static const unpin = 'Remove the dial';
  static const dialsHint = 'Pin channels to show them as dials here.';
  static String link(int id) => 'Link $id';
  static String trend(String name) => '$name trend';
  static String gauge(String name) => '$name dial';
}
