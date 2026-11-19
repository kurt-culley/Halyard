import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'strings.dart';

typedef LiveRow = ({
  int id,
  String label,
  String? unit,
  String value,
  bool stale,
  bool alarm,
  List<double> history,
  double fraction,
  bool pinned,
});

/// Every live link as a row with its recent history, and the links pinned as dials (kept by name, so they carry
/// over between definitions), refreshed at most ten times a second when a report has arrived.
class LiveController extends ChangeNotifier {
  LiveController(this._session, this._storage) {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    _load();
  }

  final Session _session;
  final AppStorage _storage;
  late final Timer _timer;
  int _version = -1;
  LiveStore? _store;
  String filter = '';

  /// Pinned link names; null until read, then the first few links when nothing was saved.
  List<String>? _pins;

  static const _file = 'live.json';

  /// About 30 seconds at the usual report rate.
  static const historyLength = 300;

  bool get isOnline => _session.state.phase == SessionPhase.online && _session.live != null;

  Future<void> _load() async {
    try {
      final raw = await _storage.read(_file);
      if (raw != null) {
        final pins = (jsonDecode(utf8.decode(raw)) as Map<String, dynamic>)['pins'] as List<dynamic>?;
        _pins = pins?.cast<String>().toList();
      }
    } on Object {
      _pins = null;
    }
    notifyListeners();
  }

  void _save() => _storage.write(_file, Uint8List.fromList(utf8.encode(jsonEncode({'pins': _pins})))).ignore();

  String _name(LinkDef l) => l.name ?? LiveStrings.link(l.id);

  /// The pinned links in pin order; by default the first four the definition gives a range for.
  List<int> get dials {
    final cal = _session.calibration;
    final live = _session.live;
    if (cal == null || live == null) return const [];
    final links = [for (final id in live.ids) ?cal.definition.links[id]];
    final pins = _pins;
    if (pins == null) return [for (final l in links.where((l) => l.maxValue > l.minValue).take(4)) l.id];
    return [
      for (final p in pins)
        if (links.where((l) => _name(l) == p).firstOrNull case final l?) l.id,
    ];
  }

  void togglePin(int id) {
    final link = _session.calibration?.definition.links[id];
    if (link == null) return;
    final pins = _pins ??= [
      for (final d in dials)
        if (_session.calibration!.definition.links[d] case final l?) _name(l),
    ];
    final n = _name(link);
    if (!pins.remove(n)) pins.add(n);
    _save();
    notifyListeners();
  }

  void setFilter(String v) {
    filter = v;
    notifyListeners();
  }

  List<LiveRow> get rows {
    final live = _session.live;
    final cal = _session.calibration;
    if (live == null || cal == null) return const [];
    final pinned = dials.toSet();
    final f = filter.toLowerCase();
    return [
      for (final id in live.ids)
        if (cal.definition.links[id] case final link? when f.isEmpty || _name(link).toLowerCase().contains(f))
          _row(live, link, pinned.contains(id)),
    ];
  }

  LiveRow _row(LiveStore live, LinkDef link, bool pinned) {
    final id = link.id;
    final v = live.value(id);
    final n = live.length(id);
    final span = link.maxValue - link.minValue;
    return (
      id: id,
      label: _name(link),
      unit: link.measureUnit,
      value: linkValueText(link, v, 2) ?? '',
      stale: live.isStale(id),
      alarm: isOutOfBounds(link, v),
      history: [for (var k = math.max(0, n - historyLength); k < n; k++) live.sample(id, k).$2],
      fraction: span > 0 ? (v - link.minValue) / span : double.nan,
      pinned: pinned,
    );
  }

  void _tick() {
    final live = _session.live;
    if (!identical(live, _store) || (live != null && live.version != _version)) {
      _store = live;
      _version = live?.version ?? -1;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}
