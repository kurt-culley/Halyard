/// The table grid's selection, as the original's grid surface kept it. Cells are (row, col) in the original's grid
/// coordinates: row 0 is the column axis, col 0 is the row axis, (0, 0) is the corner, and values start at (1, 1).
/// A curve has no row axis, so its col 0 is never chosen.
class GridSelection {
  GridSelection(int rows, int cols) : rowCount = rows + 1, colCount = cols + 1;

  /// Rows and columns of the grid, axes included.
  final int rowCount, colCount;

  final _cells = <(int, int)>{};
  (int, int) current = (1, 1);
  (int, int)? anchor, dragAnchor;

  Set<(int, int)> get selected => _cells;
  int get count => _cells.length;
  bool has((int, int) c) => _cells.contains(c);

  void clear() => _cells.clear();

  void _select((int, int) c) {
    current = c;
    _cells
      ..clear()
      ..add(c);
  }

  /// Moves to a value cell, clamped into the values.
  void setCurrentCell(int row, int col) {
    if (rowCount <= 1 || colCount <= 1) return;
    _select((row.clamp(1, rowCount - 1), col.clamp(1, colCount - 1)));
    anchor = current;
  }

  void selectAllValues() {
    _cells.clear();
    for (var r = 1; r < rowCount; r++) {
      for (var c = 1; c < colCount; c++) {
        _cells.add((r, c));
      }
    }
  }

  /// The corner selects every value; anything else selects that cell.
  void selectFromHit((int, int) c) => c == (0, 0) ? selectAllValues() : _select(c);

  /// Along an axis when both ends are on it, else the rectangle of values between them.
  void selectRectangle((int, int) a, (int, int) b) {
    _cells.clear();
    int lo(int x, int y, int min) => (x < y ? x : y) < min ? min : (x < y ? x : y);
    int hi(int x, int y, int max) => (x > y ? x : y) > max ? max : (x > y ? x : y);
    if (a.$1 == 0 && b.$1 == 0) {
      for (var c = lo(a.$2, b.$2, 1); c <= hi(a.$2, b.$2, colCount - 1); c++) {
        _cells.add((0, c));
      }
    } else if (a.$2 == 0 && b.$2 == 0) {
      for (var r = lo(a.$1, b.$1, 1); r <= hi(a.$1, b.$1, rowCount - 1); r++) {
        _cells.add((r, 0));
      }
    } else {
      for (var r = lo(a.$1, b.$1, 1); r <= hi(a.$1, b.$1, rowCount - 1); r++) {
        for (var c = lo(a.$2, b.$2, 1); c <= hi(a.$2, b.$2, colCount - 1); c++) {
          _cells.add((r, c));
        }
      }
    }
  }

  /// 1 for the column axis, 2 for the row axis, 0 for values.
  static int kind((int, int) c) => c.$1 == 0 ? 1 : (c.$2 == 0 ? 2 : 0);

  (int, int) _alongAnchor((int, int) a, (int, int) c) => a.$1 == 0 ? (0, c.$2) : (a.$2 == 0 ? (c.$1, 0) : c);

  /// A press: Shift extends from the anchor (kept on its axis), Ctrl toggles a cell of the same kind, a right
  /// press keeps a selection it lands in, anything else selects.
  void mouseDown((int, int) c, {bool shift = false, bool ctrl = false, bool right = false}) {
    if (right) {
      dragAnchor = null;
      if (!has(c)) selectFromHit(c);
      return;
    }
    final corner = c == (0, 0);
    if (!corner && shift) {
      final a = anchor ?? current;
      anchor = a;
      dragAnchor = a;
      selectRectangle(a, _alongAnchor(a, c));
      return;
    }
    if (!corner && ctrl) {
      dragAnchor = null;
      if (!_cells.every((x) => kind(x) == kind(c))) {
        anchor = c;
        selectFromHit(c);
        return;
      }
      if (!_cells.remove(c)) {
        _cells.add(c);
        current = c;
        anchor = c;
      }
      return;
    }
    anchor = c;
    dragAnchor = c;
    selectFromHit(c);
  }

  /// A drag with the button held: the rectangle from where it started (kept on its axis).
  void mouseDrag((int, int) c) {
    final a = dragAnchor;
    if (a == null) return;
    selectRectangle(a, _alongAnchor(a, c));
  }

  void mouseUp() => dragAnchor = null;

  /// Arrow keys move within the values; Shift extends from the anchor.
  void arrow(int dRow, int dCol, {bool shift = false}) {
    if (rowCount <= 1 || colCount <= 1) return;
    final row = (current.$1 + dRow).clamp(1, rowCount - 1), col = (current.$2 + dCol).clamp(1, colCount - 1);
    if (shift) {
      anchor ??= current;
      selectRectangle(anchor!, (row, col));
      current = (row, col);
    } else {
      setCurrentCell(row, col);
    }
  }
}

/// Whether [xs] is three or more indexes covering a range with none missing, as the original's menu tested.
bool isContinuousRegion(List<int> xs) {
  if (xs.length <= 2) return false;
  var lo = xs.first, hi = xs.first, sum = 0;
  for (final v in xs) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
    sum += v;
  }
  return sum == (hi * (hi + 1)) ~/ 2 - (lo * (lo - 1)) ~/ 2;
}
