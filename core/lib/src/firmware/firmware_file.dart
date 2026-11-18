/// Reading firmware (U15 R01 to R05, I01 to I03, F01, F02): `.mefw` files hold a definition, the firmware's identity
/// and the image as regions; Intel HEX text converts to an image. Writing `.mefw` files was the vendor's packaging
/// tool and isn't needed here.
library;

import 'dart:typed_data';

import '../definition/definition.dart';
import '../wire/bytes.dart' show decodeUtf8;

/// A firmware file or image that can't be used.
class FirmwareFileError implements Exception {
  const FirmwareFileError(this.message);
  final String message;
  @override
  String toString() => 'FirmwareFileError: $message';
}

/// Fletcher-16 (mod 255) of a region's data: (sum2 << 8) | sum1.
int firmwareCrc(List<int> data) {
  var s1 = 0, s2 = 0;
  for (final b in data) {
    s1 = (s1 + b) % 255;
    s2 = (s2 + s1) % 255;
  }
  return ((s2 << 8) | s1) & 0xffff;
}

final class FirmwareRegion {
  FirmwareRegion(this.startAddress, this.data, {this.last = false, this.paddingBytes = 0, this.crc = 0});
  int startAddress;
  Uint8List data;
  bool last;
  final int paddingBytes;

  /// As stored in the file (0 for regions from Intel HEX).
  final int crc;

  /// Joins [o] when it directly follows or precedes this region.
  bool merge(FirmwareRegion o) {
    if (startAddress + data.length == o.startAddress) {
      data = Uint8List.fromList([...data, ...o.data]);
      last = o.last;
      return true;
    }
    if (o.startAddress + o.data.length == startAddress) {
      startAddress = o.startAddress;
      data = Uint8List.fromList([...o.data, ...data]);
      return true;
    }
    return false;
  }
}

final class FirmwareImage {
  FirmwareImage(this.regions);
  final List<FirmwareRegion> regions;
  int get size => regions.fold(0, (a, r) => a + r.data.length);
}

class _Reader {
  _Reader(this.b, [this.o = 0]);
  final Uint8List b;
  int o;
  void _need(int n) {
    if (o + n > b.length) throw const FirmwareFileError('unexpected end of file');
  }

  int u8() {
    _need(1);
    return b[o++];
  }

  int u16() {
    _need(2);
    final v = b[o] | (b[o + 1] << 8);
    o += 2;
    return v;
  }

  int u32() {
    _need(4);
    final v = b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
    o += 4;
    return v & 0xffffffff;
  }

  /// As many as are left, up to [n].
  Uint8List bytes(int n) {
    final end = o + n > b.length ? b.length : o + n;
    final r = Uint8List.fromList(b.sublist(o < b.length ? o : b.length, end));
    o += r.length;
    return r;
  }

  String chars(int n) => decodeUtf8(bytes(n));
}

/// Regions from [offset] to the end of [b]: "FW", start, length, last flag, padding, two reserved bytes, the stored
/// CRC, then the data (a short last region keeps what there is).
FirmwareImage readFirmwareImage(Uint8List b, [int offset = 0]) {
  final r = _Reader(b, offset);
  final regions = <FirmwareRegion>[];
  while (r.o != b.length) {
    try {
      if (r.chars(2) != 'FW') throw const FirmwareFileError('no region magic');
      final start = r.u32(), len = r.u32();
      final last = r.u8() == 1;
      final padding = r.u8();
      r.bytes(2);
      final crc = r.u16();
      regions.add(FirmwareRegion(start, r.bytes(len), last: last, paddingBytes: padding, crc: crc));
    } on FirmwareFileError {
      throw const FirmwareFileError('Invalid FW file');
    }
  }
  return FirmwareImage(regions);
}

/// `Convert.ToByte(s, 16)`.
int _hexByte(String s) {
  var i = 0;
  if (s.startsWith('-')) throw const FirmwareFileError('minus sign in hex');
  if (s.startsWith('+')) i++;
  if (i + 1 < s.length && s[i] == '0' && (s[i + 1] == 'x' || s[i + 1] == 'X')) i += 2;
  final start = i;
  var v = 0;
  while (i < s.length && RegExp('[0-9a-fA-F]').hasMatch(s[i])) {
    v = v * 16 + int.parse(s[i], radix: 16);
    i++;
  }
  if (i == start || i < s.length || v > 0xff) throw FirmwareFileError('not a hex byte: $s');
  return v;
}

