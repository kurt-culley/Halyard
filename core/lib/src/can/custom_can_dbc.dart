/// DBC files to and from the custom CAN configuration (U24b), as the original's editors imported and exported them.
library;

import '../logs/number_text.dart' show formatFloatR;
import '../wire/bytes.dart' show fround;
import 'custom_can.dart';
import 'dbc.dart';

const _nl = '\r\n';

String _x3(int v) => (v & 0xffffffff).toRadixString(16).toUpperCase().padLeft(3, '0');

final class DbcImportResult {
  int added = 0, skipped = 0;
  final notes = <String>[];
}

/// The original's summary box.
String dbcImportSummary(DbcImportResult r) {
  var t = 'DBC import complete:\n✅ ${r.added} message slots added\n⏭ ${r.skipped} skipped';
  if (r.notes.isNotEmpty) {
    t += '\n\nNotes:\n${r.notes.take(15).join('\n')}';
    if (r.notes.length > 15) t += '\n… and ${r.notes.length - 15} more';
  }
  return t;
}

/// The original's picker line for a message.
String dbcPickText(DbcMessage m) {
  final id = m.id & 0x1fffffff;
  return '0x${_x3(id)} ($id) - ${m.name}  [${m.signals.length} signals]';
}

/// Asked before a message with the same id is replaced: the original's "CAN ID Conflict" question.
typedef ReplaceQuestion = Future<bool> Function(String text, String title);

bool _fits(DbcSignal s) => s.startBit <= 63 && s.length >= 1 && s.length <= 64;

/// Byte/UInt32.TryParse for the mux value after "m".
int? _unsigned(String s) {
  final m = RegExp(r'^[\t\n\v\f\r ]*([+-])?(\d+)[\t\n\v\f\r ]*$').firstMatch(s);
  if (m == null) return null;
  final v = int.tryParse(m[2]!);
  if (v == null || (m[1] == '-' && v != 0) || v > 0xffffffff) return null;
  return v;
}

void _resetRx(RxMessage m) {
  m
    ..enabled = false
    ..extended = false
    ..bigEndian = false
    ..muxEnabled = false
    ..canId = 0
    ..muxStartBit = 0
    ..muxBitLength = 1
    ..muxMatch = 0;
  for (final s in m.signals) {
    s
      ..enabled = false
      ..format = 0
      ..startBit = 0
      ..bitLength = 1
      ..timeoutMs = 0
      ..dstLinkId = 0
      ..mult = 1
      ..offset = 0
      ..fallback = 0;
  }
}

void _resetTx(TxMessage m) {
  m
    ..enabled = false
    ..extended = false
    ..canId = 0
    ..mode = 0
    ..freqHz = 10
    ..triggerLinkId = 0;
  for (final s in m.signals) {
    s
      ..enabled = false
      ..bigEndian = false
      ..signed = false
      ..startBit = 0
      ..bitLength = 1
      ..srcLinkId = 0
      ..mult = 1
      ..offset = 0
      ..constValue = 0;
  }
}

/// The input editor's FillSlotSignals.
void fillRxSignals(RxMessage slot, List<DbcSignal> sigs, String msgName, List<String> notes) {
  var k = 0;
  for (final s in sigs) {
    if (k >= slot.signals.length) {
      notes.add('$msgName.${s.name}: more than 8 signals in one message');
      continue;
    }
    if (!_fits(s)) {
      notes.add('$msgName.${s.name}: does not fit an 8-byte frame');
      continue;
    }
    var format = 0;
    if (s.valueType == DbcValueType.ieeeDouble) {
      notes.add('$msgName.${s.name}: 64-bit float signals are not supported');
      continue;
    }
    if (s.valueType == DbcValueType.ieeeFloat) {
      if (s.length != 32) {
        notes.add('$msgName.${s.name}: float signals must be 32 bits');
        continue;
      }
      format = 3;
    } else if (s.valueType == DbcValueType.signed) {
      format = 1;
    }
    slot.signals[k++]
      ..enabled = true
      ..startBit = s.startBit & 0xff
      ..bitLength = s.length & 0xff
      ..format = format
      ..mult = fround(s.factor)
      ..offset = fround(s.offset)
      ..timeoutMs = 0
      ..fallback = 0
      ..dstLinkId = 0;
  }
}

