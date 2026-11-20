import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:path_provider/path_provider.dart';

Future<AppStorage> storage() async => FileStorage(await getApplicationSupportDirectory());

FolderPicker folders() => _NativeFolders();

FileSaver saver() => const _SaveDialog();

final class _SaveDialog implements FileSaver {
  const _SaveDialog();

  @override
  Future<bool> save(String suggestedName, Uint8List bytes) async {
    final at = await getSaveLocation(suggestedName: suggestedName);
    if (at == null) return false;
    await File(at.path).writeAsBytes(bytes, flush: true);
    return true;
  }
}

/// Files under a directory (the app support directory in the app).
final class FileStorage implements AppStorage {
  FileStorage(this.root);
  final Directory root;

  File _file(String name) => File('${root.path}/$name');

  @override
  Future<Uint8List?> read(String name) async {
    final f = _file(name);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    final f = _file(name);
    await f.parent.create(recursive: true);
    // Write beside, then rename, so a crash never leaves half a file.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String name) async {
    final f = _file(name);
    if (await f.exists()) await f.delete();
  }
}

final class _NativeFolders implements FolderPicker {
  @override
  bool get available => true;

  @override
  Future<List<(String, String)>?> pick(String extension) async {
    final path = await getDirectoryPath();
    if (path == null) return null;
    return readFolder(Directory(path), extension);
  }
}

/// The files directly in [dir] ending in [extension] (any case), by name.
Future<List<(String, String)>> readFolder(Directory dir, String extension) async {
  final files = [
    await for (final e in dir.list())
      if (e is File && e.path.toLowerCase().endsWith(extension.toLowerCase())) e,
  ]..sort((a, b) => a.path.compareTo(b.path));
  return [for (final f in files) (f.uri.pathSegments.last, await f.readAsString())];
}

DemoDefinitionSource demoDefinition() => const _NoDemo();

final class _NoDemo implements DemoDefinitionSource {
  const _NoDemo();
  @override
  Future<String?> fetch() async => null;
}
