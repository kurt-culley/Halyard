import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// A dial gauge as the original drew it: a 270° scale from [min] to [max] in [divisions], coloured low, normal and
/// high sections from the warnings, a needle that holds its place when a reading leaves the scale, and the
/// needle's value as text.
class DialGauge extends StatelessWidget {
  const DialGauge({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.unit,
    this.divisions = 10,
    this.minWarning,
    this.maxWarning,
    this.text,
    this.stale = false,
  });

  final String label;
  final String? unit;

  /// The needle's value; null before the first reading.
  final double? value;
  final double min, max;
  final int divisions;
  final double? minWarning, maxWarning;

  /// The value as text; the needle's value to two places when null.
  final String? text;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Opacity(
      opacity: stale ? 0.5 : 1,
      child: Column(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: CustomPaint(
                painter: _DialPainter(
                  label: label,
                  unit: unit,
                  value: value,
                  min: min,
                  max: max > min ? max : min + 1,
                  divisions: divisions < 1 ? 1 : divisions,
                  minWarning: minWarning,
                  maxWarning: maxWarning,
                  text: text ?? (value == null ? '–' : value!.toStringAsFixed(2)),
                  face: scheme.surfaceContainerHighest,
                  ink: scheme.onSurface,
                  muted: scheme.onSurfaceVariant,
                  normal: scheme.primary,
                  warning: scheme.error,
                  needle: scheme.tertiary,
                  labelStyle: theme.textTheme.labelMedium!,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.labelLarge, overflow: TextOverflow.ellipsis, maxLines: 1),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.minWarning,
    required this.maxWarning,
    required this.text,
    required this.face,
    required this.ink,
    required this.muted,
    required this.normal,
    required this.warning,
    required this.needle,
    required this.labelStyle,
  });

  final String label, text;
  final String? unit;
  final double? value, minWarning, maxWarning;
  final double min, max;
  final int divisions;
  final Color face, ink, muted, normal, warning, needle;
  final TextStyle labelStyle;

  static const start = math.pi * 0.75, sweep = math.pi * 1.5;

  double _angle(double v) => start + sweep * ((v - min) / (max - min)).clamp(0.0, 1.0);

  void _text(Canvas c, String s, Offset centre, TextStyle style, {double? maxWidth}) {
    final t = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    t.paint(c, centre - Offset(t.width / 2, t.height / 2));
  }

  static String _short(double v) {
    final a = v.abs();
    if (a >= 1000) return v.toStringAsFixed(0);
    if (a >= 10 || v == v.roundToDouble()) return v.toStringAsFixed(a >= 100 || v == v.roundToDouble() ? 0 : 1);
    return v.toStringAsFixed(2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final r = s / 2 - 4;
    canvas.drawCircle(c, r, Paint()..color = face);

    final band = s * 0.05;
    final arc = Rect.fromCircle(center: c, radius: r - band);
    void section(double from, double to, Color colour) {
      if (!(to > from)) return;
      final a = _angle(from), b = _angle(to);
      canvas.drawArc(
        arc,
        a,
        b - a,
        false,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = band,
      );
    }

    final lo = minWarning != null && minWarning! > min && minWarning! < max ? minWarning! : min;
    final hi = maxWarning != null && maxWarning! > min && maxWarning! < max ? maxWarning! : max;
    section(min, lo, warning);
    section(lo, hi, normal.withValues(alpha: 0.6));
    section(hi, max, warning);

    final tick = Paint()
      ..color = ink
      ..strokeWidth = math.max(1, s / 160);
    final labelSize = math.max(8.0, s * 0.05);
    final labels = labelStyle.copyWith(fontSize: labelSize, color: muted);
    final every = divisions > 5 ? (divisions / 5).ceil() : 1;
    for (var i = 0; i <= divisions; i++) {
      final a = start + sweep * i / divisions;
      final dir = Offset(math.cos(a), math.sin(a));
      final outer = r - band * 2.2, inner = outer - (i % every == 0 ? band * 1.6 : band * 0.8);
      canvas.drawLine(c + dir * inner, c + dir * outer, tick);
      if (i % every == 0) {
        _text(canvas, _short(min + (max - min) * i / divisions), c + dir * (inner - labelSize * 1.3), labels);
      }
    }
    for (var i = 0; i < divisions * 5; i++) {
      if (i % 5 == 0) continue;
      final a = start + sweep * i / (divisions * 5);
      final dir = Offset(math.cos(a), math.sin(a));
      final outer = r - band * 2.2;
      canvas.drawLine(c + dir * (outer - band * 0.4), c + dir * outer, tick..strokeWidth = math.max(0.5, s / 320));
    }

    _text(
      canvas,
      text,
      c + Offset(0, r * 0.62),
      labelStyle.copyWith(
        fontSize: math.max(12.0, s * 0.11),
        fontWeight: FontWeight.w600,
        color: ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    if (unit != null && unit!.isNotEmpty) {
      _text(canvas, unit!, c + Offset(0, r * 0.82), labels);
    }

    final v = value;
    if (v != null && v.isFinite) {
      final a = _angle(v);
      final dir = Offset(math.cos(a), math.sin(a));
      final back = Offset(-dir.dx, -dir.dy) * (r * 0.12);
      final side = Offset(-dir.dy, dir.dx) * math.max(2, s * 0.018);
      final tip = c + dir * (r - band * 2.6);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo((c + side).dx, (c + side).dy)
        ..lineTo((c + back).dx, (c + back).dy)
        ..lineTo((c - side).dx, (c - side).dy)
        ..close();
      canvas
        ..drawShadow(path, Colors.black, 2, false)
        ..drawPath(path, Paint()..color = needle);
    }
    canvas
      ..drawCircle(c, math.max(4, s * 0.045), Paint()..color = ink)
      ..drawCircle(c, math.max(2, s * 0.02), Paint()..color = face);
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.value != value || old.text != text || old.min != min || old.max != max || old.face != face;
}
