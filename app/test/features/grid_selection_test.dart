import 'package:flutter_test/flutter_test.dart';
import 'package:halyard/features/tables/grid_selection.dart';

void main() {
  test('a press selects one cell and the corner selects every value', () {
    final s = GridSelection(3, 4)..mouseDown((2, 3));
    expect(s.selected, {(2, 3)});
    s.mouseDown((0, 0));
    expect(s.count, 12);
  });

  test('shift and drag select a rectangle of values, or a run along an axis', () {
    final s = GridSelection(3, 4)..mouseDown((1, 1));
    s.mouseDown((2, 3), shift: true);
    expect(s.selected, {(1, 1), (1, 2), (1, 3), (2, 1), (2, 2), (2, 3)});
    s
      ..mouseDown((0, 1))
      ..mouseDrag((3, 3));
    expect(s.selected, {(0, 1), (0, 2), (0, 3)});
  });

  test('ctrl toggles cells of the same kind only', () {
    final s = GridSelection(3, 4)
      ..mouseDown((1, 1))
      ..mouseDown((2, 2), ctrl: true);
    expect(s.selected, {(1, 1), (2, 2)});
    s.mouseDown((1, 1), ctrl: true);
    expect(s.selected, {(2, 2)});
    s.mouseDown((0, 2), ctrl: true);
    expect(s.selected, {(0, 2)});
  });

  test('arrows stay within the values and shift extends', () {
    final s = GridSelection(3, 4)..setCurrentCell(1, 1);
    s.arrow(-1, -1);
    expect(s.current, (1, 1));
    s.arrow(1, 1, shift: true);
    expect(s.selected, {(1, 1), (1, 2), (2, 1), (2, 2)});
  });

  test('a continuous region is three or more indexes with none missing', () {
    expect(isContinuousRegion([3, 1, 2]), isTrue);
    expect(isContinuousRegion([1, 2]), isFalse);
    expect(isContinuousRegion([1, 2, 4]), isFalse);
  });
}
