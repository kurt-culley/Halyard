import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'heat.dart';

/// Modifier keys held at a press.
typedef GridPress = ({bool shift, bool ctrl, bool right, Offset global});

/// A map or curve as a grid in the original's coordinates: row 0 is the column axis across the top, col 0 the row
/// axis down the side (none for a curve), values from (1, 1). Values are heat-shaded; the selection, the current
/// cell, the live cell and tuned cells are marked.
class MapGrid extends StatefulWidget {
  const MapGrid({
    super.key,
    required this.columns,
    required this.rows,
    required this.cells,
    required this.shades,
    this.live,
    this.selected = const {},
    this.current,
    this.tuned = const {},
    this.marks = const {},
    this.onPress,
    this.onDrag,
    this.onRelease,
    this.onDoubleTap,
  });

  final List<String> columns;

  /// Empty for a curve.
  final List<String> rows;

  /// Row-major, one row for a curve.
  final List<String> cells;

  /// 0 to 1 per cell; NaN shades a cell as mid-range.
  final List<double> shades;

  /// The live position in value cells, fractional: (row, column) from 0.
  final (double, double)? live;

  /// Selected cells and the current cell, in grid coordinates.
  final Set<(int, int)> selected;
  final (int, int)? current;

  /// Value indexes marked tuned, and axis cells marked for interpolation.
  final Set<int> tuned;
  final Set<(int, int)> marks;

  final void Function((int, int) cell, GridPress press)? onPress;
  final void Function((int, int) cell)? onDrag;
  final VoidCallback? onRelease;
  final void Function((int, int) cell)? onDoubleTap;

  static const cellWidth = 58.0, cellHeight = 24.0;

  @override
  State<MapGrid> createState() => _MapGridState();
}

class _MapGridState extends State<MapGrid> {
  static const cellHeight = MapGrid.cellHeight;

  /// Cells widen to fill the room there is, within reason.
  double cellWidth = MapGrid.cellWidth;
  var _lastDown = DateTime(0);
  (int, int)? _lastCell;

  bool get _isCurve => widget.rows.isEmpty;

  /// The grid cell under [p], or null outside it.
  (int, int)? _cellAt(Offset p) {
    final col = (p.dx / cellWidth).floor() + (_isCurve ? 1 : 0);
    final row = (p.dy / cellHeight).floor();
    final rowCount = _isCurve ? 2 : widget.rows.length + 1;
    if (row < 0 || row >= rowCount || col < 0 || col > widget.columns.length) return null;
    return (row, col);
  }

  @override
  Widget build(BuildContext context) {
    final MapGrid(:columns, :rows, :cells, :shades, :live, :selected, :current, :tuned, :marks) = widget;
    final MapGrid(:onPress, :onDrag, :onRelease, :onDoubleTap) = widget;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final head = style.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant);
    final cols = columns.length;
    final rowCount = _isCurve ? 1 : rows.length;
    final firstCol = _isCurve ? 1 : 0;
    final height = (rowCount + 1) * cellHeight;

    Widget cell(int r, int c) {
      final isHead = r == 0 || c == 0;
      final i = (r - 1) * cols + (c - 1);
      final text = r == 0 && c == 0 ? '' : (r == 0 ? columns[c - 1] : (c == 0 ? rows[r - 1] : cells[i]));
      final fill = isHead ? scheme.surfaceContainerHigh : heatColor(shades[i]);
      final sel = selected.contains((r, c));
      return Positioned(
        left: (c - firstCol) * cellWidth,
        top: r * cellHeight,
        width: cellWidth,
        height: cellHeight,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? Color.alphaBlend(scheme.primary.withValues(alpha: isHead ? 0.35 : 0.55), fill) : fill,
            border: Border(
              right: BorderSide(color: scheme.surface.withValues(alpha: 0.5), width: 0.5),
              bottom: BorderSide(color: scheme.surface.withValues(alpha: 0.5), width: 0.5),
            ),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: isHead
                ? (marks.contains((r, c)) ? head.copyWith(color: scheme.tertiary) : head)
                : style.copyWith(
                    color: sel ? scheme.onPrimary : textOn(fill),
                    fontWeight: tuned.contains(i) ? FontWeight.w800 : null,
                    decoration: tuned.contains(i) ? TextDecoration.underline : null,
                  ),
          ),
        ),
      );
    }

    final cur = current;
    final at = live;
    return LayoutBuilder(
      builder: (context, box) {
        final n = cols + 1 - firstCol;
        cellWidth = box.maxWidth.isFinite ? (box.maxWidth / n).clamp(44.0, 80.0).floorToDouble() : MapGrid.cellWidth;
        final width = n * cellWidth;
        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Listener(
              onPointerDown: (e) {
                final c = _cellAt(e.localPosition);
                if (c == null || onPress == null) return;
                final keys = HardwareKeyboard.instance;
                final now = DateTime.now();
                final twice = c == _lastCell && now.difference(_lastDown) < const Duration(milliseconds: 400);
                _lastDown = now;
                _lastCell = c;
                if (twice && e.buttons == kPrimaryMouseButton) {
                  onDoubleTap?.call(c);
                  return;
                }
                onPress(c, (
                  shift: keys.isShiftPressed,
                  ctrl: keys.isControlPressed || keys.isMetaPressed,
                  right: e.buttons == kSecondaryMouseButton,
                  global: e.position,
                ));
              },
              onPointerMove: (e) {
                if (e.buttons != kPrimaryMouseButton) return;
                final c = _cellAt(e.localPosition);
                if (c != null) onDrag?.call(c);
              },
              onPointerUp: (_) => onRelease?.call(),
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  children: [
                    for (var r = 0; r <= rowCount; r++)
                      for (var c = firstCol; c <= cols; c++) cell(r, c),
                    if (cur != null && cur.$1 > 0 && cur.$2 > 0)
                      Positioned(
                        left: (cur.$2 - firstCol) * cellWidth,
                        top: cur.$1 * cellHeight,
                        width: cellWidth,
                        height: cellHeight,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(border: Border.all(color: scheme.primary, width: 2)),
                          ),
                        ),
                      ),
                    if (at != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _LivePainter(
                              left: (1 - firstCol) * cellWidth,
                              top: cellHeight,
                              x: at.$2,
                              y: at.$1,
                              colour: scheme.onSurface,
                              halo: scheme.surface,
                              cellWidth: cellWidth,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The live position: a ring on the cell it falls in, with crosshairs through its exact place.
class _LivePainter extends CustomPainter {
  _LivePainter({
    required this.left,
    required this.top,
    required this.x,
    required this.y,
    required this.colour,
    required this.halo,
    required this.cellWidth,
  });

  final double left, top, x, y, cellWidth;
  final Color colour, halo;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = left + (x + 0.5) * cellWidth, cy = top + (y + 0.5) * MapGrid.cellHeight;
    final cell = Rect.fromLTWH(
      left + x.round() * cellWidth,
      top + y.round() * MapGrid.cellHeight,
      cellWidth,
      MapGrid.cellHeight,
    );
    final under = Paint()
      ..color = halo
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final over = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas
      ..drawRect(cell.deflate(1), under)
      ..drawRect(cell.deflate(1), over);
    for (final p in [under, over]) {
      canvas
        ..drawLine(Offset(cx, top), Offset(cx, size.height), p..strokeWidth = p == under ? 3 : 1)
        ..drawLine(Offset(left, cy), Offset(size.width, cy), p);
    }
    canvas.drawCircle(Offset(cx, cy), 4, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_LivePainter old) =>
      old.x != x || old.y != y || old.colour != colour || old.cellWidth != cellWidth;
}
