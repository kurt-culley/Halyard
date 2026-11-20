import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:halyard_core/halyard_core.dart';

/// The user's units, shared by every feature as a `ValueNotifier<UnitPreferences>` and kept in app storage.
abstract final class Preferences {
  static const _file = 'preferences.json';

  static Future<ValueNotifier<UnitPreferences>> load(AppStorage storage) async {
    var units = defaultUnitPreferences;
    try {
      final raw = await storage.read(_file);
      if (raw != null) {
        final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
        MeasurementUnit pick(String key, MeasurementUnit fallback) =>
            MeasurementUnit.fromKey(j[key] as String? ?? '') ?? fallback;
        units = (
          analog: pick('analog', units.analog),
          analogTemperature: pick('analogTemperature', units.analogTemperature),
          pressure: pick('pressure', units.pressure),
          temperature: pick('temperature', units.temperature),
        );
      }
    } on Object {
      // Unreadable preferences fall back to the defaults.
    }
    final notifier = ValueNotifier(units);
    notifier.addListener(() {
      final u = notifier.value;
      storage
          .write(
            _file,
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'analog': u.analog.key,
                  'analogTemperature': u.analogTemperature.key,
                  'pressure': u.pressure.key,
                  'temperature': u.temperature.key,
                }),
              ),
            ),
          )
          .ignore();
    });
    return notifier;
  }
}
