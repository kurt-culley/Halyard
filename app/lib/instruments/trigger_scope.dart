import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// One channel of a trigger trace: its level at each time.
typedef ScopeLane = ({String name, List<double> levels});

/// Trigger edges as square waves, one lane per channel, over a band coloured by sync state; edges filled in for a
/// missed one are drawn dashed. The wheel zooms around the pointer, a drag pans, and a drag with Shift marks a span.
class TriggerScope extends StatefulWidget {
  const TriggerScope({
    super.key,
    required this.times,
    required this.lanes,
    required this.sync,
    required this.simulated,
    required this.start,
    required this.end,
    this.selection,
    this.syncNames = const [],
    this.onWindow,
    this.onSelect,
  });

  /// Seconds, ascending.
  final List<double> times;
  final List<ScopeLane> lanes;
  final List<int> sync;
  final List<bool> simulated;

  /// The visible window in seconds.
  final double start, end;
  final (double, double)? selection;
  final List<String> syncNames;
  final void Function(double start, double end)? onWindow;
  final void Function((double, double)? span)? onSelect;

  static const axis = 22.0, left = 64.0, syncBand = 18.0;

  @override
  State<TriggerScope> createState() => _TriggerScopeState();
}

class _TriggerScopeState extends State<TriggerScope> {
  double? _dragFrom;
  bool _selecting = false;

