/// What an ECU firmware exposes: live-data links, tables and drivers (settings pages). Immutable; loaded from a
/// definition file the user supplies. Values live in a `Calibration`.
library;

/// Product, model and definition version, from a file or from the ECU itself.
final class DeviceInfo {
  const DeviceInfo({this.productName, this.modelName, this.version, this.fwVersion});
  final String? productName;
  final String? modelName;

  /// Definition version; the ECU reports the one its firmware expects.
  final String? version;
  final String? fwVersion;

  static const genericModel = 'GENERIC';

  bool get isGeneric => _eq(modelName, genericModel);

  /// Whether this definition describes [ecu]: same product and version, and the same model unless this one is the
  /// generic model.
  bool describes(DeviceInfo ecu) =>
      _eq(productName, ecu.productName) && _eq(version, ecu.version) && (isGeneric || _eq(modelName, ecu.modelName));

  /// Same product, version and model as [other]: the same kind of ECU, so a calibration read from one fits the other.
  bool sameDevice(DeviceInfo other) =>
      _eq(productName, other.productName) && _eq(version, other.version) && _eq(modelName, other.modelName);

  static bool _eq(String? a, String? b) => a != null && b != null && a.toUpperCase() == b.toUpperCase();

  @override
  String toString() => '$productName $modelName v$version';
}

/// How a live value should be shown.
enum LinkDataType { normal, trimModPercent, percent, adcRaw }

enum FeedbackKind { normal, ok, warning, alarm }

enum ConstraintKind { eq, gt, gtEq, gtInc, lt, ltEq }

/// A threshold test on a live value.
final class Constraint {
  const Constraint(this.kind, this.values);
  final ConstraintKind kind;

  /// One value, except [ConstraintKind.eq], which matches any of several.
  final List<double> values;
}

/// A colour state for a live value and the tests that select it.
final class Feedback {
  const Feedback(this.kind, {this.flashing = false, this.constraints});
  final FeedbackKind kind;
  final bool flashing;
  final List<Constraint>? constraints;
}

/// Shared by links, tables and drivers.
abstract base class Item {
  const Item({
    required this.id,
    this.name,
    this.category,
    this.viewInTree = false,
    this.boardSpecific = false,
    this.defaultLocked = false,
  });
  final int id;
  final String? name;

  /// The definition's own grouping. The app's catalogue decides where an item is shown.
  final String? category;
  final bool viewInTree;
  final bool boardSpecific;
  final bool defaultLocked;
}

/// A live value the ECU can report.
final class LinkDef extends Item {
  const LinkDef({
    required super.id,
    super.name,
    super.category,
    super.viewInTree,
    super.boardSpecific,
    super.defaultLocked,
    this.dataKey,
    this.feedbacks,
    this.measurementUnits = const [],
    this.measureUnit,
    this.standardLogging = false,
    this.textValues,
    this.dataType = LinkDataType.normal,
    this.minValue = 0,
    this.maxValue = 0,
  });
  final String? dataKey;
  final List<Feedback>? feedbacks;

  /// Unit families the value can be converted between (Celsius/Fahrenheit, KPa/PSI…).
  final List<String> measurementUnits;
  final String? measureUnit;
  final bool standardLogging;

  /// Enumerated values shown as text; null when the file has no list (an empty list is kept as such).
  final Map<double, String?>? textValues;
  final LinkDataType dataType;
  final double minValue;
  final double maxValue;

  /// The definition gives a display range.
  bool get hasRange => minValue != maxValue;
}

/// Table shapes. A table's actual size is in its rows and columns; the shape is part of the wire format.
abstract final class TableType {
  static const names = ['T1x16', 'T1x32', 'T16x16', 'T32x32', 'T1x2', 'T8x8'];
}

enum TableFunction { normal, percentTrim }

/// A curve (one row) or map (several rows) over one or two live inputs.
final class TableDef extends Item {
  const TableDef({
    required super.id,
    super.name,
    super.category,
    super.viewInTree,
    super.boardSpecific,
    super.defaultLocked,
    this.type = 0,
    this.function = TableFunction.normal,
    required this.cols,
    required this.rows,
    this.input0LinkId = 0,
    this.input1LinkId = 0,
    this.outputLinkId = 0,
    this.input0Name,
    this.input1Name,
    this.outputName,
    this.increment = 0.10000000149011612,
    this.defaultValue = 0,
    this.dataKey,
  });

