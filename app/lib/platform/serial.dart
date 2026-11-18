import 'package:halyard_core/halyard_core.dart';

import 'serial_native.dart' if (dart.library.js_interop) 'serial_web.dart' as impl;

/// The serial ports of the platform the app runs on: Web Serial in a browser, the operating system's otherwise.
PortFinder platformPorts() => impl.ports();
