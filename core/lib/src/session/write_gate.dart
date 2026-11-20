/// The one path to the ECU for any change (U03-W01 to W07, U04-W01, K01 to K04). It sends what the original sent and
/// applies the original's checks, nothing more; the deviations are those in behaviour-changes.md (a batch stops at
/// its first failed request, so nothing unacknowledged is stored).
library;

import 'dart:typed_data';

import '../calibration/calibration.dart';
import '../calibration/driver_settings.dart';
import '../link/channel.dart';
import '../wire/framing.dart';
import '../wire/messages/drivers.dart';
import '../wire/messages/tables.dart';
import 'session.dart';

/// How a save went: done, or the first request that failed and why.
final class WriteResult {
  const WriteResult(this.results);

  final List<RequestResult> results;

  bool get ok => results.every((r) => r.ok);

  /// The first request that failed, with the ECU's status when it answered with one.
  RequestResult? get failed => results.where((r) => !r.ok).firstOrNull;
}

/// Table elements as the protocol numbers them.
abstract final class TableElement {
  static const columns = 0, rows = 1, values = 2;
}

class WriteGate {
  /// Over the session's calibration and channel.
  WriteGate(Session session) : this.over(() => session.calibration, () => session.connection.channel);

  /// Over any calibration and channel (tests, and a calibration not from a session).
  WriteGate.over(this._calibration, this._channel);

  final Calibration? Function() _calibration;
  final Channel Function() _channel;

  /// Cells changed since the table was last read, by table and element: sent on every save until then, as the
  /// original's dirty flags were.
  final _dirty = <int, List<Set<int>>>{};

  Calibration get _cal => _calibration() ?? (throw StateError('No calibration'));

  /// Sets a cell of a table here. An equal value (0 equals −0) changes nothing and isn't sent.
  void setTableCell(int tableId, int element, int index, double value) {
    final v = _cal.tables[tableId]!;
    final a = switch (element) {
      TableElement.columns => v.x,
      TableElement.rows => v.y,
      _ => v.z,
    };
    final old = a[index], f = (Float32List(1)..[0] = value)[0];
    if (old == f || (old.isNaN && f.isNaN)) return;
    a[index] = f;
    (_dirty[tableId] ??= [<int>{}, <int>{}, <int>{}])[element].add(index);
  }

  /// Sets every cell of a table that differs in [edited], a changed copy of its values, as [setTableCell] would.
  void setTable(int tableId, TableValues edited) {
    final v = _cal.tables[tableId]!;
    for (final (element, from, to) in [
      (TableElement.values, v.z, edited.z),
      (TableElement.rows, v.y, edited.y),
      (TableElement.columns, v.x, edited.x),
    ]) {
      for (var i = 0; i < from.length && i < to.length; i++) {
        setTableCell(tableId, element, i, to[i]);
      }
    }
  }

  /// Forgets the changed cells of every table: the calibration was read again.
  void calibrationRead() => _dirty.clear();

  /// Tables sent to the ECU since they were last stored: their changes are lost when it powers off.
  final _unstored = <int>{};

  bool isUnstored(int tableId) => _unstored.contains(tableId);

  /// The frames a table save sends: changed values, then rows (maps only), then columns, one cell per offset; then
  /// a store when asked.
  List<Frame> tableSaveFrames(int tableId, {bool store = false}) {
    final d = _cal.definition.tables[tableId]!;
    final v = _cal.tables[tableId]!;
    final dirty = _dirty[tableId];
    final out = <Frame>[];
    void add(int elem, Float32List a) {
      final idx = (dirty?[elem].toList() ?? <int>[])..sort();
      if (idx.isEmpty) return;
      out.add(
        setTableDataRequest(tableId, elem, idx, [
          for (final i in idx) [a[i]],
        ]),
      );
    }

    add(TableElement.values, v.z);
    if (d.rows > 1) add(TableElement.rows, v.y);
    add(TableElement.columns, v.x);
    if (store) out.add(storeTableRequest(tableId));
    return out;
  }

  /// Sends a table's changes, and stores it when asked.
  Future<WriteResult> saveTable(int tableId, {bool store = false}) async {
    final frames = tableSaveFrames(tableId, store: store);
    final r = await _send(frames);
    if (store && r.ok) {
      _unstored.remove(tableId);
    } else if (!store && frames.isNotEmpty) {
      _unstored.add(tableId);
    }
    return r;
  }

