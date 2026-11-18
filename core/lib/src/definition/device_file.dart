/// Reads a definition (.medef) or calibration (.mecal) file. Both are the same XML document: a calibration is a
/// definition with values and notes.
library;

import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../calibration/calibration.dart';
import 'definition.dart';
import 'xml_convert.dart';

/// A file that isn't a usable definition or calibration.
class DeviceFileError implements Exception {
  const DeviceFileError(this.message);
  final String message;
  @override
  String toString() => 'DeviceFileError: $message';
}

/// The structure of the file and the values it holds.
typedef DeviceFile = ({Definition definition, Calibration calibration});

const _units = ['Raw', 'Volt', 'Ohm', 'KPa', 'PSI', 'Celsius', 'Fahrenheit'];
const _constraints = ['Eq', 'Gt', 'GtEq', 'GtInc', 'Lt', 'LtEq'];
const _feedbacks = ['Default', 'Ok', 'Warning', 'Alarm'];
const _validationKinds = ['AllowMultipleDuplicates', 'AllowIndex', 'AllowValue', 'DenyValue', 'DenyIndex'];

final _tableType = XmlConvert.enumOf(TableType.names, 'TableType');
final _tableFunction = XmlConvert.enumOf(['Normal', 'PercentTrim'], 'TableFunction');
final _paramType = XmlConvert.enumOf(['InputBox', 'ComboBox'], 'ParamType');
final _dataType = XmlConvert.enumOf(['Normal', 'TrimModPercent', 'Percent', 'ADCRaw'], 'DataType');

DeviceFile readDeviceFile(String xml) {
  final XmlElement root;
  try {
    root = XmlDocument.parse(normaliseXmlSource(xml.startsWith('\uFEFF') ? xml.substring(1) : xml)).rootElement;
  } on XmlException catch (e) {
    throw DeviceFileError('not well-formed XML: ${e.message}');
  }

  var info = const DeviceInfo();
  for (final e in childElements(root, 'DeviceDataInformationModel')) {
    info = _info(e);
  }
  String? notes;
  for (final e in childElements(root, 'CalibrationNotes')) {
    readMembers(e, {'Text': (c) => notes = directText(c)});
  }

  Iterable<XmlElement> section(String name, String item) {
    final s = firstChild(root, name);
    if (s == null) throw DeviceFileError('no <$name> section');
    return childElements(s, item);
  }

  final links = <int, LinkDef>{};
  for (final e in section('links', 'DataLinkModel')) {
    final l = _link(e);
    if (links.containsKey(l.id)) throw DeviceFileError('link ${l.id} appears twice');
    links[l.id] = l;
  }

  final tables = <int, TableDef>{};
  final tableValues = <int, TableValues>{};
  for (final e in section('tables', 'TableModel')) {
    final (t, v) = _table(e);
    // A table whose inputs or output don't exist, or a repeated id, is left out (as the original did).
    bool has(int id) => id != 0 && links.containsKey(id);
    final linked = has(t.input0LinkId) && has(t.outputLinkId) && (!t.isMap || has(t.input1LinkId));
    if (!linked || tables.containsKey(t.id)) continue;
    tables[t.id] = t;
    tableValues[t.id] = v;
  }

  final drivers = <int, DriverDef>{};
  final driverValues = <int, DriverValues>{};
  for (final e in section('drivers', 'DriverModel')) {
    final (d, v) = _driver(e);
    if (drivers.containsKey(d.id)) throw DeviceFileError('driver ${d.id} appears twice');
    drivers[d.id] = d;
    driverValues[d.id] = v;
  }

  final definition = Definition(info: info, links: links, tables: tables, drivers: drivers);
  return (
    definition: definition,
    calibration: Calibration(definition, tables: tableValues, drivers: driverValues, notes: notes),
  );
}

DeviceInfo _info(XmlElement e) {
  String? product, model, version, fw;
  readMembers(e, {
    'ProductName': (c) => product = directText(c),
    'ModelName': (c) => model = directText(c),
    'Version': (c) => version = directText(c),
    'FWVersion': (c) => fw = directText(c),
  });
  return DeviceInfo(productName: product, modelName: model, version: version, fwVersion: fw);
}

/// Members every item has.
class _Base {
  var id = 0;
  String? name, category;
  var viewInTree = false, boardSpecific = false, defaultLocked = false;

