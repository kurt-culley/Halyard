/// What a platform implements to carry bytes to and from the ECU, and the timing that suits each kind of link.
library;

import 'dart:typed_data';

import '../wire/framing.dart';

/// An open byte link: serial port, USB serial, Web Serial or a TCP socket to a Wi-Fi bridge.
abstract interface class Transport {
  /// Received bytes, in order. Single subscription; ends when the link drops.
  Stream<Uint8List> get input;

  Future<void> write(Uint8List bytes);

  /// No-op where the link has no baud rate (USB CDC end to end, or a bridge without RFC 2217).
  Future<void> setBaudRate(int baud);

  Future<void> close();
}

/// Opens a transport at a baud rate. The platform layer supplies one per port.
typedef TransportOpener = Future<Transport> Function(int baudRate);

/// Timeouts and retry limits for one kind of link.
final class LinkTiming {
  const LinkTiming({
    this.replyTimeout = const Duration(seconds: 3),
    this.handshakeTimeout = const Duration(seconds: 1),
    this.watchdogPeriod = const Duration(seconds: 3),
    this.cancelDelay = const Duration(milliseconds: 500),
    this.errorDelay = const Duration(seconds: 3),
    this.maxAttempts = 15,
  });

  /// How long a request waits for its reply.
  final Duration replyTimeout;

  /// How long the identity request waits when connecting.
  final Duration handshakeTimeout;

  /// The connection drops when no frame arrives for a whole period.
  final Duration watchdogPeriod;

  /// Wait before reconnecting after a dropped connection, and after a failure to open.
  final Duration cancelDelay;
  final Duration errorDelay;

  /// Consecutive failed attempts before giving up.
  final int maxAttempts;

  /// A cable: the original tool's timings.
  static const cable = LinkTiming();

  /// Wi-Fi bridges add latency and jitter.
  static const wifi = LinkTiming(
    replyTimeout: Duration(seconds: 5),
    handshakeTimeout: Duration(milliseconds: 2500),
    watchdogPeriod: Duration(seconds: 6),
  );
}

/// Decides which frames may be written.
abstract interface class FramePolicy {
  bool allows(Frame f);
}

/// Reads only. Lets through requests that read, the RAM-only switches live data needs, and the lifesign; refuses
/// everything that changes the ECU, including the host's answers during a firmware transfer. Used on mobile and in
/// bench mode.
final class ReadOnlyPolicy implements FramePolicy {
  const ReadOnlyPolicy();

  static const _reads = {
    (0, 1), (0, 2), (0, 3), //       lifesign, reporting on/off, high-rate channel list (RAM)
    (1, 1), (1, 7), //               read a table, table live-cursor reporting (RAM)
    (2, 1), (2, 3), //               read a driver, CAN reserved ids
    (4, 0), (4, 1), (4, 5), //       identity, calibration hash, password-lock state
    (6, 0), (6, 1), (6, 5), (6, 6), (6, 7), // on-board log reads
    (7, 0), //                       trigger scope support
    (9, 0), (9, 1), (9, 2), (9, 3), // fault log reads
  };

  @override
  bool allows(Frame f) => f.type == MsgType.req && _reads.contains((f.cls, f.cmd));
}
