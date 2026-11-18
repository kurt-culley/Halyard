/// Reading definition and calibration XML the way the original tool's serializer did: value syntax (XmlConvert),
/// members taken from their first occurrence in document order, arrays by item element name.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../wire/bytes.dart' show fround;

/// A value in a definition or calibration file has the wrong syntax or range.
class XmlValueError implements Exception {
  const XmlValueError(this.kind, this.text);
  final String kind;
  final String text;
  @override
  String toString() => "'$text' is not a valid $kind value";
}

final _xmlWs = RegExp(r'^[ \t\n\r]+|[ \t\n\r]+$');
final _netWs = RegExp(r'^[\t\n\x0B\f\r ]+|[\t\n\x0B\f\r ]+$');
final _digits = RegExp(r'^[0-9]+$');
final _signedDigits = RegExp(r'^([-+]?)0*([0-9]+)$');
final _float = RegExp(r'^[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?$');
final _b64 = RegExp(r'^[A-Za-z0-9+/]*={0,2}$');

abstract final class XmlConvert {
  static bool toBool(String s) => switch (s.replaceAll(_xmlWs, '')) {
    'true' || '1' => true,
    'false' || '0' => false,
    _ => throw XmlValueError('Boolean', s),
  };

  static int toU16(String s) {
    final t = s.replaceAll(_netWs, '');
    if (!_digits.hasMatch(t)) throw XmlValueError('UInt16', s);
    final d = t.replaceFirst(RegExp('^0+(?=.)'), '');
    final v = d.length > 5 ? null : int.parse(d);
    if (v == null || v > 0xffff) throw XmlValueError('UInt16', s);
    return v;
  }

  static int toI32(String s) {
    final m = _signedDigits.firstMatch(s.replaceAll(_netWs, ''));
    if (m == null || m[2]!.length > 10) throw XmlValueError('Int32', s);
    final v = int.parse(m[2]!) * (m[1] == '-' ? -1 : 1);
    if (v > 2147483647 || v < -2147483648) throw XmlValueError('Int32', s);
    return v;
  }

  /// INF, -INF and NaN as such; otherwise a decimal number, which must stay finite in [round]'s precision.
  static double _number(String s, String kind, double Function(double) round) {
    final t = s.replaceAll(_xmlWs, '');
    switch (t) {
      case 'INF':
        return double.infinity;
      case '-INF':
        return double.negativeInfinity;
      case 'NaN':
        return double.nan;
    }
    if (!_float.hasMatch(t)) throw XmlValueError(kind, s);
    final v = round(double.parse(t));
    if (!v.isFinite) throw XmlValueError(kind, s);
    return v;
  }

  static double toF32(String s) => _number(s, 'Single', fround);
  static double toF64(String s) => _number(s, 'Double', (d) => d);

  static Uint8List toBase64(String s) {
    final t = s.replaceAll(RegExp(r'[ \t\n\r]+'), '');
    if (t.length % 4 != 0 || !_b64.hasMatch(t)) throw XmlValueError('Base64', s);
    return base64.decode(t);
  }

  /// A float as the original wrote it (`Single.ToString("R")`): INF, -INF and NaN as such, otherwise the shortest of
  /// 7 significant digits that reads back to the same float, or 9.
  static String fromF32(double v) {
    if (v.isNaN) return 'NaN';
    if (v == double.infinity) return 'INF';
    if (v == double.negativeInfinity) return '-INF';
    if (v == 0) return v.isNegative ? '-0' : '0';
    final s7 = _general(v, 7);
    return fround(double.parse(s7)) == v ? s7 : _general(v, 9);
  }