/// The output editor's FillSlotSignals.
void fillTxSignals(TxMessage slot, List<DbcSignal> sigs, String msgName, List<String> notes) {
  var k = 0;
  for (final s in sigs) {
    if (k >= slot.signals.length) {
      notes.add('$msgName.${s.name}: more than 8 signals in one message');
      continue;
    }
    if (!_fits(s)) {
      notes.add('$msgName.${s.name}: does not fit an 8-byte frame');
      continue;
    }
    if (s.valueType == DbcValueType.ieeeFloat || s.valueType == DbcValueType.ieeeDouble) {
      notes.add('$msgName.${s.name}: float signals are not supported on transmit');
      continue;
    }
    slot.signals[k++]
      ..enabled = true
      ..bigEndian = s.byteOrder == 0
      ..signed = s.valueType == DbcValueType.signed
      ..startBit = s.startBit & 0xff
      ..bitLength = s.length & 0xff
      ..mult = fround(s.factor)
      ..offset = fround(s.offset)
      ..srcLinkId = 0
      ..constValue = 0;
  }
}

Future<bool> _replaceExisting<M>(
  List<M> listed,
  int id,
  DbcImportResult r,
  ReplaceQuestion ask,
  void Function(M) reset,
) async {
  if (listed.isEmpty) return true;
  if (!await ask('A message with ID 0x${_x3(id)} already exists. Replace it?', 'CAN ID Conflict')) {
    r.skipped++;
    return false;
  }
  listed.forEach(reset);
  return true;
}

/// Imports the chosen messages and signals into the receive messages: a multiplexed message takes a slot per mux
/// value; existing ids are replaced only when [ask] agrees; ids in [reserved] are skipped.
Future<DbcImportResult> importRx(
  CustomCanConfig c,
  List<(DbcMessage, List<DbcSignal>)> selection, {
  required ReplaceQuestion ask,
  Set<int> reserved = const {},
}) async {
  final r = DbcImportResult();
  RxMessage? free() => c.rx.where((m) => !m.enabled).firstOrNull;
  // The original's message list, refreshed after a replace (and at the end), not after each add.
  var items = c.rx.where((m) => m.enabled).toList();
  for (final (msg, sigs) in selection) {
    final id = msg.id & 0x1fffffff;
    if (reserved.contains(id)) {
      r
        ..skipped += 1
        ..notes.add('0x${_x3(id)}: used by the selected OEM CAN stream');
      continue;
    }
    final listed = items.where((m) => (m.canId & 0xffffffff) == id).toList();
    if (!await _replaceExisting(listed, id, r, ask, _resetRx)) continue;
    if (listed.isNotEmpty) items = c.rx.where((m) => m.enabled).toList();
    final mux = sigs.where((s) => s.multiplexing == 'M').firstOrNull;
    final first = sigs.where((s) => !identical(s, mux)).firstOrNull ?? mux;
    final big = first != null && first.byteOrder == 0;
    final plain = <DbcSignal>[];
    final frames = <int, List<DbcSignal>>{};
    for (final s in sigs) {
      if (identical(s, mux)) continue;
      if ((s.byteOrder == 0) != big) {
        r.notes.add('${msg.name}.${s.name}: mixed endianness in one message is not supported');
        continue;
      }
      final mm = s.multiplexing;
      final f = mm.isNotEmpty && (mm[0] == 'm' || mm[0] == 'M') ? _unsigned(mm.substring(1)) : null;
      if (f != null) {
        (frames[f] ??= []).add(s);
      } else {
        plain.add(s);
      }
    }
    final ext = msg.isExtended || isExtendedCanId(id);
    if (mux == null) {
      final slot = free();
      if (slot == null) {
        r
          ..skipped += 1
          ..notes.add('0x${_x3(id)}: no free message slots');
        continue;
      }
      slot
        ..enabled = true
        ..canId = id
        ..extended = ext
        ..bigEndian = big;
      fillRxSignals(slot, plain, msg.name, r.notes);
      r.added++;
      continue;
    }
    if (mux.startBit > 63 || mux.length < 1 || mux.length > 32) {
      r
        ..skipped += 1
        ..notes.add('0x${_x3(id)}: multiplexor does not fit (start ${mux.startBit}, length ${mux.length})');
      continue;
    }
    if (frames.isEmpty) frames[0] = [];
    for (final key in frames.keys.toList()..sort()) {
      final slot = free();
      if (slot == null) {
        r.notes.add('0x${_x3(id)} frame $key: no free message slots');
        continue;
      }
      slot
        ..enabled = true
        ..canId = id
        ..extended = ext
        ..bigEndian = big
        ..muxEnabled = true
        ..muxStartBit = mux.startBit & 0xff
        ..muxBitLength = mux.length & 0xff
        ..muxMatch = key;
      fillRxSignals(slot, [...frames[key]!, ...plain], msg.name, r.notes);
      r.added++;
    }
  }
  return r;
}

