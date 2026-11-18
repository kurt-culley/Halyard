/// The ECU's fault codes: what each number means, as the original tool's catalogue gave it (U13-C01, C02). The app
/// shows the names; display text for kinds, severities and states lives in the app.
library;

enum FaultKind { fault, event }

/// Info 0, warning 1, fault 2, critical 3; other values come from the ECU as numbers.
abstract final class FaultSeverity {
  static const info = 0, warning = 1, fault = 2, critical = 3;
}

/// Idle 0, pending 1, active 2, active in cooldown 3, stored 4.
abstract final class FaultState {
  static const idle = 0, pending = 1, active = 2, cooldown = 3, stored = 4;
  static bool isActive(int s) => s == active || s == cooldown;
}

/// Occurrence 1, checkpoint 2, counters cleared 3, logging mode changed 4.
abstract final class FaultRecordType {
  static const occurrence = 1, checkpoint = 2, clear = 3, config = 4;
}

/// Logging off 0, faults only 1, faults and events 2.
abstract final class FaultLogMode {
  static const off = 0, faultsOnly = 1, faultsAndEvents = 2;
}

final class FaultCode {
  const FaultCode(this.index, this.code, this.name, this.kind, this.severity, {this.isKnown = true});

  /// A code the catalogue doesn't have: index -1, named by its number.
  const FaultCode.unknown(this.code, [this.severity = FaultSeverity.info])
    : index = -1,
      name = 'Code $code',
      kind = FaultKind.fault,
      isKnown = false;

  /// Position in the catalogue: active-code bits count in this order.
  final int index;
  final int code;
  final String name;
  final FaultKind kind;
  final int severity;
  final bool isKnown;
}

final List<FaultCode> faultCatalogue = List.unmodifiable(() {
  final list = <FaultCode>[];
  void add(int code, String name, FaultKind kind, int severity) =>
      list.add(FaultCode(list.length, code, name, kind, severity));
  const f = FaultKind.fault, e = FaultKind.event;
  add(101, 'Crank sync lost', f, 2);
  add(102, 'Cam sync lost', f, 1);
  for (var i = 1; i <= 15; i++) {
    add(200 + i, 'Analog C$i stuck low', f, 2);
  }
  for (var i = 1; i <= 15; i++) {
    add(230 + i, 'Analog C$i stuck high', f, 2);
  }
  add(301, 'DBW pedal sensor fail', f, 2);
  add(302, 'DBW throttle sensor fail', f, 2);
  add(303, 'DBW failsafe entered', f, 3);
  add(401, 'Wideband heater short to ground', f, 2);
  add(402, 'Wideband heater short to battery', f, 2);
  add(403, 'Wideband heater open', f, 2);
  add(404, 'Wideband sensor short to ground', f, 2);
  add(405, 'Wideband sensor short to battery', f, 2);
  add(406, 'Wideband supply low', f, 1);
  add(411, 'EGT thermocouple open', f, 2);
  add(412, 'EGT comms error', f, 2);
  add(601, 'SD card error', f, 1);
  add(602, 'SD card not formatted', f, 0);
  add(701, 'Watchdog reset', f, 3);
  add(702, 'Brownout reset', f, 1);
  add(703, 'Core lockup reset', f, 3);
  add(704, 'Clock loss reset', f, 3);
  add(711, 'Battery low (< 7 V)', f, 1);
  add(801, 'EPS oil temperature', e, 1);
  add(802, 'EPS oil pressure', e, 1);
  add(803, 'EPS fuel pressure', e, 1);
  add(804, 'EPS lambda', e, 1);
  add(805, 'EPS EGT', e, 1);
  add(806, 'EPS knock', e, 1);
  add(807, 'EPS overboost', e, 1);
  add(901, 'Rev limiter', e, 1);
  add(902, 'Launch control limiter', e, 0);
  add(903, 'Boost cut', e, 1);
  add(904, 'GPT limiter', e, 0);
  add(905, 'EPS limiter', e, 1);
  add(906, 'Gear cut', e, 0);
  add(907, 'Traction control cut', e, 0);
  add(908, 'Overboost', e, 1);
  add(909, 'Knock DSP error', f, 2);
  add(910, 'Knock max retard', e, 1);
  return list;
}());

final Map<int, FaultCode> _byCode = {for (final c in faultCatalogue) c.code: c};

/// The catalogue entry for [code], or [FaultCode.unknown]. A summary entry passes its own severity for unknown codes.
FaultCode faultCode(int code, [int unknownSeverity = FaultSeverity.info]) =>
    _byCode[code] ?? FaultCode.unknown(code, unknownSeverity);
