/// The definitions the user has added, by where they came from (a file, a folder or a URL; the app reads them).
/// Halyard ships none. A connected ECU gets the definition for its own model, or else a generic one for its product
/// and version (U10 D02).
library;

import 'definition.dart';
import 'device_file.dart';

final class DefinitionLibrary {
  final _files = <String, DeviceFile>{};

  /// Where each definition came from, in the order added.
  Iterable<String> get sources => _files.keys;

  DeviceFile? operator [](String source) => _files[source];

  /// Reads a definition's text and keeps it under [source], replacing one from the same source. Throws
  /// [DeviceFileError] for a file that isn't a usable definition.
  DeviceFile add(String source, String xml) => _files[source] = readDeviceFile(xml);

  void remove(String source) => _files.remove(source);

  /// The definition for [ecu]: one for its exact model, otherwise the last generic one that describes it.
  DeviceFile? lookup(DeviceInfo ecu) {
    DeviceFile? generic;
    for (final f in _files.values) {
      final info = f.definition.info;
      if (info.describes(ecu) && !info.isGeneric) return f;
      if (info.describes(ecu)) generic = f;
    }
    return generic;
  }
}
