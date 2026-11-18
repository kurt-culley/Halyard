import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:halyard_core/halyard_core.dart';

PortFinder ports() => _NativePorts();

final class _NativePorts implements PortFinder {
  @override
  bool get canAsk => false;

  @override
  Future<PortEntry?> ask() async => null;

  @override
  Future<List<PortEntry>> list() async {
    final names = SerialPort.availablePorts;
    // macOS lists each port twice; the call-out (cu) device is the one to open.
    final usable = Platform.isMacOS ? names.where((n) => !n.startsWith('/dev/tty.')) : names;
    return [for (final n in usable) _entry(n)];
  }

  PortEntry _entry(String name) {
    final port = SerialPort(name);
    try {
      final description = port.description;
      final vid = port.vendorId, pid = port.productId;
      String hex(int v) => v.toRadixString(16).toUpperCase().padLeft(4, '0');
      final usb = vid != null && pid != null ? ' (USB ${hex(vid)}:${hex(pid)})' : '';
      return PortEntry(
        name,
        '${description == null || description.isEmpty ? name : '$description, $name'}$usb',
        (baud) => NativeSerialTransport.open(name, baud),
        vendorId: vid,
        productId: pid,
      );
    } finally {
      port.dispose();
    }
  }
}

/// A port opened through libserialport: 8 data bits, no parity, one stop bit, no flow control.
final class NativeSerialTransport implements Transport {
  NativeSerialTransport._(this._port, this._reader) {
    _sub = _reader.stream.listen(
      _input.add,
      onError: (Object e) {
        _input.addError(e);
        unawaited(close());
      },
      onDone: () => unawaited(close()),
    );
  }

  static Future<Transport> open(String name, int baud) async {
    final port = SerialPort(name);
    if (!port.openReadWrite()) {
      final e = SerialPort.lastError;
      port.dispose();
      throw StateError('Could not open $name: ${e?.message ?? 'unknown error'}');
    }
    _configure(port, baud);
    return NativeSerialTransport._(port, SerialPortReader(port));
  }

  static void _configure(SerialPort port, int baud) {
    final c = SerialPortConfig()
      ..baudRate = baud
      ..bits = 8
      ..parity = SerialPortParity.none
      ..stopBits = 1
      ..setFlowControl(SerialPortFlowControl.none);
    port.config = c;
    c.dispose();
  }

  final SerialPort _port;
  final SerialPortReader _reader;
  final _input = StreamController<Uint8List>();
  late final StreamSubscription<Uint8List> _sub;
  var _closed = false;

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  Future<void> write(Uint8List bytes) async {
    if (_closed) throw StateError('The port is closed.');
    final n = _port.write(bytes, timeout: 1000);
    if (n != bytes.length) throw TimeoutException('The write timed out.');
  }

  @override
  Future<void> setBaudRate(int baud) async => _configure(_port, baud);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    _reader.close();
    _port
      ..close()
      ..dispose();
    await _input.close();
  }
}
