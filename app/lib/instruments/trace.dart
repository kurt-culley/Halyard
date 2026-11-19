import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// A live trace: the recent values of one channel as a line, scaled to their own range (or [min] to [max] when
/// given), with the label and the latest value above it.
class Trace extends StatelessWidget {
  const Trace({
    super.key,
    required this.label,
    required this.values,
    required this.latest,
    this.unit,
    this.min,
    this.max,
  });

  final String label;
  final String latest;
  final String? unit;

  /// Oldest first; NaN values leave a gap.
  final List<double> values;
  final double? min, max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis),
              ),
              Text('$latest${unit == null || unit!.isEmpty ? '' : ' $unit'}', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: CustomPaint(
              painter: _TracePainter(
                values,
                min,
                max,
                theme.colorScheme.primary,
                theme.dividerColor,
                theme.textTheme.labelSmall!,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter(this.values, this.min, this.max, this.line, this.grid, this.text);
  final List<double> values;
  final double? min, max;
  final Color line, grid;
  final TextStyle text;

  @override
  void paint(Canvas canvas, Size size) {
    final finite = values.where((v) => v.isFinite);
    var lo = min ?? (finite.isEmpty ? 0 : finite.reduce(math.min));
    var hi = max ?? (finite.isEmpty ? 1 : finite.reduce(math.max));
    if (hi - lo < 1e-9) {
      lo -= 0.5;
      hi += 0.5;
    }
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var k = 0; k <= 4; k++) {
      final y = size.height * k / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), g);
    }
    void label(double v, double y) {
      final tp = TextPainter(
        text: TextSpan(text: _short(v), style: text),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y));
    }

    label(hi, 0);
    label(lo, size.height - 14);
    if (values.length < 2) return;
    final path = Path();
    var pen = false;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (!v.isFinite) {
        pen = false;
        continue;
      }
      final x = size.width * i / (values.length - 1);
      final y = size.height * (1 - ((v - lo) / (hi - lo)).clamp(0, 1));
      if (pen) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
        pen = true;
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  static String _short(double v) =>
      v.abs() >= 1000 || v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  bool shouldRepaint(_TracePainter old) => true;
}
