/// Loads the golden vectors written by tool/export_vectors.mjs and puts Dart values in the same JSON-safe form.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';

List<dynamic> loadVectors(String name) => jsonDecode(File('test/vectors/$name').readAsStringSync()) as List<dynamic>;

/// Bytes as "hex:..", non-finite numbers as strings, recursively.
Object? norm(Object? v) => switch (v) {
  Uint8List b => 'hex:${toHex(b)}',
  double d when d.isNaN => 'NaN',
  double d when d.isInfinite => d > 0 ? 'Infinity' : '-Infinity',
  Map<dynamic, dynamic> m => {for (final e in m.entries) e.key: norm(e.value)},
  List<dynamic> l => [for (final x in l) norm(x)],
  _ => v,
};

/// A frame from the vectors' hex form: type, cls, cmd, payload.
Frame frameFromHex(String hex) {
  final b = fromHex(hex);
  return Frame(b[0], b[1], b[2], Uint8List.sublistView(b, 3));
}

/// Vector bytes ("hex:..") back to a Uint8List.
Uint8List bytesArg(Object? v) => fromHex((v! as String).substring(4));
