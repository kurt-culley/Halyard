import 'package:material_ui/material_ui.dart';

/// The table heat ramp: four bands from low to high, as the original shaded its tables.
const _heat = [
  Color.fromARGB(255, 13, 66, 88),
  Color.fromARGB(255, 0, 132, 156),
  Color.fromARGB(255, 0, 164, 127),
  Color.fromARGB(255, 229, 164, 45),
  Color.fromARGB(255, 211, 64, 72),
];

/// The colour for [t], 0 to 1 across a table's range.
Color heatColor(double t) {
  final k = t.isNaN ? 0.5 : t.clamp(0.0, 1.0);
  final band = (k * 4).floor().clamp(0, 3);
  return Color.lerp(_heat[band], _heat[band + 1], k * 4 - band)!;
}

/// Dark text on light cells, light text on dark ones.
Color textOn(Color c) => (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.52
    ? const Color.fromARGB(255, 16, 19, 23)
    : const Color.fromARGB(255, 236, 239, 243);
