import 'dart:async';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'strings.dart';

typedef LiveRow = ({String label, String? unit, String value, bool stale, bool alarm});

/// Every live link as a row, refreshed at most ten times a second when a report has arrived.
class LiveController extends ChangeNotifier {
  LiveController(this._session) {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  final Session _session;
  late final Timer _timer;
  int _version = -1;
  LiveStore? _store;

  bool get isOnline => _session.state.phase == SessionPhase.online && _session.live != null;

  List<LiveRow> get rows {
    final live = _session.live;
    final cal = _session.calibration;
    if (live == null || cal == null) return const [];
    return [
      for (final id in live.ids)
        if (cal.definition.links[id] case final link?)
          (
            label: link.name ?? LiveStrings.link(id),
            unit: link.measureUnit,
            value: linkValueText(link, live.value(id), 2) ?? '',
            stale: live.isStale(id),
            alarm: isOutOfBounds(link, live.value(id)),
          ),
    ];
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
