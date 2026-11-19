import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// One channel of a log plot, already reduced to about one point per pixel by its caller.
typedef LogLane = ({String label, List<double> times, List<double> values});

/// A logged session as stacked lanes on one time axis, each scaled to its own range, with markers as lines.
class LogPlot extends StatelessWidget {
  const LogPlot({super.key, required this.start, required this.end, required this.lanes, this.markers = const []});

  final double start, end;
  final List<LogLane> lanes;
  final List<double> markers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      size: Size.infinite,
      painter: _LogPainter(
        start,
        end,
        lanes,
        markers,
        theme.colorScheme.primary,
        theme.colorScheme.tertiary,
        theme.dividerColor,
        theme.textTheme.labelSmall!,
      ),
    );
  }
}

class _LogPainter extends CustomPainter {
  _LogPainter(this.start, this.end, this.lanes, this.markers, this.line, this.mark, this.grid, this.text);
  final double start, end;
  final List<LogLane> lanes;
  final List<double> markers;
  final Color line, mark, grid;
  final TextStyle text;

  static const axis = 18.0;

  void _text(Canvas c, String s, Offset at) => (TextPainter(
    text: TextSpan(text: s, style: text),
    textDirection: TextDirection.ltr,
  )..layout()).paint(c, at);

  @override
  void paint(Canvas canvas, Size size) {
    if (lanes.isEmpty) return;
    final span = end > start ? end - start : 1.0;
    final h = (size.height - axis) / lanes.length;
    double x(double t) => size.width * (t - start) / span;
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final (i, lane) in lanes.indexed) {
      final top = i * h;
      canvas.drawLine(Offset(0, top + h), Offset(size.width, top + h), g);
      final finite = lane.values.where((v) => v.isFinite);
      var lo = finite.isEmpty ? 0.0 : finite.reduce(math.min);
      var hi = finite.isEmpty ? 1.0 : finite.reduce(math.max);
      if (hi - lo < 1e-9) {
        lo -= 0.5;
        hi += 0.5;
      }
      final path = Path();
      var pen = false;
      for (var k = 0; k < lane.times.length; k++) {
        final v = lane.values[k];
        if (!v.isFinite) {
          pen = false;
          continue;
        }
        final p = Offset(x(lane.times[k]), top + 4 + (h - 8) * (1 - (v - lo) / (hi - lo)));
        pen ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
        pen = true;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
      _text(canvas, '${lane.label}   ${_short(lo)} – ${_short(hi)}', Offset(4, top + 2));
    }
    final m = Paint()
      ..color = mark
      ..strokeWidth = 1;
    for (final t in markers) {
      canvas.drawLine(Offset(x(t), 0), Offset(x(t), size.height - axis), m);
    }
    for (var k = 0; k <= 5; k++) {
      final t = start + span * k / 5;
      _text(canvas, '${t.toStringAsFixed(1)} s', Offset(math.min(x(t), size.width - 40), size.height - axis + 2));
    }
  }

  static String _short(double v) =>
      v.abs() >= 100 || v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  bool shouldRepaint(_LogPainter old) => true;
}
