/// Class 1: tables.
library;

import 'dart:typed_data';

import '../bytes.dart';
import '../framing.dart';
import '../reply.dart';

abstract final class TablesCmd {
  static const setTable = 0, getTable = 1, enable = 2, disable = 3, setData = 4, store = 6, setReporting = 7;
}

Frame _req(int cmd, void Function(ByteWriter w) body) => Frame.request(1, cmd, build(body));

Frame getTableRequest(int id) => _req(TablesCmd.getTable, (w) => w.u16(id));
Frame storeTableRequest(int id) => _req(TablesCmd.store, (w) => w.u16(id));
Frame enableTableRequest(int id) => _req(TablesCmd.enable, (w) => w.u16(id));
Frame disableTableRequest(int id) => _req(TablesCmd.disable, (w) => w.u16(id));
Frame setTableReportingRequest(int id, bool enabled) => _req(
  TablesCmd.setReporting,
  (w) =>
      w
        ..u16(id)
        ..u8(enabled ? 1 : 0),
);

/// The whole table: id, blob length (16 bits kept), serialised table.
Frame setTableRequest(int id, Uint8List blob) => _req(
  TablesCmd.setTable,
  (w) =>
      w
        ..u16(id)
        ..u16(blob.length)
        ..bytes(blob),
);

/// Runs of cells: for each offset, the floats that start there.
Frame setTableDataRequest(int id, int elem, List<int> offsets, List<List<double>> chunks) {
  if (offsets.length != chunks.length) throw ArgumentError('offsets and chunks differ in length');
  return _req(TablesCmd.setData, (w) {
    w
      ..u16(id)
      ..u8(elem)
      ..u16(offsets.length);
    for (var i = 0; i < offsets.length; i++) {
      w.u16(offsets[i]);
      chunks[i].forEach(w.f32);
    }
  });
}

/// GetTable and GetDriver: a length-prefixed blob after the entity id.
class BlobReply extends EntityReply {
  const BlobReply(super.status, super.id, this.blob);
  final Uint8List blob;
  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'blob': blob};
}

BlobReply parseBlobReply(Uint8List p, int status, int id) {
  final size = u16(p, 3);
  if (5 + size > p.length) throw const PayloadError('blob longer than payload');
  return BlobReply(status, id, Uint8List.fromList(p.sublist(5, 5 + size)));
}

/// SetTableData echo: element, then (offset, value) pairs.
class SetDataReply extends EntityReply {
  const SetDataReply(super.status, super.id, this.elem, this.offsets, this.values);
  final int elem;
  final List<int> offsets;
  final List<List<double>> values;
  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'elem': elem, 'offsets': offsets, 'values': values};
}

SetDataReply parseSetDataReply(Uint8List p, int status, int id) {
  final elem = u8(p, 3);
  final count = u16(p, 4);
  final offsets = <int>[];
  final values = <List<double>>[];
  for (var i = 0, o = 6; i < count; i++, o += 6) {
    offsets.add(u16(p, o));
    values.add([f32(p, o + 2)]);
  }
  return SetDataReply(status, id, elem, offsets, values);
}
