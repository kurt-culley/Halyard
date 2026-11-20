import 'dart:js_interop';
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:web/web.dart' as web;

Future<AppStorage> storage() async => OpfsStorage(await web.window.navigator.storage.getDirectory().toDart);

FolderPicker folders() => const _NoFolders();

FileSaver saver() => const _Download();

DemoDefinitionSource demoDefinition() => const _ServedDemo();

/// demo.medef beside the app: the publish workflow writes it from tool/demo_definition.mjs.
final class _ServedDemo implements DemoDefinitionSource {
  const _ServedDemo();

  @override
  Future<String?> fetch() async {
    try {
      final r = await web.window.fetch('demo.medef'.toJS).toDart;
      if (!r.ok) return null;
      return (await r.text().toDart).toDart;
    } on Object {
      return null;
    }
  }
}

/// A browser download of the bytes.
final class _Download implements FileSaver {
  const _Download();

  @override
  Future<bool> save(String suggestedName, Uint8List bytes) async {
    final blob = web.Blob([bytes.toJS].toJS);
    final url = web.URL.createObjectURL(blob);
    (web.document.createElement('a') as web.HTMLAnchorElement)
      ..href = url
      ..download = suggestedName
      ..click();
    web.URL.revokeObjectURL(url);
    return true;
  }
}

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
