import 'package:halyard_core/halyard_core.dart';

/// The custom CAN editor's words, the original's where it had them (without its vendor's contact details).
abstract final class CanStrings {
  static const title = 'Custom CAN';
  static const notOnline = 'Operation can only be performed while the ECU is connected or a calibration is loaded.';
  static const notSupported =
      'Custom CAN messages are not supported by the loaded ECU definition.\n\nThis feature requires a GEN2B or GEN2D '
      'ECU running firmware with definition version 83 or newer.';
  static const wasReset = 'No valid custom CAN configuration was found on the ECU — starting fresh.';
  static const inputs = 'Inputs (receive)';
  static const outputs = 'Outputs (transmit)';
  static const unused = 'Unused';
  static const enabled = 'Enabled';
  static const canId = 'CAN ID (hex)';
  static const extended = 'Extended (29-bit)';
  static const bigEndian = 'Big endian (Motorola)';
  static const mux = 'Multiplexed';
  static const muxStart = 'Mux start bit';
  static const muxLength = 'Mux bit length';
  static const muxMatch = 'Mux value';
  static const mode = 'Send mode';
  static const modes = ['Periodic', 'Event-driven periodic', 'Event-driven one-shot'];
  static const rate = 'Rate (Hz)';
  static const trigger = 'Trigger channel';
  static const signals = 'Signals';
  static const signal = 'Signal';
  static const start = 'Start bit';
  static const length = 'Bit length';
  static const format = 'Format';
  static const formats = ['Unsigned', 'Signed', 'Bool', 'Float32'];
  static const signed = 'Signed';
  static const mult = 'Multiplier';
  static const offset = 'Offset';
  static const timeout = 'Timeout ms';
  static const fallback = 'Fallback';
  static const target = 'Write to channel';
  static const source = 'Data source';
  static const fixed = 'Fixed value';
  static const none = 'None';
  static const bits = 'Bits (byte 0 at the top, bit 7 on the left)';
  static const save = 'Save and store';
  static const saved = 'Saved and stored.';
  static const revert = 'Revert';
  static const errors = 'Fix these before saving:';
  static const readOnly = 'Read only is on: turn it off on the connect page to save.';
  static const outputHelp =
      'If no data source is set, then the "Fixed value" will be transmitted for this variable. Values are quantized '
      'before transmit: raw = round((value - offset) / multiplier), clamped to the range of the bit length and '
      'signedness.';
  static String failed(String what) => 'The ECU did not accept the configuration ($what).';
  static String hex(int v) => '0x${formatCanId(v)}';

  /// The original's check messages.
  static String issue(CanIssue i) {
    String h(int v) => (v & 0xffffffff).toRadixString(16).toUpperCase();
    final n = (i.signal ?? 0) + 1;
    return switch (i.kind) {
      CanIssueKind.idOutOfRange =>
        'CAN ID 0x${h(i.a)} is outside the ${i.extended ? 'extended' : 'standard'} range (max 0x${h(i.b)}).',
      CanIssueKind.idReserved => 'CAN ID 0x${h(i.a)} is used by the selected OEM CAN stream.',
      CanIssueKind.muxLength => 'Mux selector length ${i.a} is outside 1-32.',
      CanIssueKind.muxSpan => 'Mux selector at bit ${i.a} length ${i.b} does not fit the frame.',
      CanIssueKind.signalSpan => 'Signal $n at bit ${i.a} length ${i.b} does not fit the frame.',
      CanIssueKind.signalMultiplier => 'Signal $n multiplier must be non-zero and finite.',
      CanIssueKind.signalFloatLength => 'Signal $n is float32 and must be exactly 32 bits, not ${i.a}.',
      CanIssueKind.signalNoTarget => 'Signal $n has no target channel.',
      CanIssueKind.signalTargetMissing => 'Signal $n target channel ${i.a} does not exist.',
      CanIssueKind.rate => 'Rate ${i.a} Hz is outside 1-1000.',
      CanIssueKind.unknownMode => 'Unknown transmit mode.',
      CanIssueKind.noTrigger => 'Event-driven mode needs a trigger channel.',
      CanIssueKind.triggerMissing => 'Trigger channel ${i.a} does not exist.',
      CanIssueKind.sourceMissing =>
        'Signal $n source channel ${i.a} does not exist; its constant value is transmitted instead.',
    };
  }
}
