import 'dart:typed_data';

/// A payload is shorter than its layout, or holds a value its layout forbids. The message factory turns this into
/// "unrecognised frame"; it never escapes the wire layer.
class PayloadError implements Exception {
  const PayloadError(this.message);
  final String message;
  @override
  String toString() => 'PayloadError: $message';
}

void _need(Uint8List p, int o, int n) {
  if (o < 0 || o + n > p.length) throw PayloadError('needs $n byte(s) at $o, payload is ${p.length}');
}

int u8(Uint8List p, int o) {
  _need(p, o, 1);
  return p[o];
}

int i8(Uint8List p, int o) {
  final v = u8(p, o);
  return v >= 0x80 ? v - 0x100 : v;
}

int u16(Uint8List p, int o) {
  _need(p, o, 2);
  return p[o] | (p[o + 1] << 8);
}

int i16(Uint8List p, int o) {
  final v = u16(p, o);
  return v >= 0x8000 ? v - 0x10000 : v;
}

/// Unsigned 32-bit. Built with addition, not `<< 24`, so the result is the same on the VM, under Wasm and in JS.
int u32(Uint8List p, int o) {
  _need(p, o, 4);
  return p[o] + (p[o + 1] << 8) + (p[o + 2] << 16) + p[o + 3] * 0x1000000;
}

double f32(Uint8List p, int o) {
  _need(p, o, 4);
  return ByteData.sublistView(p).getFloat32(o, Endian.little);
}

final _f32 = Float32List(1);

/// The nearest single-precision value, as a double (JavaScript's Math.fround).
double fround(double v) {
  _f32[0] = v;
  return _f32[0];
}

/// Little-endian payload builder. Every write keeps only the low bits of its value, as the protocol does.
class ByteWriter {
  final List<int> _b = [];

  void u8(int v) => _b.add(v & 0xff);
  void u16(int v) =>
      _b
        ..add(v & 0xff)
        ..add((v >> 8) & 0xff);
  void u32(int v) =>
      _b
        ..add(v & 0xff)
        ..add((v >>> 8) & 0xff)
        ..add((v >>> 16) & 0xff)
        ..add((v >>> 24) & 0xff);
  void f32(double v) => _b.addAll(Uint8List.view((ByteData(4)..setFloat32(0, v, Endian.little)).buffer));
  void bytes(List<int> v) => _b.addAll(v);
  void zeros(int n) {
    if (n < 0) throw ArgumentError.value(n, 'n', 'negative length');
    _b.addAll(List<int>.filled(n, 0));
  }

  Uint8List take() => Uint8List.fromList(_b);
}

/// A payload written by [body].
Uint8List build(void Function(ByteWriter w) body) {
  final w = ByteWriter();
  body(w);
  return w.take();
}

/// UTF-8 to text, replacing each invalid sequence with U+FFFD by the WHATWG "maximal subpart" rule. Written out so the
/// result is identical on every platform; a leading byte-order mark is kept as U+FEFF.
String decodeUtf8(Uint8List b, [int start = 0]) {
  final out = StringBuffer();
  var cp = 0, needed = 0, seen = 0, lower = 0x80, upper = 0xbf;
  for (var i = start; i < b.length; i++) {
    final x = b[i];
    if (needed == 0) {
      if (x <= 0x7f) {
        out.writeCharCode(x);
      } else if (x >= 0xc2 && x <= 0xdf) {
        needed = 1;
        cp = x & 0x1f;
      } else if (x >= 0xe0 && x <= 0xef) {
        if (x == 0xe0) lower = 0xa0;
        if (x == 0xed) upper = 0x9f;
        needed = 2;
        cp = x & 0x0f;
      } else if (x >= 0xf0 && x <= 0xf4) {
        if (x == 0xf0) lower = 0x90;
        if (x == 0xf4) upper = 0x8f;
        needed = 3;
        cp = x & 0x07;
      } else {
        out.writeCharCode(0xfffd);
      }
      continue;
    }
    if (x < lower || x > upper) {
      cp = needed = seen = 0;
      lower = 0x80;
      upper = 0xbf;
      out.writeCharCode(0xfffd);
      i--; // this byte starts the next sequence
      continue;
    }
    lower = 0x80;
    upper = 0xbf;
    cp = (cp << 6) | (x & 0x3f);
    if (++seen == needed) {
      out.writeCharCode(cp);
      cp = needed = seen = 0;
    }
  }
  if (needed != 0) out.writeCharCode(0xfffd);
  return out.toString();
}

String toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List fromHex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