int _roundEven(double x) {
  final f = x.floorToDouble(), d = x - f;
  return (d > 0.5 || (d == 0.5 && f % 2 != 0) ? f + 1 : f).toInt();
}

/// FrequencyFromDbc: from GenMsgCycleTime, else 10 Hz.
int frequencyFromDbc(DbcMessage m) {
  final v = m.properties['GenMsgCycleTime']?.integer;
  if (v != null && v > 0) return _roundEven(1000 / v).clamp(1, 1000);
  return 10;
}

/// Imports the chosen messages into the transmit messages; multiplexed messages can't be transmitted.
Future<DbcImportResult> importTx(
  CustomCanConfig c,
  List<(DbcMessage, List<DbcSignal>)> selection, {
  required ReplaceQuestion ask,
  Set<int> reserved = const {},
}) async {
  final r = DbcImportResult();
  var items = c.tx.where((m) => m.enabled).toList();
  for (final (msg, sigs) in selection) {
    final id = msg.id & 0x1fffffff;
    if (reserved.contains(id)) {
      r
        ..skipped += 1
        ..notes.add('0x${_x3(id)}: used by the selected OEM CAN stream');
      continue;
    }
    if (sigs.any((s) => s.multiplexing.isNotEmpty)) {
      r
        ..skipped += 1
        ..notes.add('0x${_x3(id)}: multiplexed messages are not supported on transmit');
      continue;
    }
    final listed = items.where((m) => (m.canId & 0xffffffff) == id).toList();
    if (!await _replaceExisting(listed, id, r, ask, _resetTx)) continue;
    if (listed.isNotEmpty) items = c.tx.where((m) => m.enabled).toList();
    final slot = c.tx.where((m) => !m.enabled).firstOrNull;
    if (slot == null) {
      r
        ..skipped += 1
        ..notes.add('0x${_x3(id)}: no free message slots');
      continue;
    }
    slot
      ..enabled = true
      ..canId = id
      ..extended = msg.isExtended || isExtendedCanId(id)
      ..mode = 0
      ..freqHz = frequencyFromDbc(msg)
      ..triggerLinkId = 0;
    fillTxSignals(slot, sigs, msg.name, r.notes);
    r.added++;
  }
  return r;
}

// ---------------------------------------------------------------- export

int _rawId(int id, bool extended) => extended ? (id | 0x80000000) & 0xffffffff : id & 0xffffffff;
String _messageName(int id) => 'MSG_${_x3(id)}';

final _letterOrDigit = RegExp(r'^[\p{L}\p{Nd}]$', unicode: true);

/// SignalName: the channel's name with anything but ASCII letters, digits and "_" made "_", or SIG and the start bit.
String dbcSignalName(String? linkName, int startBit) {
  if (linkName == null || RegExp(r'^[\s\u0085]*$').hasMatch(linkName)) return 'SIG$startBit';
  final b = StringBuffer();
  for (final r in linkName.runes) {
    final ch = String.fromCharCode(r);
    final keep = (_letterOrDigit.hasMatch(ch) && r <= 127) || ch == '_';
    b.write(keep ? ch : (r > 0xffff ? '__' : '_'));
  }
  final s = b.toString();
  return RegExp(r'^\p{Nd}', unicode: true).hasMatch(s) ? '_$s' : s;
}

String _unique(Set<String> used, String name) {
  var n = name;
  var k = 2;
  while (used.contains(n.toLowerCase())) {
    n = '${name}_${k++}';
  }
  used.add(n.toLowerCase());
  return n;
}

String _header() => ['VERSION ""', '', 'NS_ :', '', 'BS_:', '', 'BU_: ECU'].map((l) => '$l$_nl').join();

