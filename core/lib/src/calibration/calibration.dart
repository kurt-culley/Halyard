/// The values of one calibration: what a calibration file holds and what the ECU stores. Structure comes from the
/// [Definition]; this holds numbers only.
library;

import 'dart:typed_data';

import '../definition/definition.dart';
import '../wire/bytes.dart';
import '../wire/framing.dart' show fletcher16;

/// One table's values. [x] has a value per column, [y] per row (used by maps only), [z] per cell, row by row.
final class TableValues {
  TableValues({required this.enabled, required this.x, required this.y, required this.z});

  TableValues.zero(TableDef d)
    : enabled = false,
      x = Float32List(d.cols),
      y = Float32List(d.rows),
      z = Float32List(d.cells);

  bool enabled;
  final Float32List x, y, z;

  TableValues copy() =>
      TableValues(enabled: enabled, x: Float32List.fromList(x), y: Float32List.fromList(y), z: Float32List.fromList(z));
}

/// One driver's values.
final class DriverValues {
  DriverValues({required this.config, required this.outputs, required this.inputs, required this.priv});

  final Float32List config;
  final Uint16List outputs, inputs;
  Uint8List priv;

  DriverValues copy() => DriverValues(
    config: Float32List.fromList(config),
    outputs: Uint16List.fromList(outputs),
    inputs: Uint16List.fromList(inputs),
    priv: Uint8List.fromList(priv),
  );
}

final class Calibration {
  Calibration(this.definition, {required this.tables, required this.drivers, this.notes});

  final Definition definition;
  final Map<int, TableValues> tables;
  final Map<int, DriverValues> drivers;

  /// Free text kept with the calibration file.
  String? notes;

  Calibration copy() => Calibration(
    definition,
    tables: {for (final e in tables.entries) e.key: e.value.copy()},
    drivers: {for (final e in drivers.entries) e.key: e.value.copy()},
    notes: notes,
  );

  /// The hash the ECU reports for the whole calibration: drivers then tables, in definition order.
  int get overallHash {
    final b = <int>[];
    for (final id in definition.drivers.keys) {
      final h = driverHash(definition.drivers[id]!, drivers[id]!);
      b
        ..add(h & 0xff)
        ..add(h >> 8);
    }
    for (final id in definition.tables.keys) {
      final h = tableHash(definition.tables[id]!, tables[id]!);
      b
        ..add(h & 0xff)
        ..add(h >> 8);
    }
    return fletcher16(b);
  }

  /// Hash of one table or driver, or null for an unknown id.
  int? hashFor(int id) {
    if (definition.tables[id] case final d?) return tableHash(d, tables[id]!);
    if (definition.drivers[id] case final d?) return driverHash(d, drivers[id]!);
    return null;
  }
}

/// Copies [src] into [dst] as far as both reach, leaving an element alone when the new value equals it. 0 equals -0,
/// so a zero keeps its sign: the original's arrays and parameters compared with `Single.Equals` before storing, and the
/// sign shows in saved files and hashes.
void assignFloats(Float32List dst, List<double> src) {
  for (var i = 0; i < dst.length && i < src.length; i++) {
    if (dst[i] != src[i]) dst[i] = src[i];
  }
}

/// A table or driver blob that doesn't fit its definition.
class BlobError implements Exception {
  const BlobError(this.id, this.message);
  final int id;
  final String message;
  @override
  String toString() => 'Entity $id: $message';
}

Uint8List _floats(Float32List v, int n) {
  final out = ByteData(n * 4);
  for (var i = 0; i < n; i++) {
    out.setFloat32(i * 4, i < v.length ? v[i] : 0, Endian.little);
  }
  return out.buffer.asUint8List();
}

List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];

