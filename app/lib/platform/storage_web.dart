import 'dart:js_interop';
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:web/web.dart' as web;

Future<AppStorage> storage() async => OpfsStorage(await web.window.navigator.storage.getDirectory().toDart);

FolderPicker folders() => const _NoFolders();

/// The origin-private file system: the browser's own storage for this site, a working copy the user exports from.
final class OpfsStorage implements AppStorage {
  OpfsStorage(this.root);
  final web.FileSystemDirectoryHandle root;

  Future<(web.FileSystemDirectoryHandle, String)?> _parent(String name, {required bool create}) async {
    final parts = name.split('/');
    var dir = root;
    for (final p in parts.take(parts.length - 1)) {
      try {
        dir = await dir.getDirectoryHandle(p, web.FileSystemGetDirectoryOptions(create: create)).toDart;
      } on Object {
        return null;
      }
    }
    return (dir, parts.last);
  }

  @override
  Future<Uint8List?> read(String name) async {
    final at = await _parent(name, create: false);
    if (at == null) return null;
    try {
      final handle = await at.$1.getFileHandle(at.$2).toDart;
      final file = await handle.getFile().toDart;
      return (await file.arrayBuffer().toDart).toDart.asUint8List();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    final at = (await _parent(name, create: true))!;
    final handle = await at.$1.getFileHandle(at.$2, web.FileSystemGetFileOptions(create: true)).toDart;
    final w = await handle.createWritable().toDart;
    await w.write(bytes.toJS).toDart;
    await w.close().toDart;
  }

  @override
  Future<void> delete(String name) async {
    final at = await _parent(name, create: false);
    if (at == null) return;
    try {
      await at.$1.removeEntry(at.$2).toDart;
    } on Object {
      // not there
    }
  }
}

final class _NoFolders implements FolderPicker {
  const _NoFolders();
  @override
  bool get available => false;
  @override
  Future<List<(String, String)>?> pick(String extension) async => null;
}