/// Two bytes big-endian; four bytes little-endian and sign-extended; other sizes 0 (the digits are still checked).
int _address(String chars, int size) {
  final n = size ~/ 2;
  final b = [for (var i = 0; i < n; i++) _hexByte(_sub(chars, i * 2, 2))];
  if (n == 2) return (b[0] << 8) | b[1];
  if (n == 4) return ((b[3] << 24) | (b[2] << 16) | (b[1] << 8) | b[0]).toSigned(32);
  return 0;
}

String _sub(String s, int start, int len) =>
    start >= s.length ? '' : s.substring(start, start + len > s.length ? s.length : start + len);

/// An image from Intel HEX text. Reads go through one reused 1024-character buffer, as the original's did, so a short
/// read at the end of the text sees what the buffer held before. Adjacent regions are joined.
FirmwareImage firmwareImageFromHex(String text) {
  final regions = <FirmwareRegion>[];
  var base = 0, p = 0;
  final buf = List<String>.filled(1024, '\u0000');
  bool eos() => p >= text.length;
  void readBlock(int n) {
    for (var i = 0; i < n && p < text.length; i++) {
      buf[i] = text[p++];
    }
  }

  String str() => buf.join();
  while (!eos()) {
    String ch;
    do {
      ch = text[p++];
    } while (ch != ':' && !eos());
    if (eos()) break;
    readBlock(2);
    final len = _hexByte(_sub(str(), 0, 2));
    readBlock(4);
    final address = _address(str(), 4) + base;
    readBlock(2);
    final type = _hexByte(_sub(str(), 0, 2));
    switch (type) {
      case 0:
        readBlock(len * 2);
        final data = Uint8List.fromList([for (var i = 0; i < len; i++) _hexByte(_sub(str(), i * 2, 2))]);
        regions.add(FirmwareRegion(address, data));
      case 1:
        readBlock(len * 2);
        if (regions.isEmpty) throw const FirmwareFileError('end of file before any data');
        regions.last.last = true;
      case 2:
        readBlock(len * 2);
        base = _address(str(), len * 2) * 16;
      case 4:
        readBlock(len * 2);
        base = _address(str(), len * 2) * 65536;
      case 3 || 5:
        readBlock(len * 2);
      default:
      // other types: their data characters are not skipped
    }
    readBlock(2); // checksum, not verified
  }
  for (var i = 0; i < regions.length - 1; i++) {
    if (regions[i].merge(regions[i + 1])) {
      regions.removeAt(i + 1);
      i--;
    }
  }
  if (regions.isEmpty) throw const FirmwareFileError('Empty FW file');
  return FirmwareImage(regions);
}

/// A `.mefw` file: "MEFW", the header's offset, the definition, then at the offset the firmware's identity (product,
/// model and version with byte lengths, the firmware version), comments, 8 reserved bytes and the regions.
final class FirmwareFile {
  FirmwareFile._(this.info, this.comments, this.image, this._bytes);

  factory FirmwareFile.read(Uint8List b) {
    final r = _Reader(b);
    if (r.chars(4) != 'MEFW') throw const FirmwareFileError('Corrupted firmware file');
    r.o = r.u32();
    String str() => r.chars(r.u8());
    final product = str(), model = str(), version = str(), fw = str();
    final comments = r.chars(r.u16());
    r.bytes(8);
    final info = DeviceInfo(productName: product, modelName: model, version: version, fwVersion: fw);
    return FirmwareFile._(info, comments, readFirmwareImage(b, r.o), b);
  }

  final DeviceInfo info;
  final String comments;
  final FirmwareImage image;
  final Uint8List _bytes;

  /// The definition stored between the header and the firmware's identity.
  Uint8List get definition {
    final r = _Reader(_bytes, 4);
    final offset = r.u32();
    if (offset < r.o) throw const FirmwareFileError('Corrupted firmware file');
    return r.bytes(offset - r.o);
  }
}
