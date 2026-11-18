/// Class 2: drivers (settings pages).
library;

import 'dart:typed_data';

import '../bytes.dart';
import '../framing.dart';
import '../reply.dart';

abstract final class DriversCmd {
  static const setDriver = 0, getDriver = 1, store = 2, canReservedIds = 3;
}

Frame _req(int cmd, [void Function(ByteWriter w)? body]) => Frame.request(2, cmd, body == null ? null : build(body));

Frame getDriverRequest(int id) => _req(DriversCmd.getDriver, (w) => w.u16(id));
Frame storeDriverRequest(int id) => _req(DriversCmd.store, (w) => w.u16(id));
Frame getCanReservedIdsRequest() => _req(DriversCmd.canReservedIds);
Frame setDriverRequest(int id, Uint8List blob) => _req(
  DriversCmd.setDriver,
  (w) =>
      w
        ..u16(id)
        ..u16(blob.length)
        ..bytes(blob),
);

/// A CAN id the ECU's own streams use, which custom CAN must avoid.
class CanReservedId {
  const CanReservedId(this.messageId, this.streamReceives, this.streamTransmits, this.secondaryStream);
  final int messageId;
  final bool streamReceives;
  final bool streamTransmits;
  final bool secondaryStream;
  Map<String, Object?> toJson() => {
    'messageId': messageId,
    'streamReceives': streamReceives,
    'streamTransmits': streamTransmits,
    'secondaryStream': secondaryStream,
  };
}

class CanReservedIdsReply extends Reply {
  const CanReservedIdsReply(super.status, this.reservedIds);
  final List<CanReservedId> reservedIds;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'reservedIds': [for (final r in reservedIds) r.toJson()],
  };
}

/// Never fails past the status byte: a short list is cut, not rejected.
CanReservedIdsReply parseCanReservedIds(Uint8List p, int status) {
  final ids = <CanReservedId>[];
  if (p.length >= 2) {
    final count = p[1];
    for (var i = 0, o = 2; i < count && o + 5 <= p.length; i++, o += 5) {
      final fl = p[o + 4];
      ids.add(CanReservedId(u32(p, o), (fl & 1) != 0, (fl & 2) != 0, (fl & 4) != 0));
    }
  }
  return CanReservedIdsReply(status, ids);
}
