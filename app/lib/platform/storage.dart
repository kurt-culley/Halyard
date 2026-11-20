import 'package:halyard_core/halyard_core.dart';

import 'storage_native.dart' if (dart.library.js_interop) 'storage_web.dart' as impl;

/// The app's own storage on this platform.
Future<AppStorage> platformStorage() => impl.storage();

/// Picking a folder of files, where the platform allows it.
FolderPicker platformFolders() => impl.folders();

/// Saving files the user keeps on this platform.
FileSaver platformSaver() => impl.saver();

/// Halyard's own synthetic definition for demo mode, where the platform serves one.
DemoDefinitionSource platformDemoDefinition() => impl.demoDefinition();