/// Wire form of a table: type, enabled, rows, cols, then y (maps only), x and z as little-endian floats.
Uint8List tableBlob(TableDef d, TableValues v) => build((w) {
  w
    ..u8(d.type)
    ..u8(v.enabled ? 1 : 0)
    ..u8(d.rows)
    ..u8(d.cols);
  if (d.isMap) w.bytes(_floats(v.y, d.rows));
  w
    ..bytes(_floats(v.x, d.cols))
    ..bytes(_floats(v.z, d.cells));
});

/// A table from its wire form, applied over [current] (zeros without one). A curve's wire form has no row axis, so
/// [current]'s is kept.
TableValues parseTableBlob(TableDef d, Uint8List b, [TableValues? current]) {
  if (b.length < 4 || b[0] != d.type || b[2] != d.rows || b[3] != d.cols) {
    throw BlobError(d.id, 'table shape differs from the definition');
  }
  final v = current?.copy() ?? TableValues.zero(d);
  var o = 4;
  void read(Float32List into) {
    final n = into.length;
    final got = <double>[];
    for (var i = 0; i < n; i++, o += 4) {
      try {
        got.add(f32(b, o));
      } on PayloadError {
        throw BlobError(d.id, 'table data is short');
      }
    }
    assignFloats(into, got);
  }

  if (d.isMap) read(v.y);
  read(v.x);
  read(v.z);
  v.enabled = b[1] != 0;
  return v;
}

int tableHash(TableDef d, TableValues v) {
  final h1 = d.isMap ? fletcher16(_floats(v.y, d.rows)) : 0;
  final h0 = fletcher16(_floats(v.x, d.cols));
  final hz = fletcher16(_floats(v.z, d.cells));
  return fletcher16([..._le16(h0), ..._le16(h1), ..._le16(hz)]);
}

/// Wire form of a driver: counts, config floats, output ids, input ids, then the private block.
Uint8List driverBlob(DriverDef d, DriverValues v) => build((w) {
  w
    ..u8(d.configCount)
    ..u8(d.outputCount)
    ..u8(d.inputCount)
    ..bytes(_floats(v.config, d.configCount));
  for (var i = 0; i < d.outputCount; i++) {
    w.u16(v.outputs[i]);
  }
  for (var i = 0; i < d.inputCount; i++) {
    w.u16(v.inputs[i]);
  }
  if (d.privSize > 0) w.bytes(v.priv);
});

/// A driver from its wire form, applied over [current] (zeros without one).
DriverValues parseDriverBlob(DriverDef d, Uint8List b, [DriverValues? current]) {
  if (b.length < 3 || b[0] != d.configCount || b[1] != d.outputCount || b[2] != d.inputCount) {
    throw BlobError(d.id, 'driver shape differs from the definition');
  }
  try {
    var o = 3;
    final config = current == null ? Float32List(d.configCount) : Float32List.fromList(current.config);
    assignFloats(config, [for (var i = 0; i < d.configCount; i++, o += 4) f32(b, o)]);
    final outputs = Uint16List(d.outputCount);
    for (var i = 0; i < d.outputCount; i++, o += 2) {
      outputs[i] = u16(b, o);
    }
    final inputs = Uint16List(d.inputCount);
    for (var i = 0; i < d.inputCount; i++, o += 2) {
      inputs[i] = u16(b, o);
    }
    if (d.privSize > 0 && b.length - o != d.privSize) throw BlobError(d.id, 'private data size differs');
    final priv = d.privSize > 0 ? Uint8List.fromList(b.sublist(o)) : Uint8List(0);
    return DriverValues(config: config, outputs: outputs, inputs: inputs, priv: priv);
  } on PayloadError {
    throw BlobError(d.id, 'driver data is short');
  }
}

int driverHash(DriverDef d, DriverValues v) {
  final hc = fletcher16(_floats(v.config, d.configCount));
  List<int> ids(Uint16List a) => [for (final x in a) ..._le16(x)];
  final hi = fletcher16(ids(v.inputs));
  final ho = fletcher16(ids(v.outputs));
  return fletcher16([..._le16(hc), ..._le16(hi), ..._le16(ho)]);
}
