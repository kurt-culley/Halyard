// Fails when the original tool or its vendor is named anywhere a user could see it: string literals in Dart code
// under core/lib and app/lib, and files under app/assets. Comments may name them. Run from the repository root:
//
//   dart run tool/check_branding.dart
import 'dart:io';

final _names = RegExp(r'meite|motorsport\s*electronics', caseSensitive: false);

void main() {
  final problems = <String>[];
  for (final root in ['core/lib', 'app/lib']) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final (line, s) in _strings(f.readAsStringSync())) {
        if (_names.hasMatch(s)) problems.add('${f.path}:$line: ${s.trim()}');
      }
    }
  }
  final assets = Directory('app/assets');
  if (assets.existsSync()) {
    for (final f in assets.listSync(recursive: true).whereType<File>()) {
      String text;
      try {
        text = f.readAsStringSync();
      } on FileSystemException {
        continue; // binary
      }
      if (_names.hasMatch(text) || _names.hasMatch(f.path)) problems.add(f.path);
    }
  }
  for (final p in problems) {
    stderr.writeln(p);
  }
  if (problems.isNotEmpty) exit(1);
  stdout.writeln('No vendor names in user-facing text.');
}

/// String literals in Dart source with their line numbers; comments are skipped.
Iterable<(int, String)> _strings(String src) sync* {
  var i = 0, line = 1;
  while (i < src.length) {
    final c = src[i];
    if (c == '\n') line++;
    if (src.startsWith('//', i)) {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (src.startsWith('/*', i)) {
      final end = src.indexOf('*/', i + 2);
      final stop = end < 0 ? src.length : end + 2;
      line += '\n'.allMatches(src.substring(i, stop)).length;
      i = stop;
      continue;
    }
    if (c == "'" || c == '"') {
      final raw = i > 0 && src[i - 1] == 'r';
      final q = src.startsWith(c * 3, i) ? c * 3 : c;
      final start = line;
      var j = i + q.length;
      final buf = StringBuffer();
      while (j < src.length && !src.startsWith(q, j)) {
        if (!raw && src[j] == r'\' && j + 1 < src.length) {
          buf.write(src[j + 1]);
          j += 2;
          continue;
        }
        if (src[j] == '\n') line++;
        buf.write(src[j++]);
      }
      yield (start, buf.toString());
      i = j + q.length;
      continue;
    }
    i++;
  }
}
