/// Reading DBC files (U24b D01 to D09), as the parser the original bundled read them: messages, signals, value types
/// and custom properties. Other sections are parsed only for the number errors they can raise, then dropped. A file
/// with a malformed number fails as a whole.
library;

import '../logs/number_text.dart';

enum DbcValueType { signed, unsigned, ieeeFloat, ieeeDouble }

final class DbcSignal {
  DbcSignal({
    required this.name,
    required this.multiplexing,
    required this.startBit,
    required this.length,
    required this.byteOrder,
    required this.valueType,
    required this.isInteger,
    required this.factor,
    required this.offset,
    required this.minimum,
    required this.maximum,
    required this.unit,
    required this.receivers,
  });
  final String name, multiplexing, unit;
  final int startBit, length;

  /// 0 Motorola (big-endian), 1 Intel.
  final int byteOrder;
  DbcValueType valueType;

  /// The factor is a whole number.
  final bool isInteger;
  final double factor, offset, minimum, maximum;
  final List<String> receivers;
  final properties = <String, DbcProperty>{};
}

final class DbcMessage {
  DbcMessage(this.id, this.name, this.dlc, this.transmitter);
  int id;

  /// Ids of 0x80000000 and above in the file are extended ids.
  bool isExtended = false;
  final String name, transmitter;
  final int dlc;
  List<DbcSignal> signals = [];
  final properties = <String, DbcProperty>{};
}

enum DbcPropertyType { integer, hex, float, string, enumeration }

final class DbcPropertyDefinition {
  DbcPropertyDefinition(this.name);
  final String name;
  DbcPropertyType type = DbcPropertyType.integer;
  double min = 0, max = 0;
  List<String> enumValues = const [];

  /// int, double or String.
  Object? defaultValue;
}

final class DbcProperty {
  const DbcProperty(this.definition, {this.integer, this.hex, this.float, this.string, this.enumValue});
  final DbcPropertyDefinition definition;
  final int? integer, hex;
  final double? float;
  final String? string, enumValue;
}

int _u32(String s) => parseNetInteger(s, 0, 0xffffffff);
int _u16(String s) => parseNetInteger(s, 0, 0xffff);
int _byte(String s) => parseNetInteger(s, 0, 0xff);
int _i32(String s) => parseNetInteger(s, -2147483648, 2147483647);
double? _tryFloat(String s) {
  try {
    return parseNetSingle(s);
  } on Object {
    return null;
  }
}

/// A .NET pattern as a Dart one: \w and \d are Unicode classes there.
RegExp _rx(String src) {
  const w = r'\p{L}\p{Mn}\p{Nd}\p{Pc}';
  final out = StringBuffer();
  var inClass = false;
  for (var i = 0; i < src.length; i++) {
    final c = src[i];
    if (c == r'\') {
      final n = src[++i];
      if (n == 'w') {
        out.write(inClass ? w : '[$w]');
      } else if (n == 'd') {
        out.write(r'\p{Nd}');
      } else {
        out.write('\\$n');
      }
      continue;
    }
    if (c == '[' && !inClass) {
      inClass = true;
    } else if (c == ']' && inClass) {
      inClass = false;
    }
    out.write(c);
  }
  return RegExp(out.toString(), unicode: true);
}