  Map<String, void Function(XmlElement)> get members => {
    'DefaultLocked': (c) => defaultLocked = XmlConvert.toBool(directText(c)),
    'id': (c) => id = XmlConvert.toU16(directText(c)),
    'name': (c) => name = directText(c),
    'ViewInTree': (c) => viewInTree = XmlConvert.toBool(directText(c)),
    'BoardSpecific': (c) => boardSpecific = XmlConvert.toBool(directText(c)),
    'category': (c) => category = directText(c),
  };
}

List<String> _unitList(XmlElement w) => readArray(w, {for (final u in _units) u: (_) => u});

Constraint _constraint(int kind, XmlElement x) {
  final v = x.getAttribute('Value');
  if (kind == 0) {
    final parts = v == null ? const <String>[] : v.split(RegExp(r'[ \t\n\r]+')).where((s) => s.isNotEmpty);
    return Constraint(ConstraintKind.eq, [for (final p in parts) XmlConvert.toF32(p)]);
  }
  return Constraint(ConstraintKind.values[kind], [v == null ? 0 : XmlConvert.toF32(v)]);
}

Feedback _feedback(int kind, XmlElement x) {
  final flashing = x.getAttribute('Flashing');
  List<Constraint>? constraints;
  readMembers(x, {
    'Constraints':
        (c) =>
            constraints = readArray(c, {
              for (var i = 0; i < _constraints.length; i++) _constraints[i]: (y) => _constraint(i, y),
            }),
  });
  return Feedback(
    FeedbackKind.values[kind],
    flashing: flashing == null ? false : XmlConvert.toBool(flashing),
    constraints: constraints,
  );
}

LinkDef _link(XmlElement e) {
  final b = _Base();
  String? dataKey, measureUnit;
  List<Feedback>? feedbacks;
  var units = const <String>[];
  var standardLogging = false;
  Map<double, String?>? textValues;
  var dataType = 0;
  double min = 0, max = 0;
  readMembers(e, {
    ...b.members,
    'DataKey': (c) => dataKey = directText(c),
    'Feedbacks':
        (c) =>
            feedbacks = readArray(c, {
              for (var i = 0; i < _feedbacks.length; i++) _feedbacks[i]: (y) => _feedback(i, y),
            }),
    'MeasurementUnitTypes': (c) => units = _unitList(c),
    'measureUnit': (c) => measureUnit = directText(c),
    'StandardLogging': (c) => standardLogging = XmlConvert.toBool(directText(c)),
    'TextValues': (c) {
      final map = textValues = {};
      for (final (value, text) in readArray(c, {'TextValueModel': _textValue})) {
        if (map.containsKey(value)) throw DeviceFileError('link ${b.id}: text value $value appears twice');
        map[value] = text;
      }
    },
    'DataTypeSet': (c) => dataType = _dataType(directText(c)),
    'MinValue': (c) => min = XmlConvert.toF32(directText(c)),
    'MaxValue': (c) => max = XmlConvert.toF32(directText(c)),
  });
  return LinkDef(
    id: b.id,
    name: b.name,
    category: b.category,
    viewInTree: b.viewInTree,
    boardSpecific: b.boardSpecific,
    defaultLocked: b.defaultLocked,
    dataKey: dataKey,
    feedbacks: feedbacks,
    measurementUnits: units,
    measureUnit: measureUnit,
    standardLogging: standardLogging,
    textValues: textValues,
    dataType: LinkDataType.values[dataType],
    minValue: min,
    maxValue: max,
  );
}

(double, String?) _textValue(XmlElement x) {
  double value = 0;
  String? text;
  readMembers(x, {'value': (y) => value = XmlConvert.toF32(directText(y)), 'text': (y) => text = directText(y)});
  return (value, text);
}

/// Values copied into an array of the definition's size; extra values are dropped, missing ones are zero.
Float32List _sized(List<double>? v, int n) {
  final out = Float32List(n);
  if (v != null) assignFloats(out, v);
  return out;
}

