import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:web/web.dart' as web;

/// Web Serial (Chrome and Edge). Ports are only those the user has granted to this page.
PortFinder ports() => WebSerialPorts(_navigatorSerial);

@JS('navigator.serial')
external JSSerial? get _navigatorSerial;

/// The Web Serial API, as far as Halyard uses it.
extension type JSSerial._(JSObject _) implements JSObject {
  external JSPromise<JSArray<JSSerialPort>> getPorts();
  external JSPromise<JSSerialPort> requestPort();
}

extension type JSSerialPort._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> open(JSSerialOptions options);
  external JSPromise<JSAny?> close();
  external web.ReadableStream? get readable;
  external web.WritableStream? get writable;
  external JSSerialPortInfo getInfo();
}

extension type JSSerialOptions._(JSObject _) implements JSObject {
  external factory JSSerialOptions({
    int baudRate,
    int dataBits,
    int stopBits,
    String parity,
    String flowControl,
    int bufferSize,
  });
}

extension type JSSerialPortInfo._(JSObject _) implements JSObject {
  external int? get usbVendorId;
  external int? get usbProductId;
}

final class WebSerialPorts implements PortFinder {
  WebSerialPorts(this._serial);

  final JSSerial? _serial;
  final _ids = <JSSerialPort, String>{};

  @override
  bool get canAsk => _serial != null;

  @override
  Future<List<PortEntry>> list() async {
    final s = _serial;
    if (s == null) return const [];
    final ports = (await s.getPorts().toDart).toDart;
    return [for (final p in ports) _entry(p)];
  }

  @override
  Future<PortEntry?> ask() async {
    final s = _serial;
    if (s == null) return null;
    try {
      return _entry(await s.requestPort().toDart);
    } on Object {
      return null; // the picker was dismissed
    }
  }

  PortEntry _entry(JSSerialPort p) {
    final info = p.getInfo();
    final vid = info.usbVendorId, pid = info.usbProductId;
    String hex(int v) => v.toRadixString(16).toUpperCase().padLeft(4, '0');
    final base = vid != null && pid != null ? 'USB ${hex(vid)}:${hex(pid)}' : 'Serial';
    final id = _ids[p] ??= () {
      var id = base;
      for (var n = 2; _ids.containsValue(id); n++) {
        id = '$base #$n';
      }
      return id;
    }();
    return PortEntry(id, id, (baud) => WebSerialTransport.open(p, baud), vendorId: vid, productId: pid);
  }
}

/// A granted port. Web Serial can't change an open port's rate, so a new rate closes and reopens it.
final class WebSerialTransport implements Transport {
  WebSerialTransport._(this._port, this._baud);

  static Future<Transport> open(JSSerialPort port, int baud) async {
    final t = WebSerialTransport._(port, baud);
    await t._start();
    return t;
  }

  final JSSerialPort _port;
  int _baud;
  final _input = StreamController<Uint8List>();
  web.ReadableStreamDefaultReader? _reader;
  Future<void>? _loop;
  Future<void> _ops = Future.value();
  var _closed = false;

  static const writeTimeout = Duration(seconds: 1);

  @override
  Stream<Uint8List> get input => _input.stream;

  Future<T> _queue<T>(Future<T> Function() f) {
    final r = _ops.then((_) => f());
    _ops = r.then((_) {}, onError: (Object _) {});
    return r;
  }

  Future<void> _start() async {
    await _port
        .open(
          JSSerialOptions(
            baudRate: _baud,
            dataBits: 8,
            stopBits: 1,
            parity: 'none',
            flowControl: 'none',
            bufferSize: 4096,
          ),
        )
        .toDart;
    final reader = _port.readable!.getReader() as web.ReadableStreamDefaultReader;
    _reader = reader;
    _loop = _read(reader);
  }

  Future<void> _read(web.ReadableStreamDefaultReader r) async {
    try {
      for (;;) {
        final chunk = await r.read().toDart;
        if (chunk.done) break;
        final v = chunk.value;
        if (v != null && identical(_reader, r)) _input.add((v as JSUint8Array).toDart);
      }
    } on Object catch (e) {
      // The device went away while open.
      if (identical(_reader, r) && !_closed) {
        _input.addError(e);
        unawaited(close());
      }
    } finally {
      r.releaseLock();
    }
  }

  Future<void> _stop() async {
    final r = _reader;
    _reader = null;
    if (r == null) return;
    try {
      await r.cancel().toDart;
    } on Object {
      // already cancelled
    }
    await _loop;
  }

  @override
  Future<void> write(Uint8List bytes) => _queue(() async {
    final writable = _port.writable;
    if (_closed || writable == null) throw StateError('The port is closed.');
    final w = writable.getWriter();
    try {
      await w.write(bytes.toJS).toDart.timeout(writeTimeout);
    } finally {
      w.releaseLock();
    }
  });

  @override
  Future<void> setBaudRate(int baud) => _queue(() async {
    if (baud == _baud || _closed) return;
    _baud = baud;
    await _stop();
    await _port.close().toDart;
    await _start();
  });

  @override
  Future<void> close() => _queue(() async {
    if (_closed) return;
    _closed = true;
    await _stop();
    try {
      await _port.close().toDart;
    } on Object {
      // the port has gone
    }
    await _input.close();
  });
}
