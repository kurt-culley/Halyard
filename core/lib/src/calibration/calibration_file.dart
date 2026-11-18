/// Writes a calibration file (.mecal) byte for byte as the original tool did: its serializer's member order and value
/// syntax, saved as indented XML with CRLF line ends. The caller writes the text as UTF-8 without a byte-order mark.
library;

import 'dart:convert';

import '../definition/definition.dart';
import '../definition/xml_convert.dart';
import 'calibration.dart';

const calibrationFileExtension = 'mecal';

/// The whole file: version information, notes, then links, drivers and tables in definition order.
String writeCalibrationFile(Calibration c) {
  final d = c.definition;
  final root = _El('ecu', [
    _info(d.info),
    _El('CalibrationNotes', _keep([_text('Text', c.notes)])),
    _El('links', [for (final l in d.links.values) _link(l)]),
    _El('drivers', [for (final v in d.drivers.values) _driver(v, c.drivers[v.id]!)]),
    _El('tables', [for (final t in d.tables.values) _table(t, c.tables[t.id]!)]),
  ]);
  final out = ['<?xml version="1.0" encoding="utf-8"?>'];
  _render(root, '', out);
  return out.join('\r\n');
}

/// The name the original gave a calibration saved without a file of its own:
/// `product_model_version_yyyy_MM_dd_HH_mm.mecal`, in local time.
String backupCalibrationFileName(DeviceInfo info, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp = '${now.year}_${two(now.month)}_${two(now.day)}_${two(now.hour)}_${two(now.minute)}';
  return '${info.productName}_${info.modelName}_${info.version}_$stamp.$calibrationFileExtension';
}

// ---------------------------------------------------------------- element tree and its text form

final class _El {
  _El(this.name, [this.children = const [], this.attrs = const []]);
  final String name;

  /// [_El] or [String].
  final List<Object> children;
  final List<(String, String)> attrs;
}