  /// .NET "G[p]": fixed notation when -5 < exponent < p, otherwise d.ddddE±xx; trailing zeros dropped.
  static String _general(double v, int p) {
    final parts = v.toStringAsExponential(p - 1).split('e');
    final exp = int.parse(parts[1]);
    final neg = parts[0].startsWith('-');
    var digits = parts[0].replaceAll('-', '').replaceAll('.', '').replaceFirst(RegExp(r'0+$'), '');
    if (digits.isEmpty) digits = '0';
    final String s;
    if (exp <= -5 || exp >= p) {
      final e = exp.abs().toString().padLeft(2, '0');
      s = '${digits[0]}${digits.length > 1 ? '.${digits.substring(1)}' : ''}E${exp < 0 ? '-' : '+'}$e';
    } else if (exp < 0) {
      s = '0.${'0' * (-exp - 1)}$digits';
    } else if (digits.length > exp + 1) {
      s = '${digits.substring(0, exp + 1)}.${digits.substring(exp + 1)}';
    } else {
      s = digits + '0' * (exp + 1 - digits.length);
    }
    return neg ? '-$s' : s;
  }

  static int Function(String) enumOf(List<String> names, String kind) => (s) {
    final i = names.indexOf(s);
    if (i < 0) throw XmlValueError(kind, s);
    return i;
  };
}

/// The source as an XML processor hands it on (XML 1.0 §2.11 and §3.3.3), which package:xml leaves undone: line ends
/// become `\n`, and a literal tab or line end inside an attribute value becomes a space. Character references such as
/// `&#xA;` are untouched, so they still give the character itself.
String normaliseXmlSource(String src) {
  final s = src.replaceAll(RegExp('\r\n?'), '\n');
  final out = StringBuffer();
  var i = 0;
  void skipTo(String end) {
    final j = s.indexOf(end, i);
    final stop = j < 0 ? s.length : j + end.length;
    out.write(s.substring(i, stop));
    i = stop;
  }

  while (i < s.length) {
    final lt = s.indexOf('<', i);
    if (lt < 0) {
      out.write(s.substring(i));
      break;
    }
    out.write(s.substring(i, lt));
    i = lt;
    if (s.startsWith('<!--', i)) {
      skipTo('-->');
    } else if (s.startsWith('<![CDATA[', i)) {
      skipTo(']]>');
    } else if (s.startsWith('<?', i)) {
      skipTo('?>');
    } else if (s.startsWith('<!', i)) {
      skipTo('>');
    } else {
      // A tag: whitespace inside quoted values becomes spaces.
      String? quote;
      while (i < s.length) {
        final c = s[i++];
        if (quote == null) {
          out.write(c);
          if (c == '"' || c == "'") quote = c;
          if (c == '>') break;
        } else {
          out.write(c == '\t' || c == '\n' ? ' ' : c);
          if (c == quote) quote = null;
        }
      }
    }
  }
  return out.toString();
}

/// Character data directly inside [e] (text and CDATA, not nested elements).
String directText(XmlElement e) =>
    e.children.map((n) => n is XmlText ? n.value : (n is XmlCDATA ? n.value : '')).join();

/// Child elements of [e], in document order, optionally only those named [name].
Iterable<XmlElement> childElements(XmlElement e, [String? name]) =>
    name == null ? e.childElements : e.childElements.where((c) => c.name.qualified == name);

XmlElement? firstChild(XmlElement e, String name) {
  for (final c in childElements(e, name)) {
    return c;
  }
  return null;
}

/// Each mapped member from its first occurrence, in document order; unmapped and repeated elements are ignored.
void readMembers(XmlElement e, Map<String, void Function(XmlElement c)> members) {
  final done = <String>{};
  for (final c in e.childElements) {
    final name = c.name.qualified;
    final fn = members[name];
    if (fn == null || !done.add(name)) continue;
    fn(c);
  }
}

/// An array wrapper: items by element name; other children ignored.
List<T> readArray<T>(XmlElement wrapper, Map<String, T Function(XmlElement item)> items) => [
  for (final c in wrapper.childElements)
    if (items[c.name.qualified] case final fn?) fn(c),
];

List<double> readFloats(XmlElement w) => readArray(w, {'float': (x) => XmlConvert.toF32(directText(x))});
List<int> readUShorts(XmlElement w) => readArray(w, {'unsignedShort': (x) => XmlConvert.toU16(directText(x))});
List<String> readStrings(XmlElement w) => readArray(w, {'string': directText});
