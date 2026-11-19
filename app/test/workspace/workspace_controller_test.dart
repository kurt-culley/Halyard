import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:halyard/workspace/page_layout.dart';
import 'package:halyard/workspace/workspace_controller.dart';
import 'package:halyard_core/halyard_core.dart';

final class _MemoryStorage implements AppStorage {
  final files = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String name) async => files[name];
  @override
  Future<void> write(String name, Uint8List bytes) async => files[name] = bytes;
  @override
  Future<void> delete(String name) async => files.remove(name);
}

const _rpm = TileContent('readout', 1);

void main() {
  test('edits undo and redo per page, and pages come back after a restart', () async {
    final storage = _MemoryStorage();
    final c = WorkspaceController(storage);
    await c.load();
    expect(c.pages.single.name, 'Page 1');

    c.edit((p) => p.setContent(0, _rpm));
    c.edit((p) => p.split(0, DropSide.right));
    expect(c.page.tiles, hasLength(2));
    c.undo();
    expect(c.page.tiles.single.content, _rpm);
    c.redo();
    expect(c.page.tiles, hasLength(2));

    c.addPage();
    expect(c.canUndo, isFalse, reason: 'each page has its own history');
    c.rename('Boost');
    c.select(0);
    expect(c.canUndo, isTrue);
    await Future<void>.delayed(Duration.zero);

    final again = WorkspaceController(storage);
    await again.load();
    expect([for (final p in again.pages) p.name], ['Page 1', 'Boost']);
    expect(again.current, 0);
    expect(again.page.tiles.first.content, _rpm);
  });

  test('removing the last page leaves a blank one', () async {
    final c = WorkspaceController(_MemoryStorage());
    await c.load();
    c.edit((p) => p.setContent(0, _rpm));
    c.removePage();
    expect(c.page.tiles.single.content, TileContent.empty);
  });
}
