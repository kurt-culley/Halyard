import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

class _File implements TextFileSink {
  _File(this.name);
  final String name;
  final text = StringBuffer();
  @override
  void write(String t) => text.write(t);
  @override
  void close() {}
}

String _f32Hex(double v) => toHex((Float32List(1)..[0] = v).buffer.asUint8List());

Future<void> main() async {
  final v = (await loadVectors('live_recordings.json')).first as Map<String, dynamic>;

  test('recording into rolling files', () {
    for (final (i, w) in (v['writers'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
      var clock = w['start'] as int;
      final writer = LiveRecordingWriter(
        maxLines: w['maxLines'] as int,
        now: () => DateTime.fromMillisecondsSinceEpoch(clock, isUtc: true),
      )..headers = (w['headers'] as List<dynamic>).cast<String?>();
      final files = <_File>[];
      for (final s in (w['steps'] as List<dynamic>).cast<List<dynamic>>()) {
        switch (s[0]) {
          case 'save':
            final folder = s[1] as String?;
            writer.setFolder(
              folder == null || folder.isEmpty
                  ? null
                  : (name) {
                    final f = _File(name);
                    files.add(f);
                    return f;
                  },
            );
          case 'dispose':
            writer.closeFile();
          case 'tick':
            clock = s[1] as int;
          case 'line':
            writer.addLine((s[1] as List<dynamic>).cast<String?>());
        }
      }
      expect(
        [
          for (final f in files) [f.name, f.text.toString()],
        ],
        [
          for (final f in (w['files'] as List<dynamic>).cast<Map<String, dynamic>>())
            [(f['name'] as String).replaceFirst('MEITEData_', 'LiveData_'), f['text']],
        ],
        reason: 'writer $i',
      );
    }
  });

  test('reading a recording back', () {
    for (final (i, r) in (v['reads'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
      final text = r['text'] as String;
      final maxLines = r['maxLines'] as int;
      if (r['throws'] == true) {
        expect(() => readLiveRecording(text, maxLines: maxLines), throwsFormatException, reason: 'read $i');
        continue;
      }
      final got = readLiveRecording(text, maxLines: maxLines);
      expect(got.complete, r['error'] != true, reason: 'read $i');
      expect(
        [
          for (final e in got.columns.entries)
            [
              e.key,
              [
                for (final (ms, value) in e.value) ['${BigInt.from(ms) * BigInt.from(10000)}', _f32Hex(value)],
              ],
            ],
        ],
        [
          for (final c in (r['map'] as List<dynamic>).cast<List<dynamic>>())
            [
              c[0],
              [
                for (final x in (c[1] as List<dynamic>).cast<List<dynamic>>()) [x[0], x[1]],
              ],
            ],
        ],
        reason: 'read $i',
      );
    }
  });

  test('the time column', () {
    for (final t in (v['times'] as List<dynamic>).cast<List<dynamic>>()) {
      expect(liveRecordingTime(DateTime.fromMillisecondsSinceEpoch(t[0] as int, isUtc: true)), t[1]);
    }
  });
}
