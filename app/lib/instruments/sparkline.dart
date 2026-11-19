import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Recent values as a small line, scaled to their own range, with the latest marked.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.colour});

  /// Oldest first; NaN leaves a gap.
  final List<double> values;
  final Color? colour;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.infinite, painter: _SparkPainter(values, colour ?? Theme.of(context).colorScheme.primary));
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.colour);
  final List<double> values;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final finite = values.where((v) => v.isFinite);
    if (values.length < 2 || finite.isEmpty) return;
    var lo = finite.reduce(math.min), hi = finite.reduce(math.max);
    if (hi - lo < 1e-9) {
      lo -= 0.5;
      hi += 0.5;
    }
    Offset at(int i) =>
        Offset(size.width * i / (values.length - 1), 2 + (size.height - 4) * (1 - (values[i] - lo) / (hi - lo)));
    final line = Path(), fill = Path();
    var pen = false;
    Offset? last;
    for (var i = 0; i < values.length; i++) {
      if (!values[i].isFinite) {
        pen = false;
        continue;
      }
      final p = at(i);
      if (pen) {
        line.lineTo(p.dx, p.dy);
        fill.lineTo(p.dx, p.dy);
      } else {
        line.moveTo(p.dx, p.dy);
        fill
          ..moveTo(p.dx, size.height)
          ..lineTo(p.dx, p.dy);
      }
      pen = true;
      last = p;
    }
    if (last != null) {
      fill
        ..lineTo(last.dx, size.height)
        ..close();
    }
    canvas
      ..drawPath(fill, Paint()..color = colour.withValues(alpha: 0.12))
      ..drawPath(
        line,
        Paint()
          ..color = colour
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
    if (last != null) canvas.drawCircle(last, 2.5, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => true;
}