String _escText(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll(RegExp('\r\n|\r|\n'), '\r\n');

String _escAttr(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll('\t', '&#x9;')
    .replaceAll('\n', '&#xA;')
    .replaceAll('\r', '&#xD;');

void _render(_El n, String indent, List<String> out) {
  final open = '<${n.name}${n.attrs.map((a) => ' ${a.$1}="${_escAttr(a.$2)}"').join()}';
  if (n.children.isEmpty) {
    out.add('$indent$open />');
  } else if (n.children.every((c) => c is String)) {
    out.add('$indent$open>${_escText(n.children.join())}</${n.name}>');
  } else {
    out.add('$indent$open>');
    for (final c in n.children) {
      if (c is _El) {
        _render(c, '$indent  ', out);
      } else {
        out.add('$indent  ${_escText(c as String)}');
      }
    }
    out.add('$indent</${n.name}>');
  }
}

// ---------------------------------------------------------------- serializer conventions

List<_El> _keep(List<_El?> xs) => [
  for (final x in xs)
    if (x != null) x,
];
_El _val(String name, String v) => _El(name, [v]);
_El _bool(String name, bool v) => _val(name, v ? 'true' : 'false');
_El _int(String name, int v) => _val(name, '$v');
_El _float(String name, double v) => _val(name, XmlConvert.fromF32(v));

/// A string member: left out when null, an empty element when empty.
_El? _text(String name, String? s) => s == null ? null : _El(name, s.isEmpty ? const [] : [s]);

/// An array member: left out when null.
_El? _list<T>(String name, Iterable<T>? xs, _El Function(T) item) =>
    xs == null ? null : _El(name, [for (final x in xs) item(x)]);

_El? _floats(String name, Iterable<double>? xs) => _list(name, xs, (v) => _float('float', v));

/// A null array item.
final _nil = _El('DriverModelParam', const [], const [
  ('xsi:nil', 'true'),
  ('xmlns:xsi', 'http://www.w3.org/2001/XMLSchema-instance'),
]);

_El _units(List<String> units) => _El('MeasurementUnitTypes', [for (final u in units) _El(u)]);

List<_El?> _base(Item o) => [
  _bool('DefaultLocked', o.defaultLocked),
  _int('id', o.id),
  _text('name', o.name),
  _bool('ViewInTree', o.viewInTree),
  _bool('BoardSpecific', o.boardSpecific),
  _text('category', o.category),
];

_El _info(DeviceInfo i) => _El(
  'DeviceDataInformationModel',
  _keep([
    _text('ProductName', i.productName),
    _text('ModelName', i.modelName),
    _text('Version', i.version),
    _text('FWVersion', i.fwVersion),
  ]),
);

// ---------------------------------------------------------------- items

const _feedbackNames = ['Default', 'Ok', 'Warning', 'Alarm'];
const _constraintNames = ['Eq', 'Gt', 'GtEq', 'GtInc', 'Lt', 'LtEq'];
const _dataTypeNames = ['Normal', 'TrimModPercent', 'Percent', 'ADCRaw'];

_El _link(LinkDef l) => _El(
  'DataLinkModel',
  _keep([
    ..._base(l),
    _text('DataKey', l.dataKey),
    _list(
      'Feedbacks',
      l.feedbacks,
      (f) => _El(
        _feedbackNames[f.kind.index],
        _keep([
          _list(
            'Constraints',
            f.constraints,
            (c) =>
                _El(_constraintNames[c.kind.index], const [], [('Value', c.values.map(XmlConvert.fromF32).join(' '))]),
          ),
        ]),
        [('Flashing', f.flashing ? 'true' : 'false')],
      ),
    ),
    _units(l.measurementUnits),
    _text('measureUnit', l.measureUnit),
    _bool('StandardLogging', l.standardLogging),
    _list(
      'TextValues',
      l.textValues?.entries,
      (e) => _El('TextValueModel', _keep([_float('value', e.key), _text('text', e.value)])),
    ),
    _val('DataTypeSet', _dataTypeNames[l.dataType.index]),
    _float('MinValue', l.minValue),
    _float('MaxValue', l.maxValue),
  ]),
);

_El _table(TableDef t, TableValues v) => _El(
  'TableModel',
  _keep([
    ..._base(t),
    _bool('enabled', v.enabled),
    _val('type', TableType.names[t.type]),
    _val('function', t.function == TableFunction.percentTrim ? 'PercentTrim' : 'Normal'),
    _int('cols', t.cols),
    _int('rows', t.rows),
    _int('input_0_LinkId', t.input0LinkId),
    _int('input_1_LinkId', t.input1LinkId),
    _int('output_LinkId', t.outputLinkId),
    _text('input_0_name', t.input0Name),
    _text('input_1_name', t.input1Name),
    _text('output_name', t.outputName),
    _floats('input_0', v.x),
    _floats('input_1', v.y),
    _floats('output', v.z),
    _float('incVal', t.increment),
    _float('defaultValue', t.defaultValue),
    _text('DataKey', t.dataKey),
  ]),
);

const _exceptionNames = ['AllowMultipleDuplicates', 'AllowIndex', 'AllowValue', 'DenyValue', 'DenyIndex'];

_El? _validation(String name, Validation? v) =>
    v == null
        ? null
        : _El(
          name,
          _keep([
            _bool('CheckDuplicates', v.checkDuplicates),
            _list(
              'DefaultValues',
              v.defaultValues,
              (d) => _El('DefaultValue', const [], [
                if (d.$1 case final g?) ('Group', g),
                ('Value', XmlConvert.fromF32(d.$2)),
              ]),
            ),
            // Written only when the definition had exceptions; the original also wrote an empty list.
            if (v.exceptions.isNotEmpty)
              _list(
                'Exceptions',
                v.exceptions,
                (x) => _El(_exceptionNames[x.kind.index], const [], [
                  if (x.group case final g?) ('Group', g),
                  ('Value', XmlConvert.fromF32(x.value)),
                ]),
              ),
          ]),
        );

_El? _linkConfigs(String name, List<LinkConfig>? l) =>
    _list(name, l, (c) => _El('LinkConfig', [_int('Index', c.index), _bool('Visible', c.visible)]));

_El _param(ParamDef p, double value) => _El(
  'DriverModelParam',
  _keep([
    _text('ValidationGroup', p.validationGroup),
    _text('name', p.name),
    _text('DisplayName', p.displayName),
    _text('SectionName', p.sectionName),
    _val('type', p.type == ParamType.comboBox ? 'ComboBox' : 'InputBox'),
    _bool('readOnly', p.readOnly),
    _bool('Hidden', p.hidden),
    _bool('RequiresReset', p.requiresReset),
    _text('ToolTipText', p.toolTipText),
    _float('value', value),
    _float('Min', p.min),
    _float('Max', p.max),
    _bool('CheckRange', p.checkRange),
    if (p.viewConstraint case final vc?)
      _El('ViewConstraint', _keep([_int('ParamIndex', vc.paramIndex), _floats('AcceptedValues', vc.acceptedValues)])),
    _list('options', p.options, (o) => _El('comboBoxOption', _keep([_int('id', o.id), _text('name', o.name)]))),
    _units(p.measurementUnits),
  ]),
);

_El _driver(DriverDef d, DriverValues v) => _El(
  'DriverModel',
  _keep([
    ..._base(d),
    _validation('ConfigValidation', d.configValidation),
    _int('numberOfConfigs', d.configCount),
    // One item per configuration value; a value without a parameter description is a null item.
    _El('configParams', [
      for (var i = 0; i < d.configCount; i++) i < d.params.length ? _param(d.params[i], v.config[i]) : _nil,
    ]),
    if (d.privSize > 0) _int('privSize', d.privSize),
    if (d.privSize > 0) _text('privData', base64.encode(v.priv)),
    _validation('OutputValidation', d.outputValidation),
    _int('numberOfOutputs', d.outputCount),
    _list('outputLinkIds', v.outputs, (id) => _int('unsignedShort', id)),
    _bool('editableOutputs', d.editableOutputs),
    _list('outputNames', d.outputNames, (s) => _text('string', s)!),
    _validation('InputValidation', d.inputValidation),
    _bool('editableInputs', d.editableInputs),
    _list('inputNames', d.inputNames, (s) => _text('string', s)!),
    _int('numberOfInputs', d.inputCount),
    _list('inputLinkIds', v.inputs, (id) => _int('unsignedShort', id)),
    _linkConfigs('InputLinksConfigs', d.inputConfigs),
    _linkConfigs('OutputLinkConfigs', d.outputConfigs),
  ]),
);
