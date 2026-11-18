/// Logging live data to a CSV on this computer (U21a P03 to P06): a header naming the channels, then one line per
/// tick with the time since the start, a marker flag and each channel's latest value to two decimals. The recorder
/// samples the live store on its own timer, so what the display skips never matters to the log.
library;

import 'dart:async';

import '../definition/definition.dart';
import '../live/live_store.dart';
import 'number_text.dart';

/// The rates the original offered, per second.
const pcLogMinFrequency = 10, pcLogMaxFrequency = 25;

/// The configured channels that the definition has, in configured order; none configured means every link.
List<LinkDef> pcLogChannels(Definition d, List<int> configured) =>
    configured.isEmpty
        ? d.links.values.toList()
        : [
          for (final id in configured)
            if (d.links[id] case final l?) l,
        ];

String pcLogHeader(List<LinkDef> channels, {String delimiter = ','}) {
  final b = StringBuffer('Time$delimiter Marker');
  for (final l in channels) {
    b.write('$delimiter ${l.name ?? ''}');
  }
  return b.toString();
}

String pcLogLine(double elapsedSeconds, List<double> values, {bool marker = false, String delimiter = ','}) {
  final b = StringBuffer('${formatFixed(elapsedSeconds, 2, isFloat: false)}$delimiter${marker ? '1' : '0'}');
  for (final v in values) {
    b.write('$delimiter${formatFixed(v, 2)}');
  }
  return b.toString();
}

class PcLogRecorder {
  PcLogRecorder({
    required this.live,
    required this.channels,
    required this.write,
    this.delimiter = ',',
    this.frequency = pcLogMinFrequency,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now {
    if (frequency <= 0) throw ArgumentError.value(frequency, 'frequency', 'must be positive');
  }

  final LiveStore live;
  final List<LinkDef> channels;

  /// Receives the file's text, line by line with CRLF ends.
  final void Function(String text) write;
  final String delimiter;
  final int frequency;
  final DateTime Function() now;

  Timer? _timer;
  DateTime? _start;
  bool _mark = false;

  bool get isRecording => _timer != null;

  void start() {
    if (_timer != null) return;
    write('${pcLogHeader(channels, delimiter: delimiter)}\r\n');
    _start = now();
    _timer = Timer.periodic(Duration(milliseconds: 1000 ~/ frequency), (_) => tick());
  }

  /// Marks the next line.
  void mark() => _mark = isRecording;

  void tick() {
    final start = _start;
    if (start == null) return;
    final secs = now().difference(start).inMicroseconds / 1e6;
    final values = [for (final l in channels) live.has(l.id) ? live.value(l.id) : 0.0];
    write('${pcLogLine(secs, values, marker: _mark, delimiter: delimiter)}\r\n');
    _mark = false;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _start = null;
  }
}
