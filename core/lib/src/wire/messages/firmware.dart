/// Class 5: firmware update. After the start request the bootloader drives the transfer: it sends *requests* for
/// region info and region data, and the host answers each one.
library;

import 'dart:typed_data';

import '../bytes.dart';
import '../framing.dart';

abstract final class FirmwareCmd {
  static const start = 0, regionInfo = 1, regionData = 2, status = 3, enterBootloader = 4;
}

/// One byte per character, anything outside ASCII as "?". Lengths are taken in UTF-16 units, as the original does.
List<int> _ascii(String s) => [for (final r in s.runes) r > 0x7f ? 0x3f : r];

/// Starts an update: region count, eight reserved bytes, then the identity the image is built for.
Frame startFirmwareUpdateRequest(int regions, String product, String model, String version, String fwVersion) =>
    Frame.request(
      5,
      FirmwareCmd.start,
      build((w) {
        w
          ..u8(regions)
          ..zeros(8)
          ..u8(product.length)
          ..bytes(_ascii(product));
        for (final s in [model, version, fwVersion]) {
          w
            ..u16(s.length & 0xff)
            ..bytes(_ascii(s));
        }
      }),
    );

Frame enterBootloaderRequest() => Frame.request(5, FirmwareCmd.enterBootloader);

/// The host aborts an update by answering with a failed status report.
Frame stopFirmwareUpdateFrame() => Frame(MsgType.rsp, 5, FirmwareCmd.status, Uint8List.fromList([1]), true);

/// Answer to a region-info request.
Frame regionInfoAnswer(int idx, int startAddress, int length, int paddingBytes, int crc) => Frame(
  MsgType.rsp,
  5,
  FirmwareCmd.regionInfo,
  build(
    (w) =>
        w
          ..u8(0)
          ..u8(idx)
          ..u32(startAddress)
          ..u32(length)
          ..u8(paddingBytes)
          ..u16(crc),
  ),
  true,
);

/// Answer to a region-data request: [length] bytes of [data] from [offset].
Frame regionDataAnswer(int idx, int offset, int length, Uint8List data) {
  if (offset < 0 || length < 0 || offset + length > data.length) throw RangeError('region data out of range');
  return Frame(
    MsgType.rsp,
    5,
    FirmwareCmd.regionData,
    build(
      (w) =>
          w
            ..u8(0)
            ..u8(idx)
            ..u32(offset)
            ..u32(length)
            ..bytes(data.sublist(offset, offset + length)),
    ),
    true,
  );
}

/// What the bootloader asked for. [offset] and [length] are set for data requests only.
class FirmwareRequest {
  const FirmwareRequest(this.regionIdx, [this.offset, this.length]);
  final int regionIdx;
  final int? offset;
  final int? length;
  Map<String, Object?> toJson() => {
    'regionIdx': regionIdx,
    if (offset != null) 'offset': offset,
    if (length != null) 'length': length,
  };
}

FirmwareRequest parseFirmwareRequest(Frame f) {
  final p = f.payload;
  final idx = u8(p, 0);
  if (f.cmd == FirmwareCmd.regionInfo) return FirmwareRequest(idx);
  return FirmwareRequest(idx, u32(p, 1), u32(p, 5));
}