  /// Checks a settings change the original's way and, when it is valid, makes it here (not yet sent). A warning or
  /// a change needing approval waits for [applyApproved].
  SettingCheck setSetting(int driverId, int index, double raw) {
    final check = checkSetting(_cal, driverId, index, raw);
    if (check.verdict == SettingVerdict.valid) _cal.drivers[driverId]!.config[index] = raw;
    return check;
  }

  /// Makes a change the user approved after a [SettingVerdict.needsApproval] or warning: the duplicates go back to
  /// the group's default.
  void applyApproved(int driverId, int index, double raw, SettingCheck check) {
    final config = _cal.drivers[driverId]!.config;
    config[index] = raw;
    final def = check.defaultValue;
    if (def != null) {
      for (final i in check.duplicates) {
        config[i] = def.$2;
      }
    }
  }

  /// Replaces a driver's private data (the custom CAN configuration, for one), fitted to its size, and mirrors its
  /// checksum into the driver's ConfigCRC setting, as the original did whenever the data was set.
  void setDriverPrivate(int driverId, Uint8List data) {
    final d = _cal.definition.drivers[driverId], v = _cal.drivers[driverId];
    if (d == null || v == null || v.priv.isEmpty) return;
    final priv = Uint8List(v.priv.length)
      ..setAll(0, data.length > v.priv.length ? data.sublist(0, v.priv.length) : data);
    v.priv = priv;
    for (var i = 0; i < d.params.length && i < v.config.length; i++) {
      if (d.params[i].name == 'ConfigCRC') {
        v.config[i] = fletcher16(priv).toDouble();
        break;
      }
    }
  }

  /// The frames a driver save sends: the whole driver, then a store when asked.
  List<Frame> driverSaveFrames(int driverId, {bool store = false}) {
    final d = _cal.definition.drivers[driverId]!;
    return [
      setDriverRequest(driverId, driverBlob(d, _cal.drivers[driverId]!)),
      if (store) storeDriverRequest(driverId),
    ];
  }

  Future<WriteResult> saveDriver(int driverId, {bool store = false}) => _send(driverSaveFrames(driverId, store: store));

  /// Sending a whole calibration (K01 to K04): for every table, then every driver, set, store and read back.
  List<Frame> calibrationFrames(Calibration file) => [
    for (final id in file.definition.tables.keys)
      if (file.tables[id] case final v?) ...[
        setTableRequest(id, tableBlob(file.definition.tables[id]!, v)),
        storeTableRequest(id),
        getTableRequest(id),
      ],
    for (final id in file.definition.drivers.keys)
      if (file.drivers[id] case final v?) ...[
        setDriverRequest(id, driverBlob(file.definition.drivers[id]!, v)),
        storeDriverRequest(id),
        getDriverRequest(id),
      ],
  ];

  /// Sends a whole calibration, then takes the ECU's read-back of each item into the calibration here, as the
  /// original reloaded it after sending.
  Future<WriteResult> sendCalibration(Calibration file) async {
    final r = await _send(calibrationFrames(file));
    final cal = _cal;
    final ids = [
      ...file.definition.tables.keys.where((id) => file.tables[id] != null),
      ...file.definition.drivers.keys.where((id) => file.drivers[id] != null),
    ];
    for (final (k, id) in ids.indexed) {
      final i = k * 3 + 2;
      if (i >= r.results.length) break;
      if (r.results[i].reply case final BlobReply b when b.ok) {
        try {
          if (cal.definition.tables[id] case final t?) {
            cal.tables[id] = parseTableBlob(t, b.blob, cal.tables[id]);
            _unstored.remove(id);
            _dirty.remove(id);
          } else if (cal.definition.drivers[id] case final d?) {
            cal.drivers[id] = parseDriverBlob(d, b.blob, cal.drivers[id]);
          }
        } on BlobError {
          // keeps what was here
        }
      }
    }
    return r;
  }

  Future<WriteResult> _send(List<Frame> frames) async {
    if (frames.isEmpty) return const WriteResult([]);
    return WriteResult(await _channel().requestAll(frames));
  }
}