/// The receive messages as a DBC file, the original's way: messages by id (multiplexed after plain), a MUX signal
/// for a multiplexed group, float signals listed in SIG_VALTYPE_.
String exportRxDbc(List<RxMessage> messages, String? Function(int linkId) linkName) {
  final body = StringBuffer();
  final valTypes = <(int, String)>[];
  final groups = <({String key, int canId, bool mux, List<RxMessage> items})>[];
  for (final m in messages.where((x) => x.enabled)) {
    final key = '${m.canId & 0xffffffff}|${m.muxEnabled}';
    var g = groups.where((x) => x.key == key).firstOrNull;
    if (g == null) {
      g = (key: key, canId: m.canId & 0xffffffff, mux: m.muxEnabled, items: <RxMessage>[]);
      groups.add(g);
    }
    g.items.add(m);
  }
  final ordered = [for (final (i, g) in groups.indexed) (g, i)]..sort((a, b) {
    final c = a.$1.canId.compareTo(b.$1.canId);
    if (c != 0) return c;
    final d = (a.$1.mux ? 1 : 0) - (b.$1.mux ? 1 : 0);
    return d != 0 ? d : a.$2 - b.$2;
  });
  for (final (g, _) in ordered) {
    final items = [for (final (i, m) in g.items.indexed) (m, i)]..sort((a, b) {
      final c = (a.$1.muxMatch & 0xffffffff).compareTo(b.$1.muxMatch & 0xffffffff);
      return c != 0 ? c : a.$2 - b.$2;
    });
    final first = items.first.$1;
    final raw = _rawId(first.canId, first.extended);
    final used = <String>{};
    body.write(
      '$_nl'
      'BO_ $raw ${_messageName(first.canId)}: 8 Vector__XXX$_nl',
    );
    if (first.muxEnabled) {
      body.write(
        ' SG_ ${_unique(used, 'MUX')} M : ${first.muxStartBit}|${first.muxBitLength}@${first.bigEndian ? '0' : '1'}+ '
        '(1,0) [0|0] "" ECU$_nl',
      );
    }
    for (final (m, _) in items) {
      final mux = m.muxEnabled ? 'm${m.muxMatch & 0xffffffff} ' : '';
      final order = m.bigEndian ? '0' : '1';
      for (final s in m.signals.where((x) => x.enabled)) {
        final n = _unique(used, dbcSignalName(linkName(s.dstLinkId), s.startBit));
        body.write(
          ' SG_ $n $mux: ${s.startBit}|${s.bitLength}@$order${s.format == 1 ? '-' : '+'} '
          '(${formatFloatR(s.mult)},${formatFloatR(s.offset)}) [0|0] "" ECU$_nl',
        );
        if (s.format == 3) valTypes.add((raw, n));
      }
    }
  }
  final out = StringBuffer(_header())..write(body);
  for (final (raw, n) in valTypes) {
    out.write(
      '$_nl'
      'SIG_VALTYPE_ $raw $n : 1;$_nl',
    );
  }
  return out.toString();
}

/// The transmit messages as a DBC file, with each message's cycle time.
String exportTxDbc(List<TxMessage> messages, String? Function(int linkId) linkName) {
  final body = StringBuffer();
  final cycles = <(int, int)>[];
  final ordered = [for (final (i, m) in messages.where((x) => x.enabled).indexed) (m, i)]..sort((a, b) {
    final c = (a.$1.canId & 0xffffffff).compareTo(b.$1.canId & 0xffffffff);
    return c != 0 ? c : a.$2 - b.$2;
  });
  for (final (m, _) in ordered) {
    final raw = _rawId(m.canId, m.extended);
    final used = <String>{};
    body.write(
      '$_nl'
      'BO_ $raw ${_messageName(m.canId)}: 8 ECU$_nl',
    );
    for (final s in m.signals.where((x) => x.enabled)) {
      final n = _unique(used, dbcSignalName(s.srcLinkId != 0 ? linkName(s.srcLinkId) : null, s.startBit));
      body.write(
        ' SG_ $n : ${s.startBit}|${s.bitLength}@${s.bigEndian ? '0' : '1'}${s.signed ? '-' : '+'} '
        '(${formatFloatR(s.mult)},${formatFloatR(s.offset)}) [0|0] "" Vector__XXX$_nl',
      );
    }
    cycles.add((raw, _roundEven(1000 / (m.freqHz < 1 ? 1 : m.freqHz)).clamp(1, 1 << 31)));
  }
  final out = StringBuffer(_header())..write(body);
  if (cycles.isNotEmpty) {
    out.write(
      '$_nl'
      'BA_DEF_ BO_  "GenMsgCycleTime" INT 0 60000;$_nl'
      'BA_DEF_DEF_  "GenMsgCycleTime" 100;$_nl',
    );
    for (final (raw, ms) in cycles) {
      out.write('BA_ "GenMsgCycleTime" BO_ $raw $ms;$_nl');
    }
  }
  return out.toString();
}
