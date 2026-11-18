/// How a live value reads (U11 V06 to V09, C01 to C03): its text (a listed text, a percentage or a number), whether
/// it is outside the link's range, and which of the link's feedbacks (colour states) it selects. A feedback's
/// warning can be acknowledged until the value next passes it.
library;

import '../definition/definition.dart';
import '../logs/number_text.dart';
import '../wire/bytes.dart' show fround;

/// Shown for a value the link's list of texts doesn't have.
const valueNotListed = 'N/A';

/// The link's name with its unit in brackets, when it has one.
String? linkNameWithUnit(LinkDef l) {
  final u = l.measureUnit;
  return u == null || u.isEmpty ? l.name : '${l.name ?? ''} ($u)';
}

/// Outside the link's minimum and maximum (never when they are equal).
bool isOutOfBounds(LinkDef l, double value) => l.minValue != l.maxValue && (value < l.minValue || value > l.maxValue);

/// The listed text for exactly [value]; null when the link lists none.
String? listedText(LinkDef l, double value) {
  final texts = l.textValues;
  if (texts == null || texts.isEmpty) return null;
  final k = fround(value);
  return texts.containsKey(k) ? texts[k] : valueNotListed;
}

/// A value as instruments show it: a listed text (the value rounded to a whole number), a trim as a signed
/// percentage from 1, a percentage, or the number with [decimals] decimals.
String? linkValueText(LinkDef l, double value, int decimals) {
  final texts = l.textValues;
  if (texts != null && texts.isNotEmpty) {
    final k = roundOneDecimalToInt(value).toDouble();
    return texts.containsKey(k) ? texts[k] : valueNotListed;
  }
  switch (l.dataType) {
    case LinkDataType.trimModPercent:
      final d = fround(value - 1);
      return d < 0 ? formatPercent(d) : formatPercent(d, prefix: '+');
    case LinkDataType.percent:
      return formatPercent(value);
    case LinkDataType.normal || LinkDataType.adcRaw:
      return formatFixed(value, decimals);
  }
}

/// `(int)Math.Round(v, 1)`: half to even at one decimal, then truncated; NaN and values out of range give
/// int.MinValue, as the x86 conversion does.
int roundOneDecimalToInt(double v) {
  var r = v;
  if (v.abs() < 1e16) {
    final t = v * 10;
    var n = t.floorToDouble();
    if (t - n >= 0.5) n += 1;
    if (t.remainder(1).abs() == 0.5 && n % 2 != 0) n -= 1;
    r = n / 10;
  }
  if (r.isNaN || r >= 2147483648 || r <= -2147483649) return -2147483648;
  return r.truncate();
}

final class _ConstraintState {
  _ConstraintState(this.c) : testValue = c.kind == ConstraintKind.gtInc ? c.values.first : 0;
  final Constraint c;
  bool acknowledged = false;
  double testValue;
  double lastValidated = 0;

  bool holdsFor(double v) {
    final ok = switch (c.kind) {
      ConstraintKind.eq => c.values.contains(v),
      ConstraintKind.gt => v > c.values.first,
      ConstraintKind.gtEq => v >= c.values.first,
      ConstraintKind.lt => v < c.values.first,
      ConstraintKind.ltEq => v <= c.values.first,
      ConstraintKind.gtInc => v > testValue,
    };
    if (acknowledged && ok) acknowledged = false;
    if (c.kind == ConstraintKind.gtInc) lastValidated = v;
    return ok;
  }

  void acknowledge() {
    acknowledged = true;
    if (c.kind == ConstraintKind.gtInc) testValue = lastValidated;
  }
}

/// A link's feedbacks with their state. A rising-threshold constraint, once acknowledged, waits for the value to
/// pass the level it was acknowledged at.
final class LinkFeedbacks {
  LinkFeedbacks(LinkDef link)
    : feedbacks = link.feedbacks ?? const [],
      _states = [
        for (final f in link.feedbacks ?? const <Feedback>[])
          [for (final c in f.constraints ?? const <Constraint>[]) _ConstraintState(c)],
      ];

  final List<Feedback> feedbacks;
  final List<List<_ConstraintState>> _states;
  int? _last;

  /// The index of the feedback [value] selects: the last one whose constraints all hold (each is tested until one
  /// fails), or null for none.
  int? select(double value) {
    int? chosen;
    for (var i = 0; i < _states.length; i++) {
      if (_states[i].every((s) => s.holdsFor(value))) {
        chosen = i;
        _last = i;
      }
    }
    return chosen;
  }

  /// Acknowledges the feedback selected last (by any earlier value).
  void acknowledge() {
    final i = _last;
    if (i == null) return;
    for (final s in _states[i]) {
      s.acknowledge();
    }
  }

  /// Every constraint of feedback [index] acknowledged (true for one without constraints).
  bool isAcknowledged(int index) => _states[index].every((s) => s.acknowledged);
}
