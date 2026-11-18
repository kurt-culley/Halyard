/// Placing signals in an 8-byte CAN frame (U14-C01 to C04): Intel (little-endian) and Motorola (big-endian) bit
/// order. Frames are handled as [BigInt]s so the arithmetic is the same in a browser, where Dart ints are not 64-bit.
library;

import 'dart:typed_data';

final _m64 = (BigInt.one << 64) - BigInt.one;
final _byte = BigInt.from(0xff);

/// [len] low bits set.
BigInt bitMask(int len) => len < 64 ? (BigInt.one << (len & 63)) - BigInt.one : _m64;

BigInt _load(Uint8List d) {
  var v = BigInt.zero;
  for (var i = 7; i >= 0; i--) {
    v = ((v << 8) | BigInt.from(d[i])) & _m64;
  }
  return v;
}

void _store(Uint8List d, BigInt v) {
  for (var i = 0; i < 8; i++) {
    d[i] = (v & _byte).toInt();
    v = v >> 8;
  }
}

/// Motorola bit order: the bit after [pos].
int motorolaNext(int pos) => (pos & 7) != 0 ? pos - 1 : pos + 15;

/// Whether a signal of [len] bits from [start] fits the frame.
bool spanValid(int start, int len, {required bool bigEndian}) {
  if (len < 1 || len > 64 || start < 0 || start > 63) return false;
  if (!bigEndian) return start + len <= 64;
  var pos = start;
  for (var i = 1; i < len; i++) {
    pos = motorolaNext(pos);
    if (pos > 63) return false;
  }
  return true;
}

/// The signal's raw bits; 0 when it doesn't fit.
BigInt extractBits(Uint8List d, int start, int len, {required bool bigEndian}) {
  if (!spanValid(start, len, bigEndian: bigEndian)) return BigInt.zero;
  if (!bigEndian) return (_load(d) >> (start & 63)) & bitMask(len);
  var v = BigInt.zero;
  var pos = start;
  for (var i = 0; i < len; i++) {
    v = ((v << 1) | BigInt.from((d[pos >> 3] >> (pos & 7)) & 1)) & _m64;
    pos = motorolaNext(pos);
  }
  return v;
}

/// Writes [value]'s low [len] bits into the frame; nothing when the signal doesn't fit.
void packBits(Uint8List d, int start, int len, BigInt value, {required bool bigEndian}) {
  if (!spanValid(start, len, bigEndian: bigEndian)) return;
  final mask = bitMask(len);
  value &= mask;
  if (!bigEndian) {
    var f = _load(d);
    f &= ~(mask << (start & 63)) & _m64;
    f |= (value << (start & 63)) & _m64;
    _store(d, f);
    return;
  }
  var pos = start;
  for (var i = len - 1; i >= 0; i--) {
    final bit = ((value >> (i & 63)) & BigInt.one).toInt();
    d[pos >> 3] = ((d[pos >> 3] & ~(1 << (pos & 7))) | (bit << (pos & 7))) & 0xff;
    pos = motorolaNext(pos);
  }
}

/// Two's-complement sign extension of a [len]-bit value to 64 bits (as an unsigned 64-bit pattern).
BigInt signExtend(BigInt v, int len) {
  if (len == 0 || len >= 64) return v;
  if ((v & (BigInt.one << ((len - 1) & 63))) != BigInt.zero) v = (v | (_m64 << (len & 63))) & _m64;
  return v;
}
