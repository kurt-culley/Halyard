/// Measurement units and the conversions between the ECU's values and what the user sees (U11-M01 to M05), in
/// single-precision arithmetic as the original. The app holds the unit names and symbols.
library;

import '../wire/bytes.dart' show fround;

/// Units a definition can name for a value. [key] is the definition file's element name; [bit] is the original's
/// flag value, used by saved unit settings.
enum MeasurementUnit {
  raw('Raw', 1),
  ohm('Ohm', 2),
  volt('Volt', 4),
  kPa('KPa', 8),
  psi('PSI', 16),
  celsius('Celsius', 32),
  fahrenheit('Fahrenheit', 64);

  const MeasurementUnit(this.key, this.bit);
  final String key;
  final int bit;

  static MeasurementUnit? fromKey(String key) {
    for (final u in values) {
      if (u.key == key) return u;
    }
    return null;
  }
}

const _rawMax = 65535.0, _voltMax = 5.0, _internalResistance = 2700.0, _maxRawForOhm = 65000.0;
final _psiToKpa = fround(6.8947601318359375);
final _fahrenheitDivider = fround(1.8);
const _fahrenheitOffset = 32.0;

double withinBoundaries(double v, double min, double max) => v > max ? max : (v < min ? min : v);

/// The ECU's value (raw counts, kPa or °C) in [unit].
double fromRaw(MeasurementUnit unit, double value, {bool checkBoundaries = false}) {
  var v = fround(value);
  switch (unit) {
    case MeasurementUnit.raw:
      return checkBoundaries ? withinBoundaries(v, -_rawMax, _rawMax) : v;
    case MeasurementUnit.volt:
      final r = fround(fround(_voltMax * v) / _rawMax);
      return checkBoundaries ? withinBoundaries(r, -_voltMax, _voltMax) : r;
    case MeasurementUnit.ohm:
      if (!(v < _maxRawForOhm)) v = _maxRawForOhm;
      return fround(fround(_internalResistance * v) / fround(_rawMax - v));
    case MeasurementUnit.kPa || MeasurementUnit.celsius:
      return v;
    case MeasurementUnit.psi:
      return fround(v / _psiToKpa);
    case MeasurementUnit.fahrenheit:
      return fround(fround(v * _fahrenheitDivider) + _fahrenheitOffset);
  }
}

/// A value in [unit] as the ECU holds it. Fahrenheit converts as (F − 32) / 1.8; the original added 32
/// (docs/behaviour-changes.md).
double toRaw(MeasurementUnit unit, double value, {bool checkBoundaries = false}) {
  final v = fround(value);
  switch (unit) {
    case MeasurementUnit.raw:
      return checkBoundaries ? withinBoundaries(v, -_rawMax, _rawMax) : v;
    case MeasurementUnit.volt:
      final r = fround(fround(_rawMax * v) / _voltMax);
      return checkBoundaries ? withinBoundaries(r, -_rawMax, _rawMax) : r;
    case MeasurementUnit.ohm:
      final r = fround(fround(_rawMax * v) / fround(_internalResistance + v));
      return checkBoundaries ? withinBoundaries(r, -_rawMax, _rawMax) : r;
    case MeasurementUnit.kPa || MeasurementUnit.celsius:
      return v;
    case MeasurementUnit.psi:
      return fround(v * _psiToKpa);
    case MeasurementUnit.fahrenheit:
      return fround(fround(v - _fahrenheitOffset) / _fahrenheitDivider);
  }
}