const _id = r'[a-zA-Z_]\w*';
const _num = r'[\d\+\-eE.]+';
final _message = _rx('BO_ (?<Id>\\d+)\\s+(?<Name>$_id)\\s*:\\s*(?<Size>\\d+)\\s+(?<Transmitter>$_id)');
final _signal = _rx(
  r'\s*SG_\s+(?<Name>[\w]+)\s*(?<Multiplexer>[Mm\d]*)\s*:\s*(?<StartBit>\d+)\|(?<Size>\d+)@(?<ByteOrder>[01])'
  '(?<ValueType>[+-])\\s+\\((?<Factor>$_num),(?<Offset>$_num)\\)\\s+\\[(?<Min>$_num)\\|(?<Max>$_num)\\]\\s+'
  r'"(?<Unit>.*)"\s+(?<Receiver>[\w\s,]+)',
);
final _valType = _rx('SIG_VALTYPE_\\s+(?<MessageId>\\d+)\\s+(?<SignalName>$_id)\\s+[:]*\\s*(?<SignalType>[0123])\\s*;');
final _cmSignal = _rx('CM_ SG_\\s+(?<MessageId>\\d+)\\s+(?<SignalName>$_id)\\s+"*(?<CharString>[^"]*)"*\\s*;');
final _cmMessage = _rx(r'CM_ BO_\s+(?<MessageId>\d+)\s+"*(?<CharString>[^"]*)"*\s*;');
final _propDef = _rx(
  'BA_DEF_(?:\\s+(?<ObjectType>BU_|BO_|SG_|EV_))?\\s+"(?<AttributeName>$_id)"\\s+(?:(?:(?<IsIntegerValue>INT|HEX)'
  '\\s+(?<MinInt>-?\\d+)\\s+(?<MaxInt>-?\\d+))|(?:(?<IsFloatValue>FLOAT)\\s+(?<MinFloat>$_num)\\s+(?<MaxFloat>$_num))'
  '|(?<IsStringValue>STRING)|(?:(?<IsEnumValue>ENUM)\\s+(?<EnumValue>(?:"[^"]*",\\s*)*(?:"[^"]*"))))\\s*;',
);
final _propDefault = _rx('BA_DEF_DEF_\\s+"(?<AttributeName>$_id)"\\s+(?<AttributeValue>-?\\d+|$_num|"[^"]*")\\s*;');
final _prop = _rx(
  'BA_\\s+"(?<AttributeName>$_id)"(?:\\s+(?:(?<NodeEnv>BU_|EV_)\\s+(?<NodeName>$_id))|\\s+(?:(?<Message>BO_)\\s+'
  '(?<MessageId>\\d+))|\\s+(?:(?<Signal>SG_)\\s+(?<MessageId2>\\d+)\\s+(?<SignalName>$_id)))?\\s+'
  '(?<AttributeValue>-?\\d+|$_num|"[^"]*");',
);
final _envVar = _rx(
  'EV_\\s+(?<Name>$_id)\\s*:\\s+(?<VarType>[012])\\s+\\[(?<Min>$_num)\\|(?<Max>$_num)\\]\\s+"(?<Unit>[^"]*)"\\s+'
  '(?<InitialValue>$_num)\\s+(?<VarId>\\d+)\\s+DUMMY_NODE_VECTOR(?<StringDataType>800){0,1}(?<Accessibility2>[0123])'
  '\\s+(?<Node>(?:$_id)(?:,$_id)*)\\s*;',
);
final _envData = _rx('ENVVAR_DATA_\\s+(?<Name>$_id)\\s*:\\s+(?<DataSize>\\d+)\\s*;');
final _valLink = _rx('VAL_\\s+(?<MessageId>\\d+)\\s+(?<SignalName>$_id)\\s+(?<ValueTable>$_id)\\s*;');
final _valTable = _rx(
  'VAL_\\s+(?:(?:(?<MessageId>\\d+)\\s+(?<SignalName>$_id))|(?<EnvVarName>$_id))\\s+(?<ValueDescription>'
  '(?:(?:-?\\d+)\\s+(?:"[^"]*")\\s+)*)(?<ValueDescriptionEnd>(?:(?:-?\\d+)\\s+(?:"[^"]*")\\s*));',
);

const _sections = {
  'CM_',
  'BA_DEF_',
  'BA_',
  'VAL_',
  'CAT_DEF_',
  'CAT_',
  'FILTER',
  'BA_DEF_DEF_',
  'EV_DATA_',
  'ENVVAR_DATA_',
  'SGTYPE_', //
  'SGTYPE_VAL_', 'BA_DEF_SGTYPE_', 'BA_SGTYPE_', 'SIG_TYPE_REF_', 'VAL_TABLE_', 'SIG_GROUP_', 'SIG_VALTYPE_', //
  'SIGTYPE_VALTYPE_', 'BO_TX_BU_', 'BA_DEF_REL_', 'BA_REL_', 'BA_DEF_DEF_REL_', 'BU_SG_REL_', 'BU_EV_REL_', //
  'BU_BO_REL_', 'SG_MUL_VAL_',
};

