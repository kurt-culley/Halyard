import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'heat.dart';

/// A map as a shaded surface: cells evenly spaced across and down, height by value. Drag rotates, the wheel zooms,
/// a click picks the nearest point. Selected points and the live position are marked.
class Surface3D extends StatefulWidget {
  const Surface3D({
    super.key,
    required this.rows,
    required this.cols,
    required this.values,
    this.selected = const {},
    this.live,
    this.xLabel,
    this.yLabel,
    this.xTicks = const [],
    this.yTicks = const [],
    this.onPick,
  });

  final int rows, cols;

  /// Row-major.
  final List<double> values;

  /// Value cells, (row, column) from 0.
  final Set<(int, int)> selected;

  /// Fractional (row, column).
  final (double, double)? live;
  final String? xLabel, yLabel;
  final List<String> xTicks, yTicks;
  final void Function(int row, int col)? onPick;

  @override
  State<Surface3D> createState() => _Surface3DState();
}

class _Surface3DState extends State<Surface3D> {
  double _yaw = -0.45, _pitch = 0.55, _zoom = 1;
  Offset? _down;
  bool _moved = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final view = _View(widget, _yaw, _pitch, _zoom, Size(box.maxWidth, box.maxHeight));
        return Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              setState(() => _zoom = (_zoom * math.pow(0.9, e.scrollDelta.dy / 40)).clamp(0.4, 4.0));
            }
          },
          onPointerDown: (e) {
            _down = e.localPosition;
            _moved = false;
          },
          onPointerMove: (e) {
            if (_down == null) return;
            if ((e.localPosition - _down!).distance > 3) _moved = true;
            setState(() {
              _yaw += e.delta.dx * 0.01;
              _pitch = (_pitch + e.delta.dy * 0.01).clamp(0.1, math.pi / 2);
            });
          },
          onPointerUp: (e) {
            if (!_moved && widget.onPick != null) {
              final hit = view.nearest(e.localPosition);
              if (hit != null) widget.onPick!(hit.$1, hit.$2);
            }
            _down = null;
          },
          child: ClipRect(
            child: CustomPaint(
              size: Size.infinite,
              painter: _SurfacePainter(
                view,
                ink: scheme.onSurface,
                mark: scheme.primary,
                text: theme.textTheme.labelSmall!.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The projection of one frame: model points to the screen.
class _View {
  _View(this.w, double yaw, double pitch, this.zoom, this.size)
    : _cy = math.cos(yaw),
      _sy = math.sin(yaw),
      _cp = math.cos(pitch),
      _sp = math.sin(pitch) {
    final finite = w.values.where((v) => v.isFinite);
    lo = finite.isEmpty ? 0 : finite.reduce(math.min);
    hi = finite.isEmpty ? 1 : finite.reduce(math.max);
    if (hi - lo < 1e-9) hi = lo + 1;
  }

  final Surface3D w;
  final double zoom;
  final Size size;
  final double _cy, _sy, _cp, _sp;
  late final double lo, hi;

  double shade(double v) => (v - lo) / (hi - lo);

  /// Model space: x and y from −1 to 1 across the table, z from 0 to 0.9 by value.
  (double, double, double) model(double r, double c, double v) => (
    w.cols > 1 ? c / (w.cols - 1) * 2 - 1 : 0,
    w.rows > 1 ? 1 - r / (w.rows - 1) * 2 : 0,
    v.isFinite ? shade(v) * 0.9 : 0,
  );

  /// Screen position and depth (larger is nearer).
  (Offset, double) project((double, double, double) p) {
    final (x, y, z) = p;
    final rx = x * _cy - y * _sy, ry = x * _sy + y * _cy;
    final depth = ry * _cp + z * _sp;
    final up = z * _cp - ry * _sp;
    final scale = math.min(size.width * 0.8, size.height) * 0.4 * zoom;
    final persp = 6 / (6 - depth);
    return (Offset(size.width / 2 + rx * scale * persp, size.height * 0.55 - up * scale * persp), depth);
  }

  Offset at(int r, int c) => project(model(r.toDouble(), c.toDouble(), w.values[r * w.cols + c])).$1;

  (int, int)? nearest(Offset p) {
    (int, int)? best;
    var d = 24.0;
    for (var r = 0; r < w.rows; r++) {
      for (var c = 0; c < w.cols; c++) {
        final e = (at(r, c) - p).distance;
        if (e < d) {
          d = e;
          best = (r, c);
        }
      }
    }
    return best;
  }
}

class _SurfacePainter extends CustomPainter {
  _SurfacePainter(this.v, {required this.ink, required this.mark, required this.text});
  final _View v;
  final Color ink, mark;
  final TextStyle text;

  void _label(Canvas c, String s, Offset at) {
    final t = TextPainter(
      text: TextSpan(text: s, style: text),
      textDirection: TextDirection.ltr,
    )..layout();
    t.paint(c, at - Offset(t.width / 2, t.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = v.w;
    if (w.rows < 2 || w.cols < 2) return;

    // The floor, so the surface has something to stand on.
    final floor = Path();
    for (final (i, (r, c)) in [(0, 0), (0, w.cols - 1), (w.rows - 1, w.cols - 1), (w.rows - 1, 0)].indexed) {
      final p = v.project(v.model(r.toDouble(), c.toDouble(), double.nan)).$1;
      i == 0 ? floor.moveTo(p.dx, p.dy) : floor.lineTo(p.dx, p.dy);
    }
    floor.close();
    canvas
      ..drawPath(floor, Paint()..color = ink.withValues(alpha: 0.05))
      ..drawPath(
        floor,
        Paint()
          ..color = ink.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke,
      );

    // Quads far to near.
    final quads = <(double, Path, double)>[];
    for (var r = 0; r < w.rows - 1; r++) {
      for (var c = 0; c < w.cols - 1; c++) {
        final corners = [(r, c), (r, c + 1), (r + 1, c + 1), (r + 1, c)];
        final pts = [
          for (final (a, b) in corners) v.project(v.model(a.toDouble(), b.toDouble(), w.values[a * w.cols + b])),
        ];
        final depth = pts.fold(0.0, (s, p) => s + p.$2) / 4;
        final avg = corners.fold(0.0, (s, k) => s + w.values[k.$1 * w.cols + k.$2]) / 4;
        final path = Path()..moveTo(pts[0].$1.dx, pts[0].$1.dy);
        for (final p in pts.skip(1)) {
          path.lineTo(p.$1.dx, p.$1.dy);
        }
        path.close();
        quads.add((depth, path, v.shade(avg)));
      }
    }
    quads.sort((a, b) => a.$1.compareTo(b.$1));
    final edge = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (final (_, path, t) in quads) {
      canvas
        ..drawPath(path, Paint()..color = heatColor(t))
        ..drawPath(path, edge);
    }

    // Axis ticks along the floor's two front edges.
    int every(int n) => math.max(1, (n / 6).ceil());
    for (var c = 0; c < w.cols; c += every(w.cols)) {
      if (c < w.xTicks.length) {
        _label(canvas, w.xTicks[c], v.project(v.model(-0.9, c.toDouble(), double.nan)).$1);
      }
    }
    for (var r = 0; r < w.rows; r += every(w.rows)) {
      if (r < w.yTicks.length) _label(canvas, w.yTicks[r], v.project(v.model(r.toDouble(), -1.2, double.nan)).$1);
    }
    if (w.xLabel != null) {
      _label(canvas, w.xLabel!, v.project(v.model(-2.2, (w.cols - 1) / 2, double.nan)).$1);
    }
    if (w.yLabel != null) _label(canvas, w.yLabel!, v.project(v.model((w.rows - 1) / 2, -3.4, double.nan)).$1);

    for (final (r, c) in w.selected) {
      if (r < 0 || c < 0 || r >= w.rows || c >= w.cols) continue;
      final p = v.at(r, c);
      canvas
        ..drawCircle(p, 5, Paint()..color = mark)
        ..drawCircle(
          p,
          5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
    }

    final l = w.live;
    if (l != null) {
      final r0 = l.$1.floor().clamp(0, w.rows - 2), c0 = l.$2.floor().clamp(0, w.cols - 2);
      final fr = (l.$1 - r0).clamp(0.0, 1.0), fc = (l.$2 - c0).clamp(0.0, 1.0);
      double z(int r, int c) => w.values[r * w.cols + c];
      final top = z(r0, c0) * (1 - fc) + z(r0, c0 + 1) * fc;
      final bottom = z(r0 + 1, c0) * (1 - fc) + z(r0 + 1, c0 + 1) * fc;
      final val = top * (1 - fr) + bottom * fr;
      final p = v.project(v.model(l.$1, l.$2, val)).$1;
      final base = v.project(v.model(l.$1, l.$2, double.nan)).$1;
      canvas
        ..drawLine(base, p, Paint()..color = ink.withValues(alpha: 0.5))
        ..drawCircle(p, 7, Paint()..color = ink)
        ..drawCircle(p, 4, Paint()..color = heatColor(v.shade(val)));
    }
  }

  @override
  bool shouldRepaint(_SurfacePainter old) => true;
}
