import 'dart:async';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../instruments/readout.dart';
import '../../workspace/page_layout.dart';
import '../../workspace/tile_source.dart';
import 'strings.dart';

/// Readout tiles for the workspace: one live link each.
final class LiveTiles implements TileSource {
  LiveTiles(this._session) {
    _session.states.listen((_) => _changes.value++);
  }

  final Session _session;
  final _changes = ValueNotifier(0);

  @override
  String get kind => 'readout';

  @override
  Listenable get changes => _changes;

  @override
  List<TileChoice> get choices {
    final cal = _session.calibration;
    if (cal == null) return const [];
    return [
      for (final l in cal.definition.links.values)
        (content: TileContent(kind, l.id), label: l.name ?? LiveStrings.link(l.id)),
    ];
  }

  @override
  String? labelOf(TileContent content) {
    final id = content.item;
    final link = id == null ? null : _session.calibration?.definition.links[id];
    return link == null ? null : link.name ?? LiveStrings.link(link.id);
  }

  @override
  Widget build(BuildContext context, TileContent content) => _LiveReadout(session: _session, id: content.item!);
}

class _LiveReadout extends StatefulWidget {
  const _LiveReadout({required this.session, required this.id});
  final Session session;
  final int id;

  @override
  State<_LiveReadout> createState() => _LiveReadoutState();
}

class _LiveReadoutState extends State<_LiveReadout> {
  late final Timer _timer;
  String _text = '';

  @override
  void initState() {
    super.initState();
    _text = _read();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final t = _read();
      if (t != _text && mounted) setState(() => _text = t);
    });
  }

  String _read() {
    final live = widget.session.live;
    final link = widget.session.calibration?.definition.links[widget.id];
    if (live == null || link == null) return '';
    return [
      linkValueText(link, live.value(widget.id), 2) ?? '',
      live.isStale(widget.id),
      isOutOfBounds(link, live.value(widget.id)),
    ].join('|');
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.session.calibration?.definition.links[widget.id];
    final parts = _text.split('|');
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Readout(
        label: link?.name ?? LiveStrings.link(widget.id),
        unit: link?.measureUnit,
        value: parts.first,
        stale: parts.length > 1 && parts[1] == 'true',
        alarm: parts.length > 2 && parts[2] == 'true',
      ),
    );
  }
}