final _netSpace = RegExp(r'^[\s\u0085​]+|[\s\u0085​]+$', unicode: true);
final _netSpaceStart = RegExp(r'^[\s\u0085​]+', unicode: true);
String _trim(String s) => s.replaceAll(_netSpace, '');
String _trimStart(String s) => s.replaceFirst(_netSpaceStart, '');
String _trimSpaces(String s) => s.replaceAll(RegExp(r'^ +| +$'), '');

/// Object types of property definitions: global 0, node 1, message 2, signal 3, environment variable 4.
class _Builder {
  final messages = <int, DbcMessage>{};
  final signals = <int, Map<String, DbcSignal>>{};
  DbcMessage? current;
  final defs = {
    for (final k in [1, 2, 3, 4, 0]) k: <String, DbcPropertyDefinition>{},
  };

  void addMessage(DbcMessage m) {
    final old = messages[m.id];
    if (old != null) {
      current = old;
      return;
    }
    messages[m.id] = m;
    current = m;
    signals[m.id] = {};
  }

  void addSignal(DbcSignal s) {
    final c = current;
    if (c == null) return;
    signals[c.id]!.putIfAbsent(s.name, () => s);
  }

  DbcSignal? signal(int id, String name) => signals[id]?[name];

  DbcProperty? value(DbcPropertyDefinition d, String text, bool numeric) {
    final acceptAll = d.type.index <= 2 && d.min == 0 && d.max == 0;
    switch (d.type) {
      case DbcPropertyType.integer || DbcPropertyType.hex:
        if (!numeric) return null;
        final v = tryNetInt32(text);
        if (v == null || (!acceptAll && (v < d.min || v > d.max))) return null;
        return d.type == DbcPropertyType.integer ? DbcProperty(d, integer: v) : DbcProperty(d, hex: v);
      case DbcPropertyType.float:
        if (!numeric) return null;
        final v = _tryFloat(text);
        if (v == null || (!acceptAll && (v < d.min || (!(v <= d.max) && !v.isNaN)))) return null;
        return DbcProperty(d, float: v);
      case DbcPropertyType.string:
        return numeric ? null : DbcProperty(d, string: text);
      case DbcPropertyType.enumeration:
        if (numeric) {
          final i = tryNetInt32(text);
          return i == null || i < 0 || i >= d.enumValues.length ? null : DbcProperty(d, enumValue: d.enumValues[i]);
        }
        return d.enumValues.contains(text) ? DbcProperty(d, enumValue: text) : null;
    }
  }

  DbcProperty fromDefault(DbcPropertyDefinition d) {
    final v = d.defaultValue;
    return switch (d.type) {
      DbcPropertyType.integer => DbcProperty(d, integer: v is int ? v : 0),
      DbcPropertyType.hex => DbcProperty(d, hex: v is int ? v : 0),
      DbcPropertyType.float => DbcProperty(d, float: v is double ? v : (v is int ? v.toDouble() : 0)),
      DbcPropertyType.string => DbcProperty(d, string: v is String ? v : null),
      DbcPropertyType.enumeration => DbcProperty(d, enumValue: v is String ? v : null),
    };
  }

  void addDefault(String name, String text, bool numeric) {
    for (final k in [1, 2, 3, 4, 0]) {
      final d = defs[k]![name];
      if (d == null) continue;
      final p = value(d, text, numeric);
      if (p == null) continue;
      d.defaultValue = p.integer ?? p.hex ?? p.float ?? p.string ?? p.enumValue;
    }
  }

  List<DbcMessage> build() {
    for (final d in defs[2]!.values) {
      for (final m in messages.values) {
        for (final sd in defs[3]!.values) {
          for (final s in signals[m.id]!.values) {
            s.properties.putIfAbsent(sd.name, () => fromDefault(sd));
          }
        }
        m.properties.putIfAbsent(d.name, () => fromDefault(d));
      }
    }
    for (final MapEntry(key: id, value: m) in messages.entries) {
      m.signals = [...?signals[id]?.values];
      if (m.id >= 0x80000000) {
        m
          ..isExtended = true
          ..id = m.id - 0x80000000;
      }
    }
    return messages.values.toList();
  }
}