(TableDef, TableValues) _table(XmlElement e) {
  final b = _Base();
  var enabled = false;
  var type = 0, function = 0, cols = 0, rows = 0, in0 = 0, in1 = 0, out = 0;
  String? in0Name, in1Name, outName, dataKey;
  List<double>? x, y, z;
  var increment = 0.10000000149011612;
  double defaultValue = 0;
  readMembers(e, {
    ...b.members,
    'enabled': (c) => enabled = XmlConvert.toBool(directText(c)),
    'type': (c) => type = _tableType(directText(c)),
    'function': (c) => function = _tableFunction(directText(c)),
    'cols': (c) => cols = XmlConvert.toU16(directText(c)),
    'rows': (c) => rows = XmlConvert.toU16(directText(c)),
    'input_0_LinkId': (c) => in0 = XmlConvert.toU16(directText(c)),
    'input_1_LinkId': (c) => in1 = XmlConvert.toU16(directText(c)),
    'output_LinkId': (c) => out = XmlConvert.toU16(directText(c)),
    'input_0_name': (c) => in0Name = directText(c),
    'input_1_name': (c) => in1Name = directText(c),
    'output_name': (c) => outName = directText(c),
    'input_0': (c) => x = readFloats(c),
    'input_1': (c) => y = readFloats(c),
    'output': (c) => z = readFloats(c),
    'incVal': (c) => increment = XmlConvert.toF32(directText(c)),
    'defaultValue': (c) => defaultValue = XmlConvert.toF32(directText(c)),
    'DataKey': (c) => dataKey = directText(c),
  });
  final def = TableDef(
    id: b.id,
    name: b.name,
    category: b.category,
    viewInTree: b.viewInTree,
    boardSpecific: b.boardSpecific,
    defaultLocked: b.defaultLocked,
    type: type,
    function: TableFunction.values[function],
    cols: cols,
    rows: rows,
    input0LinkId: in0,
    input1LinkId: in1,
    outputLinkId: out,
    input0Name: in0Name,
    input1Name: in1Name,
    outputName: outName,
    increment: increment,
    defaultValue: defaultValue,
    dataKey: dataKey,
  );
  return (def, TableValues(enabled: enabled, x: _sized(x, cols), y: _sized(y, rows), z: _sized(z, cols * rows)));
}

Validation _validation(XmlElement e) {
  var check = false;
  List<(String?, double)>? defaults;
  var exceptions = const <ValidationException>[];
  double attrValue(XmlElement d) => d.getAttribute('Value') == null ? 0 : XmlConvert.toF32(d.getAttribute('Value')!);
  readMembers(e, {
    'CheckDuplicates': (c) => check = XmlConvert.toBool(directText(c)),
    'DefaultValues': (c) => defaults = readArray(c, {'DefaultValue': (d) => (d.getAttribute('Group'), attrValue(d))}),
    'Exceptions':
        (c) =>
            exceptions = readArray(c, {
              for (var i = 0; i < _validationKinds.length; i++)
                _validationKinds[i]:
                    (d) =>
                        ValidationException(ValidationExceptionKind.values[i], d.getAttribute('Group'), attrValue(d)),
            }),
  });
  return Validation(checkDuplicates: check, defaultValues: defaults, exceptions: exceptions);
}

List<LinkConfig> _linkConfigs(XmlElement w) => readArray(w, {
  'LinkConfig': (x) {
    var index = 0, visible = false;
    readMembers(x, {
      'Index': (c) => index = XmlConvert.toI32(directText(c)),
      'Visible': (c) => visible = XmlConvert.toBool(directText(c)),
    });
    return LinkConfig(index, visible);
  },
});