  @override
  Widget build(BuildContext context) {
    final TriggerScope(:start, :end, :onWindow, :onSelect) = widget;
    const left = TriggerScope.left;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth - left;
        double timeAt(double dx) => start + (end - start) * ((dx - left) / width).clamp(0.0, 1.0);
        return Listener(
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent || onWindow == null) return;
            final at = timeAt(e.localPosition.dx);
            final k = math.pow(1.15, e.scrollDelta.dy / 40).toDouble();
            onWindow(at - (at - start) * k, at + (end - at) * k);
          },
          child: GestureDetector(
            onPanStart: (d) {
              _selecting = HardwareKeyboard.instance.isShiftPressed;
              final from = _dragFrom = timeAt(d.localPosition.dx);
              if (_selecting) onSelect?.call((from, from));
            },
            onPanUpdate: (d) {
              final from = _dragFrom;
              if (from == null) return;
              if (_selecting) {
                final to = timeAt(d.localPosition.dx);
                onSelect?.call(from < to ? (from, to) : (to, from));
              } else {
                final dt = -d.delta.dx / width * (end - start);
                onWindow?.call(start + dt, end + dt);
              }
            },
            onPanEnd: (_) => _dragFrom = null,
            onTapUp: (_) => onSelect?.call(null),
            child: CustomPaint(
              size: Size.infinite,
              painter: _ScopePainter(
                widget,
                ink: scheme.onSurface,
                grid: theme.dividerColor,
                lane: [scheme.primary, scheme.tertiary, scheme.secondary, scheme.error, scheme.outline],
                selectionFill: scheme.primary.withValues(alpha: 0.12),
                syncColours: [
                  scheme.errorContainer,
                  scheme.tertiaryContainer,
                  scheme.secondaryContainer,
                  scheme.primaryContainer,
                  scheme.surfaceContainerHighest,
                ],
                text: theme.textTheme.labelSmall!.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScopePainter extends CustomPainter {
  _ScopePainter(
    this.s, {
    required this.ink,
    required this.grid,
    required this.lane,
    required this.selectionFill,
    required this.syncColours,
    required this.text,
  });

  final TriggerScope s;
  final Color ink, grid, selectionFill;
  final List<Color> lane, syncColours;
  final TextStyle text;

  void _label(Canvas c, String t, Offset at, {TextStyle? style}) => (TextPainter(
    text: TextSpan(text: t, style: style ?? text),
    textDirection: TextDirection.ltr,
  )..layout()).paint(c, at);

  int _first(double t) {
    var lo = 0, hi = s.times.length;
    while (lo < hi) {
      final m = (lo + hi) >> 1;
      if (s.times[m] < t) {
        lo = m + 1;
      } else {
        hi = m;
      }
    }
    return lo;
  }

  static String _ms(double seconds) {
    final ms = seconds * 1000;
    return ms.abs() >= 100 ? '${ms.toStringAsFixed(0)} ms' : '${ms.toStringAsFixed(ms.abs() >= 10 ? 1 : 2)} ms';
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = TriggerScope.left, axis = TriggerScope.axis, band = TriggerScope.syncBand;
    final w = size.width - left;
    final span = s.end > s.start ? s.end - s.start : 1e-3;
    double x(double t) => left + w * (t - s.start) / span;
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;

    // Time grid at a round step.
    final raw = span / 8;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final step = [1, 2, 5, 10].map((k) => k * mag).firstWhere((v) => v >= raw, orElse: () => 10 * mag);
    for (var t = (s.start / step).ceil() * step; t <= s.end; t += step) {
      canvas.drawLine(Offset(x(t), 0), Offset(x(t), size.height - axis), g);
      _label(canvas, _ms(t), Offset(x(t) + 3, size.height - axis + 4));
    }

    final i0 = math.max(0, _first(s.start) - 1), i1 = math.min(s.times.length, _first(s.end) + 1);

    // Sync state band along the top.
    for (var i = i0; i < i1; i++) {
      final a = x(s.times[i]), b = i + 1 < s.times.length ? x(s.times[i + 1]) : size.width;
      final st = s.sync[i].clamp(0, syncColours.length - 1);
      canvas.drawRect(
        Rect.fromLTRB(math.max(left, a), 0, math.min(size.width, b), band),
        Paint()..color = syncColours[st],
      );
    }
    _label(canvas, 'Sync', const Offset(4, 3));
    if (i1 > i0 && s.syncNames.isNotEmpty) {
      final st = s.sync[i1 - 1];
      if (st >= 0 && st < s.syncNames.length) {
        _label(canvas, s.syncNames[st], Offset(left + 4, 3), style: text.copyWith(color: ink));
      }
    }

    final h = (size.height - axis - band - 8) / math.max(1, s.lanes.length);
    for (final (k, l) in s.lanes.indexed) {
      final top = band + 8 + k * h;
      final hi = top + h * 0.2, lo = top + h * 0.8;
      canvas.drawLine(Offset(left, top + h), Offset(size.width, top + h), g);
      _label(canvas, l.name, Offset(4, top + h / 2 - 7), style: text.copyWith(color: ink));
      final colour = lane[k % lane.length];
      final solid = Paint()
        ..color = colour
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      final dashed = Paint()
        ..color = colour.withValues(alpha: 0.45)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      final path = Path();
      double? lastY;
      for (var i = i0; i < i1; i++) {
        final px = x(s.times[i]).clamp(left, size.width);
        final y = l.levels[i] > 0.5 ? hi : lo;
        if (lastY == null) {
          path.moveTo(px, y);
        } else {
          path.lineTo(px, lastY);
          if (y != lastY) {
            if (s.simulated[i]) {
              canvas.drawLine(Offset(px, lastY), Offset(px, y), dashed);
              path.moveTo(px, y);
            } else {
              path.lineTo(px, y);
            }
          }
        }
        lastY = y;
      }
      if (lastY != null) path.lineTo(size.width, lastY);
      canvas.drawPath(path, solid);
    }

    final sel = s.selection;
    if (sel != null && sel.$2 > sel.$1) {
      final a = x(sel.$1).clamp(left, size.width), b = x(sel.$2).clamp(left, size.width);
      canvas
        ..drawRect(Rect.fromLTRB(a, 0, b, size.height - axis), Paint()..color = selectionFill)
        ..drawLine(Offset(a, 0), Offset(a, size.height - axis), Paint()..color = ink)
        ..drawLine(Offset(b, 0), Offset(b, size.height - axis), Paint()..color = ink);
      _label(canvas, _ms(sel.$2 - sel.$1), Offset(a + 4, band + 2), style: text.copyWith(color: ink));
    }
  }

  @override
  bool shouldRepaint(_ScopePainter old) => true;
}