  /// Index into [TableType.names].
  final int type;
  final TableFunction function;
  final int cols;
  final int rows;

  /// Column axis input (x), row axis input (y, maps only) and the output it drives.
  final int input0LinkId, input1LinkId, outputLinkId;
  final String? input0Name, input1Name, outputName;

  /// Nudge step for editing.
  final double increment;
  final double defaultValue;
  final String? dataKey;

  bool get isMap => rows > 1;
  int get cells => rows * cols;
}

enum ParamType { inputBox, comboBox }

final class ComboOption {
  const ComboOption(this.id, this.name);
  final int id;
  final String? name;
}

/// A parameter shown only while another parameter of the same driver has one of [acceptedValues].
final class ViewConstraint {
  const ViewConstraint(this.paramIndex, this.acceptedValues);
  final int paramIndex;
  final List<double>? acceptedValues;
}

enum ValidationExceptionKind { allowMultipleDuplicates, allowIndex, allowValue, denyValue, denyIndex }

final class ValidationException {
  const ValidationException(this.kind, this.group, this.value);
  final ValidationExceptionKind kind;
  final String? group;
  final double value;
}

/// Rules for a group of values that must not repeat (output pins, input channels).
final class Validation {
  const Validation({this.checkDuplicates = false, this.defaultValues, this.exceptions = const []});
  final bool checkDuplicates;
  final List<(String?, double)>? defaultValues;
  final List<ValidationException> exceptions;
}

/// One setting on a settings page.
final class ParamDef {
  const ParamDef({
    this.name,
    this.displayName,
    this.sectionName,
    this.validationGroup,
    this.type = ParamType.inputBox,
    this.readOnly = false,
    this.hidden = false,
    this.requiresReset = false,
    this.toolTipText,
    this.value = 0,
    this.min = 0,
    this.max = 0,
    this.checkRange = false,
    this.viewConstraint,
    this.options,
    this.measurementUnits = const [],
  });
  final String? name, displayName, sectionName, validationGroup;
  final ParamType type;
  final bool readOnly, hidden;

  /// The ECU must restart before the change takes effect.
  final bool requiresReset;
  final String? toolTipText;

  /// Default value in the definition; the current value is in the calibration.
  final double value;
  final double min, max;

  /// Whether the definition's own [min]/[max] apply.
  final bool checkRange;
  final ViewConstraint? viewConstraint;
  final List<ComboOption>? options;
  final List<String> measurementUnits;
}

final class LinkConfig {
  const LinkConfig(this.index, this.visible);
  final int index;
  final bool visible;
}

/// A settings page: configuration values, output and input link ids, and an opaque private block.
final class DriverDef extends Item {
  const DriverDef({
    required super.id,
    super.name,
    super.category,
    super.viewInTree,
    super.boardSpecific,
    super.defaultLocked,
    this.params = const [],
    this.configCount = 0,
    this.outputCount = 0,
    this.inputCount = 0,
    this.outputNames,
    this.inputNames,
    this.editableOutputs = false,
    this.editableInputs = false,
    this.configValidation,
    this.outputValidation,
    this.inputValidation,
    this.inputConfigs,
    this.outputConfigs,
    this.privSize = 0,
  });

  /// Parameter descriptions; [configCount] values go on the wire.
  final List<ParamDef> params;
  final int configCount, outputCount, inputCount;
  final List<String>? outputNames, inputNames;
  final bool editableOutputs, editableInputs;
  final Validation? configValidation, outputValidation, inputValidation;
  final List<LinkConfig>? inputConfigs, outputConfigs;

  /// Bytes of private data appended to the wire form; 0 when the driver has none.
  final int privSize;

  ParamDef? param(int i) => i >= 0 && i < params.length ? params[i] : null;
}

/// A loaded definition. Maps keep file order, which the overall calibration hash depends on.
final class Definition {
  const Definition({required this.info, required this.links, required this.tables, required this.drivers});
  final DeviceInfo info;
  final Map<int, LinkDef> links;
  final Map<int, TableDef> tables;
  final Map<int, DriverDef> drivers;

  LinkDef? link(int id) => id == 0 ? null : links[id];
}