/// The messages of a DBC file. Throws [FormatException] or [RangeError] when a number in it is malformed.
List<DbcMessage> parseDbc(String text) {
  final lines = text.split(RegExp('\r\n|\r|\n'));
  if (text.isEmpty) {
    lines.clear();
  } else if (lines.last.isEmpty && RegExp(r'(\r\n|\r|\n)$').hasMatch(text)) {
    lines.removeLast();
  }
  final b = _Builder();
  var i = 0;
  String? next() => i < lines.length ? lines[i++] : null;
  while (i < lines.length) {
    final line = lines[i++];
    if (_trim(line).isEmpty) continue;
    _line(line, b, next);
  }
  return b.build();
}

void _line(String line, _Builder b, String? Function() next) {
  final ts = _trimStart(line), t = _trim(line);
  if (ts.startsWith('VERSION') ||
      ts.startsWith('BS_') ||
      ts.startsWith('NS_ ') ||
      ts.startsWith('NS_DESC_') ||
      _sections.contains(t) ||
      ts.startsWith('BU_:')) {
    return;
  }
  if (t.startsWith('BO_ ')) {
    final m = _message.firstMatch(line);
    if (m != null) {
      b.addMessage(
        DbcMessage(
          _u32(m.namedGroup('Id')!),
          m.namedGroup('Name')!,
          _u16(m.namedGroup('Size')!),
          m.namedGroup('Transmitter')!,
        ),
      );
    }
    return;
  }
  if (t.startsWith('CM_ ')) {
    var c = t;
    if (!c.endsWith(';')) {
      final parts = [c];
      for (;;) {
        final l = next();
        if (l == null) break;
        parts.add(l);
        if (l.endsWith(';')) break;
      }
      c = parts.map((p) => '$p\r\n').join();
    }
    final m =
        c.startsWith('CM_ SG_') ? _cmSignal.firstMatch(c) : (c.startsWith('CM_ BO_') ? _cmMessage.firstMatch(c) : null);
    if (m != null) _u32(m.namedGroup('MessageId')!);
    return;
  }
  if (ts.startsWith('SG_ ')) {
    final m = _signal.firstMatch(line);
    if (m != null) {
      String g(String n) => m.namedGroup(n)!;
      b.addSignal(
        DbcSignal(
          multiplexing: g('Multiplexer'),
          name: g('Name'),
          startBit: _u16(g('StartBit')),
          length: _u16(g('Size')),
          byteOrder: _byte(g('ByteOrder')),
          valueType: g('ValueType') == '-' ? DbcValueType.signed : DbcValueType.unsigned,
          isInteger: tryNetInt32(g('Factor')) != null,
          factor: parseNetDouble(g('Factor')),
          offset: parseNetDouble(g('Offset')),
          minimum: parseNetDouble(g('Min')),
          maximum: parseNetDouble(g('Max')),
          unit: g('Unit'),
          receivers: g('Receiver').split(RegExp('[ ,]')).where((x) => x.isNotEmpty).toList(),
        ),
      );
    }
    return;
  }
  final t1 = _trimSpaces(line);
  if (t1.startsWith('SIG_VALTYPE_ ')) {
    final m = _valType.firstMatch(t1);
    if (m != null) {
      final v = _u32(m.namedGroup('SignalType')!);
      if (v == 1 || v == 2) {
        b.signal(_u32(m.namedGroup('MessageId')!), m.namedGroup('SignalName')!)?.valueType =
            v == 1 ? DbcValueType.ieeeFloat : DbcValueType.ieeeDouble;
      }
    }
    return;
  }
  if (t1.startsWith('VAL_TABLE_ ')) return;
  if (t1.startsWith('VAL_ ')) {
    final l = _valLink.firstMatch(t1);
    if (l != null) {
      _u32(l.namedGroup('MessageId')!);
      return;
    }
    final m = _valTable.firstMatch(t1);
    if (m != null && m.namedGroup('MessageId') != null) {
      final desc = m.namedGroup('ValueDescription') ?? '';
      final end = m.namedGroup('ValueDescriptionEnd') ?? '';
      if ((desc.isNotEmpty || end.isNotEmpty) && _valueDictOk(desc + end)) _u32(m.namedGroup('MessageId')!);
    }
    return;
  }
  if (t1.startsWith('BA_DEF_DEF_ ')) {
    final m = _propDefault.firstMatch(t1);
    if (m != null) {
      final v = m.namedGroup('AttributeValue')!;
      b.addDefault(m.namedGroup('AttributeName')!, v.replaceAll('"', ''), !v.startsWith('"'));
    }
    return;
  }
  if (t1.startsWith('BA_DEF_ ')) {
    final m = _propDef.firstMatch(t1);
    if (m != null) {
      final obj = const {'BU_': 1, 'BO_': 2, 'SG_': 3, 'EV_': 4}[m.namedGroup('ObjectType') ?? ''] ?? 0;
      final d = DbcPropertyDefinition(m.namedGroup('AttributeName')!);
      final integer = m.namedGroup('IsIntegerValue');
      if (integer == 'INT' || integer == 'HEX') {
        d
          ..type = integer == 'INT' ? DbcPropertyType.integer : DbcPropertyType.hex
          ..min = _i32(m.namedGroup('MinInt')!).toDouble()
          ..max = _i32(m.namedGroup('MaxInt')!).toDouble();
      } else if (m.namedGroup('IsFloatValue') == 'FLOAT') {
        d
          ..type = DbcPropertyType.float
          ..min = parseNetDouble(m.namedGroup('MinFloat')!)
          ..max = parseNetDouble(m.namedGroup('MaxFloat')!);
      } else if (m.namedGroup('IsStringValue') == 'STRING') {
        d.type = DbcPropertyType.string;
      } else if (m.namedGroup('IsEnumValue')?.startsWith('ENUM') ?? false) {
        d
          ..type = DbcPropertyType.enumeration
          ..enumValues = m.namedGroup('EnumValue')!.replaceAll('"', '').replaceAll(' ', '').split(',');
      }
      b.defs[obj]![d.name] = d;
    }
    return;
  }
  if (t1.startsWith('BA_ ')) {
    final m = _prop.firstMatch(t1);
    if (m != null) {
      final raw = m.namedGroup('AttributeValue')!;
      final numeric = !raw.startsWith('"');
      final v = raw.replaceAll('"', '');
      final name = m.namedGroup('AttributeName')!;
      if (m.namedGroup('NodeEnv') != null) {
        // nodes and environment variables are unused
      } else if (m.namedGroup('Message') != null) {
        final d = b.defs[2]![name];
        final id = _u32(m.namedGroup('MessageId')!);
        final msg = b.messages[id];
        if (d != null && msg != null) {
          final p = b.value(d, v, numeric);
          if (p != null) msg.properties.putIfAbsent(name, () => p);
        }
      } else if (m.namedGroup('Signal') != null) {
        final d = b.defs[3]![name];
        final id = _u32(m.namedGroup('MessageId2')!);
        final s = b.signal(id, m.namedGroup('SignalName')!);
        if (d != null && s != null) {
          final p = b.value(d, v, numeric);
          if (p != null) s.properties.putIfAbsent(name, () => p);
        }
      }
    }
    return;
  }
  if (t1.startsWith('EV_ ')) {
    final m = _envVar.firstMatch(t1);
    if (m != null) {
      _u32(m.namedGroup('Accessibility2')!);
      if (m.namedGroup('StringDataType') != '800') {
        final vt = _u32(m.namedGroup('VarType')!);
        for (final k in ['Min', 'Max', 'InitialValue']) {
          if (vt == 0) _i32(m.namedGroup(k)!);
          if (vt == 1) parseNetDouble(m.namedGroup(k)!);
        }
      }
    }
    return;
  }
  if (t1.startsWith('ENVVAR_DATA_ ')) {
    final m = _envData.firstMatch(t1);
    if (m != null) _u32(m.namedGroup('DataSize')!);
  }
}

/// Value descriptions: `key "text"` pairs whose keys are Int32.
bool _valueDictOk(String text) {
  var off = 0;
  for (;;) {
    final q = text.indexOf('"', off);
    if (q == -1) return true;
    if (tryNetInt32(text.substring(off, q)) == null) return false;
    final e = text.indexOf('"', q + 1);
    if (e == -1) return false;
    off = e + 1;
  }
}
