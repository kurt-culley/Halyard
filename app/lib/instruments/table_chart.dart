import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'heat.dart';

/// A table drawn as lines against its column axis: one line for a curve, one per row for a map (coloured from the
/// first row to the last), with the chosen line drawn heavier and the live place marked.
class TableChart extends StatelessWidget {
  const TableChart({super.key, required this.x, required this.lines, this.chosen, this.live, this.xLabel, this.yLabel});

  final List<double> x;

  /// Each line's values, one per column.
  final List<List<double>> lines;

  /// The line to draw heavier.
  final int? chosen;

  /// The live place: fractional column, and the fractional line for a map.
  final (double, double)? live;

  final String? xLabel, yLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      size: Size.infinite,
      painter: _ChartPainter(
        x,
        lines,
        chosen,
        live,
        xLabel,
        yLabel,
        theme.colorScheme.onSurface,
        theme.dividerColor,
        theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.x, this.lines, this.chosen, this.live, this.xLabel, this.yLabel, this.ink, this.grid, this.text);

  final List<double> x;
  final List<List<double>> lines;
  final int? chosen;
  final (double, double)? live;
  final String? xLabel, yLabel;
  final Color ink, grid;
  final TextStyle text;

  static const left = 48.0, bottom = 22.0, top = 8.0, right = 12.0;

  TextPainter _label(String s) => TextPainter(
    text: TextSpan(text: s, style: text),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (x.length < 2 || lines.isEmpty) return;
    final values = [for (final l in lines) ...l.where((v) => v.isFinite)];
    if (values.isEmpty) return;
    var lo = values.reduce(math.min), hi = values.reduce(math.max);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.05;
    lo -= pad;
    hi += pad;
    final x0 = x.reduce(math.min), x1 = x.reduce(math.max);
    final xs = x1 > x0 ? x1 - x0 : 1.0;
    final w = size.width - left - right, h = size.height - top - bottom;
    Offset at(double xv, double yv) => Offset(left + w * (xv - x0) / xs, top + h * (1 - (yv - lo) / (hi - lo)));

    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var k = 0; k <= 4; k++) {
      final v = lo + (hi - lo) * k / 4;
      final p = at(x0, v);
      canvas.drawLine(Offset(left, p.dy), Offset(size.width - right, p.dy), g);
      final t = _label(_short(v));
      t.paint(canvas, Offset(left - t.width - 6, p.dy - t.height / 2));
    }
    final step = math.max(1, (x.length / math.max(1, w / 60)).ceil());
    for (var i = 0; i < x.length; i += step) {
      final p = at(x[i], lo);
      canvas.drawLine(Offset(p.dx, top), Offset(p.dx, top + h), g);
      final t = _label(_short(x[i]));
      t.paint(canvas, Offset(p.dx - t.width / 2, top + h + 4));
    }
    if (xLabel != null) {
      final t = _label(xLabel!);
      t.paint(canvas, Offset(size.width - right - t.width, top + h - t.height - 2));
    }
    if (yLabel != null) _label(yLabel!).paint(canvas, Offset(left + 4, top));

    for (var r = 0; r < lines.length; r++) {
      if (r == chosen) continue;
      _line(
        canvas,
        at,
        lines[r],
        lines.length == 1 ? ink : heatColor(lines.length == 1 ? 0.5 : r / (lines.length - 1)),
        1.2,
      );
    }
    final c = chosen;
    if (c != null && c >= 0 && c < lines.length) _line(canvas, at, lines[c], ink, 3);

    final l = live;
    if (l != null) {
      final i = l.$1.floor().clamp(0, x.length - 2), f = l.$1 - i;
      final xv = x[i] + (x[i + 1] - x[i]) * f;
      final row = lines.length == 1 ? 0 : l.$2.round().clamp(0, lines.length - 1);
      final line = lines[row];
      final yv = line[i] + (line[i + 1] - line[i]) * f;
      final p = at(xv, yv);
      if (p.dy.isFinite) {
        canvas
          ..drawLine(Offset(p.dx, top), Offset(p.dx, top + h), Paint()..color = ink.withValues(alpha: 0.4))
          ..drawCircle(p, 6, Paint()..color = ink)
          ..drawCircle(p, 3, Paint()..color = heatColor(0.75));
      }
    }
  }

  void _line(Canvas canvas, Offset Function(double, double) at, List<double> ys, Color colour, double width) {
    final path = Path();
    var pen = false;
    for (var i = 0; i < x.length && i < ys.length; i++) {
      if (!ys[i].isFinite) {
        pen = false;
        continue;
      }
      final p = at(x[i], ys[i]);
      pen ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
      pen = true;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = colour
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  static String _short(double v) =>
      v.abs() >= 100 || v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(v.abs() >= 10 ? 1 : 2);

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}
