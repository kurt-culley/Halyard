/// Files the app reaches for the core: its own storage, folders and files the user picks, and files the user saves.
/// The core has no I/O; the platform layer implements these.
library;

import 'dart:typed_data';

/// The app's own files: the app support directory natively, the origin-private file system on the web. Names are
/// relative paths with `/` separators.
abstract interface class AppStorage {
  /// Null when there is no such file.
  Future<Uint8List?> read(String name);
  Future<void> write(String name, Uint8List bytes);

  /// Does nothing when there is no such file.
  Future<void> delete(String name);
}

/// A folder of files the user picks, where the platform allows it (desktop, not the web).
abstract interface class FolderPicker {
  bool get available;

  /// The name and text of each file in the chosen folder with [extension] (".medef"); null when cancelled.
  Future<List<(String, String)>?> pick(String extension);
}

/// Saving a file the user keeps: a save dialog natively, a download in a browser.
abstract interface class FileSaver {
  /// False when the user cancelled.
  Future<bool> save(String suggestedName, Uint8List bytes);
}
