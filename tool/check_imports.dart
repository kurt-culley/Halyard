// Checks the layer and folder rules in docs/ARCHITECTURE.md. Run from the repository root:
//
//   dart run tool/check_imports.dart
//
// Exits 1 and lists every violation. Rules:
//   - core/lib has no Flutter and no dart:io;
//   - the app imports the core only through package:halyard_core/halyard_core.dart;
//   - a feature never imports another feature;
//   - instruments never import the core (they take descriptors and value sources);
//   - no utils/, helpers/ or common/ folders, and at most three folder levels under lib/;
//   - no barrel files: apart from the core's entry point, a file made only of exports is refused.
import 'dart:io';

final _import = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);
const _banned = {'utils', 'helpers', 'common'};

void main() {
  final problems = <String>[];
  for (final pkg in ['core', 'app']) {
    final lib = Directory('$pkg/lib');
    if (!lib.existsSync()) continue;
    for (final f in lib.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final rel = f.path.substring(lib.path.length + 1).replaceAll(r'\', '/');
      final dirs = rel.split('/')..removeLast();
      final where = '$pkg/lib/$rel';
      if (dirs.length > 3) {
        problems.add('$where: more than three folder levels under lib/');
      }
      for (final d in dirs) {
        if (_banned.contains(d)) problems.add('$where: "$d/" folders are not allowed; put code with what owns it');
      }
      final text = f.readAsStringSync();
      final targets = [for (final m in _import.allMatches(text)) m[1]!];
      final code = text.split('\n').where((l) => l.trim().isNotEmpty && !l.trim().startsWith('//')).toList();
      final onlyExports = code.isNotEmpty && code.every((l) => RegExp(r'^\s*(export\b|library\b|\S*;$)').hasMatch(l));
      if (onlyExports && code.any((l) => l.trimLeft().startsWith('export')) && where != 'core/lib/halyard_core.dart') {
        problems.add('$where: barrel file');
      }
      for (final t in targets) {
        if (pkg == 'core' && (t == 'dart:io' || t.startsWith('package:flutter'))) {
          problems.add('$where: the core may not import $t');
        }
        if (pkg == 'app' && t.startsWith('package:halyard_core/') && t != 'package:halyard_core/halyard_core.dart') {
          problems.add('$where: import package:halyard_core/halyard_core.dart, not $t');
        }
        if (pkg == 'app' && dirs.isNotEmpty && dirs.first == 'features' && dirs.length > 1) {
          final mine = dirs[1];
          final other = RegExp(
            r'(?:^|/)features/([^/]+)/',
          ).firstMatch(t.startsWith('package:') ? t : _resolve(dirs, t));
          if (other != null && other[1] != mine) problems.add('$where: feature "$mine" imports feature "${other[1]}"');
        }
        if (pkg == 'app' && dirs.isNotEmpty && dirs.first == 'instruments' && t.startsWith('package:halyard_core')) {
          problems.add('$where: instruments take descriptors and value sources, not core types');
        }
      }
    }
  }
  for (final p in problems) {
    stderr.writeln(p);
  }
  if (problems.isNotEmpty) exit(1);
  stdout.writeln('Import and folder rules hold.');
}

/// A relative import resolved against [dirs], as a path under lib/.
String _resolve(List<String> dirs, String rel) {
  final parts = [...dirs];
  for (final p in rel.split('/')) {
    if (p == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (p != '.') {
      parts.add(p);
    }
  }
  return parts.join('/');
}
