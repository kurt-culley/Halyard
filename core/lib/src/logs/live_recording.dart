/// Live-data recordings (U11 W01 to W06): while a folder is set, every report becomes a CSV line with the time and
/// each link's value, in files of at most a set number of lines; a recording reads back for playback.
library;

import '../definition/definition.dart';
import 'log_review.dart' show readTextLines;
import 'number_text.dart';

/// An open text file (UTF-8, no BOM).
abstract interface class TextFileSink {
  void write(String text);
  void close();
}

/// A recording's file name, from local time. The original's name carried the vendor's product name.
String liveRecordingFileName(DateTime t) {
  String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
  return 'LiveData_${p(t.year, 4)}_${p(t.month)}_${p(t.day)}_${p(t.hour)}_${p(t.minute)}_${p(t.second)}.csv';
}

/// The time column: local time as seconds since 0001-01-01, as the original wrote it.
String liveRecordingTime(DateTime t) {
  final ms = t.millisecondsSinceEpoch + t.timeZoneOffset.inMilliseconds + 62135596800000;
  return formatGeneral(ms * 10000.0 * 1e-7, isFloat: false);
}

const liveRecordingTimeHeader = 'Time';

class LiveRecordingWriter {
  LiveRecordingWriter({this.maxLines = 1200, DateTime Function()? now}) : now = now ?? DateTime.now;

  final int maxLines;
  final DateTime Function() now;
  final String delimiter = ',';

  /// The link names; set with each definition, which also ends the current file.
  List<String?>? headers;

  TextFileSink Function(String fileName)? _createFile;
  TextFileSink? _file;
  int _lines = 0;

  /// Records into a folder through [createFile] (a file of that name is emptied), or stops recording with null.
  void setFolder(TextFileSink Function(String fileName)? createFile) {
    _createFile = createFile;
    closeFile();
  }

  bool get isRecording => _createFile != null && (headers?.isNotEmpty ?? false);

  void closeFile() {
    final f = _file;
    _file = null;
    f?.close();
  }

  /// Writes a line, starting a file with a header line first when none is open. A full file is closed.
  void addLine(List<String?> cols) {
    if (_file == null) {
      if (!isRecording) return;
      _file = _createFile!(liveRecordingFileName(now()));
      _lines = 0;
      addLine([liveRecordingTimeHeader, ...headers!]);
      return addLine(cols);
    }
    _file!.write('${cols.map((c) => c ?? '').join(delimiter)}\r\n');
    _lines++;
    if (_lines > maxLines) closeFile();
  }

  /// A report's line: the time, then each link's value.
  void addReport(DateTime at, Iterable<double> values) =>
      addLine([liveRecordingTime(at), for (final v in values) formatGeneral(v)]);

  /// Sets the headers for a definition's links and ends the current file.
  void useDefinition(Definition d) {
    closeFile();
    headers = [for (final l in d.links.values) l.name];
  }
}

/// A recording read back: per column, (time in milliseconds since 0001-01-01, value), at most the last `maxLines`.
/// The time column's own values are 0. [complete] is false when a bad line ended the read early.
typedef LiveRecording = ({Map<String, List<(int ms, double value)>> columns, bool complete});

/// Reads a recording. Throws [FormatException] for an empty file.
LiveRecording readLiveRecording(String text, {int maxLines = 1200}) {
  final lines = readTextLines(text);
  if (lines.isEmpty) throw const FormatException('The recording is empty.');
  final headers = [for (final h in lines.first.split(',')) h.trim()];
  final columns = {for (final h in headers) h: <(int, double)>[]};
  void push(List<(int, double)> l, (int, double) v) {
    l.add(v);
    if (l.length > maxLines) l.removeAt(0);
  }

  try {
    for (final line in lines.skip(1)) {
      final cols = line.split(',');
      final ms = _millisFromSeconds(parseNetDouble(cols[0]));
      push(columns[headers[0]]!, (ms, 0));
      for (var i = 1; i < cols.length; i++) {
        if (i >= headers.length) throw const FormatException('more columns than headers');
        push(columns[headers[i]]!, (ms, parseNetSingle(cols[i])));
      }
    }
  } on Exception {
    return (columns: columns, complete: false);
  } on RangeError {
    return (columns: columns, complete: false);
  }
  return (columns: columns, complete: true);
}

/// `TimeSpan.FromSeconds` on .NET Framework: rounded to whole milliseconds.
int _millisFromSeconds(double s) {
  if (s.isNaN) throw const FormatException('NaN is not a time');
  final millis = s * 1000 + (s >= 0 ? 0.5 : -0.5);
  if (millis > 922337203685477 || millis < -922337203685477) throw RangeError('time out of range');
  return millis.truncate();
}