ParamDef _param(XmlElement e) {
  String? name, displayName, section, group, tip;
  var type = 0;
  var readOnly = false, hidden = false, reset = false, checkRange = false;
  double value = 0, min = 0, max = 0;
  ViewConstraint? vc;
  List<ComboOption>? options;
  var units = const <String>[];
  readMembers(e, {
    'ValidationGroup': (c) => group = directText(c),
    'name': (c) => name = directText(c),
    'DisplayName': (c) => displayName = directText(c),
    'SectionName': (c) => section = directText(c),
    'type': (c) => type = _paramType(directText(c)),
    'readOnly': (c) => readOnly = XmlConvert.toBool(directText(c)),
    'Hidden': (c) => hidden = XmlConvert.toBool(directText(c)),
    'RequiresReset': (c) => reset = XmlConvert.toBool(directText(c)),
    'ToolTipText': (c) => tip = directText(c),
    'value': (c) => value = XmlConvert.toF32(directText(c)),
    'Min': (c) => min = XmlConvert.toF32(directText(c)),
    'Max': (c) => max = XmlConvert.toF32(directText(c)),
    'CheckRange': (c) => checkRange = XmlConvert.toBool(directText(c)),
    'ViewConstraint': (c) {
      var index = 0;
      List<double>? accepted;
      readMembers(c, {
        'ParamIndex': (x) => index = XmlConvert.toI32(directText(x)),
        'AcceptedValues': (x) => accepted = readFloats(x),
      });
      vc = ViewConstraint(index, accepted);
    },
    'options':
        (c) =>
            options = readArray(c, {
              'comboBoxOption': (x) {
                var id = 0;
                String? optName;
                readMembers(x, {
                  'id': (y) => id = XmlConvert.toU16(directText(y)),
                  'name': (y) => optName = directText(y),
                });
                return ComboOption(id, optName);
              },
            }),
    'MeasurementUnitTypes': (c) => units = _unitList(c),
  });
  return ParamDef(
    name: name,
    displayName: displayName,
    sectionName: section,
    validationGroup: group,
    type: ParamType.values[type],
    readOnly: readOnly,
    hidden: hidden,
    requiresReset: reset,
    toolTipText: tip,
    value: value,
    min: min,
    max: max,
    checkRange: checkRange,
    viewConstraint: vc,
    options: options,
    measurementUnits: units,
  );
}

(DriverDef, DriverValues) _driver(XmlElement e) {
  final b = _Base();
  var params = const <ParamDef>[];
  var configs = 0, outputs = 0, inputs = 0, privSize = 0;
  Uint8List? priv;
  List<int>? outIds, inIds;
  List<String>? outNames, inNames;
  var editOut = false, editIn = false;
  Validation? cv, ov, iv;
  List<LinkConfig>? inCfg, outCfg;
  readMembers(e, {
    ...b.members,
    'ConfigValidation': (c) => cv = _validation(c),
    'numberOfConfigs': (c) => configs = XmlConvert.toI32(directText(c)),
    'configParams': (c) => params = readArray(c, {'DriverModelParam': _param}),
    'privSize': (c) => privSize = XmlConvert.toI32(directText(c)),
    'privData': (c) => priv = XmlConvert.toBase64(directText(c)),
    'OutputValidation': (c) => ov = _validation(c),
    'numberOfOutputs': (c) => outputs = XmlConvert.toI32(directText(c)),
    'outputLinkIds': (c) => outIds = readUShorts(c),
    'editableOutputs': (c) => editOut = XmlConvert.toBool(directText(c)),
    'outputNames': (c) => outNames = readStrings(c),
    'InputValidation': (c) => iv = _validation(c),
    'editableInputs': (c) => editIn = XmlConvert.toBool(directText(c)),
    'inputNames': (c) => inNames = readStrings(c),
    'numberOfInputs': (c) => inputs = XmlConvert.toI32(directText(c)),
    'inputLinkIds': (c) => inIds = readUShorts(c),
    'InputLinksConfigs': (c) => inCfg = _linkConfigs(c),
    'OutputLinkConfigs': (c) => outCfg = _linkConfigs(c),
  });
  if (configs < 0 || outputs < 0 || inputs < 0 || privSize < 0) throw DeviceFileError('driver ${b.id}: negative count');
  final def = DriverDef(
    id: b.id,
    name: b.name,
    category: b.category,
    viewInTree: b.viewInTree,
    boardSpecific: b.boardSpecific,
    defaultLocked: b.defaultLocked,
    params: params,
    configCount: configs,
    outputCount: outputs,
    inputCount: inputs,
    outputNames: outNames,
    inputNames: inNames,
    editableOutputs: editOut,
    editableInputs: editIn,
    configValidation: cv,
    outputValidation: ov,
    inputValidation: iv,
    inputConfigs: inCfg,
    outputConfigs: outCfg,
    privSize: privSize,
  );
  final privData = Uint8List(privSize);
  if (priv != null) privData.setRange(0, privSize < priv!.length ? privSize : priv!.length, priv!);
  final values = DriverValues(
    config: _sized([for (final p in params) p.value], configs),
    outputs: Uint16List.fromList([for (var i = 0; i < outputs; i++) i < (outIds?.length ?? 0) ? outIds![i] : 0]),
    inputs: Uint16List.fromList([for (var i = 0; i < inputs; i++) i < (inIds?.length ?? 0) ? inIds![i] : 0]),
    priv: privData,
  );
  return (def, values);
}
