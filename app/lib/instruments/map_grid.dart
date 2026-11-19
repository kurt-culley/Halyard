import 'package:material_ui/material_ui.dart';

/// A map or curve as a grid: column axis across the top, row axis down the side (none for a curve), each cell
/// shaded by its place in the table's range, and the live cell outlined.
class MapGrid extends StatelessWidget {
  const MapGrid({
    super.key,
    required this.columns,
    required this.rows,
    required this.cells,
    required this.shades,
    this.live,
  });

  final List<String> columns;

  /// Empty for a curve.
  final List<String> rows;

  /// Row-major, one row for a curve.
  final List<String> cells;

  /// 0 to 1 per cell; NaN leaves a cell unshaded.
  final List<double> shades;

  /// The live cell: (row, column).
  final (int, int)? live;

  static const cellWidth = 64.0, cellHeight = 26.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final head = style.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant);
    final n = rows.isEmpty ? 1 : rows.length;
    Widget box(String text, TextStyle s, {Color? fill, bool outline = false}) => Container(
      width: cellWidth,
      height: cellHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        border: outline ? Border.all(color: scheme.onSurface, width: 2) : null,
      ),
      child: Text(text, style: s, overflow: TextOverflow.clip, maxLines: 1),
    );
    Color? shade(double t) => t.isNaN ? null : Color.lerp(scheme.primaryContainer, scheme.errorContainer, t);
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [if (rows.isNotEmpty) box('', head), for (final c in columns) box(c, head)]),
            for (var r = 0; r < n; r++)
              Row(
                children: [
                  if (rows.isNotEmpty) box(rows[r], head),
                  for (var c = 0; c < columns.length; c++)
                    box(
                      cells[r * columns.length + c],
                      style,
                      fill: shade(shades[r * columns.length + c]),
                      outline: live == (r, c),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
