import 'dart:async';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../instruments/dial_gauge.dart';
import 'strings.dart';

/// One link on a dial over the link's own range. As the original's gauge did, the needle moves only for readings
/// inside the range and the text shows the needle's value.
class LiveDial extends StatefulWidget {
  const LiveDial({super.key, required this.session, required this.id});
  final Session session;
  final int id;

  @override
  State<LiveDial> createState() => _LiveDialState();
}

class _LiveDialState extends State<LiveDial> {
  late final Timer _timer;
  double? _needle;
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final before = (_needle, _stale);
      _read();
      if (before != (_needle, _stale) && mounted) setState(() {});
    });
  }

  void _read() {
    final live = widget.session.live;
    final link = widget.session.calibration?.definition.links[widget.id];
    if (live == null || link == null) return;
    final v = live.value(widget.id);
    if (v >= link.minValue && v <= link.maxValue) _needle = v;
    _stale = live.isStale(widget.id);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.session.calibration?.definition.links[widget.id];
    final n = _needle;
    return DialGauge(
      label: link?.name ?? LiveStrings.link(widget.id),
      unit: link?.measureUnit,
      value: n,
      min: link?.minValue ?? 0,
      max: link?.maxValue ?? 1,
      text: n == null || link == null ? null : linkValueText(link, n, 2),
      stale: _stale,
    );
  }
}
