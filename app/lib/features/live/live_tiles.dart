import 'dart:async';
import 'dart:math' as math;

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../instruments/readout.dart';
import '../../instruments/trace.dart';
import '../../workspace/page_layout.dart';
import '../../workspace/tile_source.dart';
import 'live_dial.dart';
import 'strings.dart';

/// How a live tile shows its link.
enum LiveStyle { readout, trace, gauge }

/// Live tiles for the workspace, one link each: a readout, a trace of its recent history, or a dial.
final class LiveTiles implements TileSource {
  LiveTiles(this._session, {this.style = LiveStyle.readout}) {
    _session.states.listen((_) => _changes.value++);
  }

  final Session _session;
  final LiveStyle style;
  final _changes = ValueNotifier(0);

  /// Saved pages name tiles by these.
  @override
  String get kind => style.name;

  String _name(LinkDef l) {
    final n = l.name ?? LiveStrings.link(l.id);
    return switch (style) {
      LiveStyle.readout => n,
      LiveStyle.trace => LiveStrings.trend(n),
      LiveStyle.gauge => LiveStrings.gauge(n),
    };
  }

  @override
  Listenable get changes => _changes;

  @override
  List<TileChoice> get choices {
    final cal = _session.calibration;
    if (cal == null) return const [];
    return [for (final l in cal.definition.links.values) (content: TileContent(kind, l.id), label: _name(l))];
  }

  @override
  String? labelOf(TileContent content) {
    final id = content.item;
    final link = id == null ? null : _session.calibration?.definition.links[id];
    return link == null ? null : _name(link);
  }

  @override
  Widget build(BuildContext context, TileContent content) => switch (style) {
    LiveStyle.readout => _LiveReadout(session: _session, id: content.item!),
    LiveStyle.trace => _LiveTrace(session: _session, id: content.item!),
    LiveStyle.gauge => Padding(
      padding: const EdgeInsets.all(8),
      child: Center(
        child: LiveDial(session: _session, id: content.item!),
      ),
    ),
  };
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
    // As large as the tile allows, up to three times the readout's own size.
    return LayoutBuilder(
      builder: (context, box) => Center(
        child: SizedBox(
          width: math.min(box.maxWidth, 3 * 220),
          height: math.min(box.maxHeight, 3 * 90),
          child: FittedBox(fit: BoxFit.contain, child: _readout(link, parts)),
        ),
      ),
    );
  }

  Widget _readout(LinkDef? link, List<String> parts) => SizedBox(
    width: 220,
    child: Readout(
      label: link?.name ?? LiveStrings.link(widget.id),
      unit: link?.measureUnit,
      value: parts.first,
      stale: parts.length > 1 && parts[1] == 'true',
      alarm: parts.length > 2 && parts[2] == 'true',
    ),
  );
}

class _LiveTrace extends StatefulWidget {
  const _LiveTrace({required this.session, required this.id});
  final Session session;
  final int id;

  @override
  State<_LiveTrace> createState() => _LiveTraceState();
}

class _LiveTraceState extends State<_LiveTrace> {
  late final Timer _timer;
  int _version = -1;

  /// About a minute at the usual report rate.
  static const samples = 600;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final v = widget.session.live?.version ?? -1;
      if (v != _version && mounted) setState(() => _version = v);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.session.live;
    final link = widget.session.calibration?.definition.links[widget.id];
    final n = live?.length(widget.id) ?? 0;
    final from = math.max(0, n - samples);
    return Trace(
      label: link?.name ?? LiveStrings.link(widget.id),
      unit: link?.measureUnit,
      latest: link == null || live == null ? '' : linkValueText(link, live.value(widget.id), 2) ?? '',
      values: [for (var k = from; k < n; k++) live!.sample(widget.id, k).$2],
    );
  }
}
