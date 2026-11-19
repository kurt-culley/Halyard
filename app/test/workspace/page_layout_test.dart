import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:halyard/workspace/page_layout.dart';

const _rpm = TileContent('readout', 1);
const _map = TileContent('readout', 2);

void main() {
  test('splitting, filling, moving and closing tiles', () {
    var p = const PageLayout.blank('Engine').setContent(0, _rpm);
    p = p.split(0, DropSide.right, _map);
    expect([for (final t in p.tiles) t.content], [_rpm, _map]);
    p = p.split(0, DropSide.top);
    expect([for (final t in p.tiles) t.content], [TileContent.empty, _rpm, _map]);
    final ids = [for (final t in p.tiles) t.id];
    expect(ids.toSet(), hasLength(3));

    p = p.move(ids[2], ids[0], DropSide.left);
    expect([for (final t in p.tiles) t.content], [_map, TileContent.empty, _rpm]);

    p = p.close(ids[0]);
    expect([for (final t in p.tiles) t.content], [_map, _rpm]);
    p = p.close(ids[2]).close(ids[1]);
    expect(p.tiles.single.content, TileContent.empty);
  });

  test('resizing keeps both parts visible', () {
    final p = const PageLayout.blank('x').split(0, DropSide.bottom);
    final split = p.root as SplitNode;
    expect((p.resize(split.id, 0.02).root as SplitNode).fraction, PageLayout.minFraction);
    expect((p.resize(split.id, 0.7).root as SplitNode).fraction, 0.7);
    expect(split.axis, SplitAxis.column);
  });

  test('moving onto itself or a missing tile changes nothing', () {
    final p = const PageLayout.blank('x').split(0, DropSide.right);
    expect(identical(p.move(0, 0, DropSide.left), p), isTrue);
    expect(identical(p.move(0, 99, DropSide.left), p), isTrue);
  });

  test('a page survives JSON', () {
    final p = const PageLayout.blank('Boost').setContent(0, _rpm).split(0, DropSide.bottom, _map).resize(2, 0.3);
    final back = PageLayout.fromJson((jsonDecode(jsonEncode(p.toJson())) as Map).cast());
    expect(jsonEncode(back.toJson()), jsonEncode(p.toJson()));
  });
}
