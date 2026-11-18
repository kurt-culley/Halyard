/// The simulated ECU as a [Transport], so the real channel and connection code run against it unchanged.
library;

import 'dart:async';
import 'dart:typed_data';

import '../link/transport.dart';
import '../wire/framing.dart';
import 'sim_ecu.dart';

/// Opens the simulator: a [TransportOpener].
Future<Transport> openSimulator(SimEcu ecu, int baudRate) async => SimTransport(ecu, baudRate);

class SimTransport implements Transport {
  /// Connects [ecu]; it answers only while [baudRate] matches its own.
  SimTransport(this.ecu, this.baudRate) {
    ecu.attach((b) {
      if (!_in.isClosed) _in.add(b);
    });
  }

  final SimEcu ecu;
  int baudRate;
  final _in = StreamController<Uint8List>();
  final _decoder = FrameDecoder();

  @override
  Stream<Uint8List> get input => _in.stream;

  /// Like a cable to the simulator, frames reach it whatever their checksum. A request it can't apply goes unanswered.
  @override
  Future<void> write(Uint8List bytes) async {
    if (_in.isClosed) throw StateError('port closed');
    for (final r in _decoder.pushRaw(bytes)) {
      if (baudRate != ecu.baudRate) continue;
      try {
        ecu.handle(r.frame);
      } on Object {
        // unanswered, as a real ECU would leave a request it can't apply
      }
    }
  }

  @override
  Future<void> setBaudRate(int baud) async => baudRate = baud;

  @override
  Future<void> close() async {
    ecu.attach(null);
    if (!_in.isClosed) unawaited(_in.close());
  }
}
