// A synthetic definition of our own for demos and screenshots: plausible names, units, ranges, a VE map, an
// ignition map, an AFR target and two curves. It describes no real ECU and holds no vendor content.
// usage: node tool/demo_definition.mjs > demo.medef
const el = (n, v) => `<${n}>${v}</${n}>`;
const floats = (a) => a.map((v) => el('float', String(Math.round(v * 1000) / 1000))).join('');
const links = [
  [1, 'Engine speed', 'RPM', 0, 7500],
  [2, 'Manifold pressure', 'kPa', 20, 220],
  [3, 'Throttle position', '%', 0, 100],
  [4, 'Coolant temperature', '°C', -20, 110],
  [5, 'Intake air temperature', '°C', -10, 60],
  [6, 'Lambda', 'λ', 0.7, 1.3],
  [7, 'Battery voltage', 'V', 11, 14.8],
  [8, 'Ignition advance', '°', -5, 45],
  [9, 'Injector duty', '%', 0, 90],
  [10, 'Boost target', 'kPa', 100, 200],
  [11, 'Oil pressure', 'kPa', 0, 600],
  [12, 'Fuel pressure', 'kPa', 250, 400],
];
const rpm = Array.from({ length: 16 }, (_, i) => 500 + i * 450);
const map = Array.from({ length: 16 }, (_, i) => 20 + i * 13);
const clt = Array.from({ length: 16 }, (_, i) => -20 + i * 8);
const iat = Array.from({ length: 16 }, (_, i) => -10 + i * 5);
const grid = (f) => map.flatMap((m, r) => rpm.map((n, c) => f(n, m, r, c)));
const ve = grid((n, m) => 35 + 55 * Math.sin(Math.PI * Math.min(1, n / 7500) * 0.9) * (0.55 + 0.45 * m / 215));
const ign = grid((n, m) => Math.max(2, 10 + 28 * Math.min(1, n / 4500) - 22 * Math.max(0, (m - 100) / 115)));
const afr = grid((n, m) => 14.7 * (m > 100 ? 0.78 + 0.12 * (215 - m) / 115 : 1.0));
const table = (id, name, category, cols, rows, in0, in1, out, x, y, z, inc) =>
  el('TableModel', el('id', String(id)) + el('name', name) + el('category', category) + el('ViewInTree', 'true') + el('enabled', 'true') +
    el("type", `T${rows}x${cols}`) + el('cols', String(cols)) + el('rows', String(rows)) +
    el('input_0_LinkId', String(in0)) + el('input_1_LinkId', String(in1)) + el('output_LinkId', String(out)) +
    el('incVal', String(inc)) + el('input_0', floats(x)) + el('input_1', floats(y)) + el('output', floats(z)));
const param = (name, section, value, { options, units, tip, constraint } = {}) =>
  el('DriverModelParam', el('name', name) + el('SectionName', section) + el('type', options ? 'ComboBox' : 'InputBox') +
    el('value', String(value)) + (tip ? el('ToolTipText', tip) : '') +
    (constraint ? el('ViewConstraint', el('ParamIndex', String(constraint[0])) + el('AcceptedValues', el('float', String(constraint[1])))) : '') +
    (options ? el('options', options.map((o, i) => el('comboBoxOption', el('id', String(i)) + el('name', o))).join('')) : '') +
    (units ? el('MeasurementUnitTypes', units.map((u) => `<${u} />`).join('')) : ''));
const driver = (id, name, params, inputs = [], inputNames = [], priv = null) =>
  el('DriverModel', el('id', String(id)) + el('name', name) + el('numberOfConfigs', String(params.length)) + el('configParams', params.join('')) +
    (priv ? el('privSize', String(priv.length)) + el('privData', priv.toString('base64')) : '') +
    el('numberOfOutputs', '0') + el('outputLinkIds', '') + el('numberOfInputs', String(inputs.length)) + el('editableInputs', 'true') +
    el('inputNames', inputNames.map((n) => el('string', n)).join('')) + el('inputLinkIds', inputs.map((i) => el('unsignedShort', String(i))).join('')));
const drivers =
  driver(8192, 'Fuel', [
    param('Fueling Mode', 'Injection', 2, { options: ['Batch', 'Paired', 'Fully Seq'], tip: 'How the injectors are timed.' }),
    param('Injector Size', 'Injection', 550, { tip: 'Flow at the reference pressure, cc/min.' }),
    param('Use IAT in Algorithm', 'Air temperature', 1, { options: ['No', 'Yes'] }),
    param('Default IAT', 'Air temperature', 25, { units: ['Celsius', 'Fahrenheit'], constraint: [2, 0], tip: 'Used when the sensor is not.' }),
  ], [2, 5], ['Load sensor', 'Air temperature sensor']) +
  driver(8223, 'Ignition', [
    param('Mode', 'Outputs', 3, { options: ['Distributor', 'Wasted Spark', 'Wasted Spark - COPS', 'Fully Sequential'] }),
    param('Dwell', 'Coils', 3.2, { tip: 'Coil charge time, ms.' }),
  ]) +
  driver(8222, 'Engine trigger', [
    param('Trigger Pattern', 'Crank', 0, { options: ['36-1', 'Nissan SR', '60-2'] }),
    param('Teeth', 'Crank', 36),
    param('Cam A Pattern', 'Cam', 2, { options: ['None', 'Nissan SR', 'Single'] }),
    param('Cam Sync After RPM', 'Cam', 0),
  ]) +
  // Custom CAN: the configuration lives in the driver's private data, an empty layout-2 blob to start with.
  driver(8253, 'Custom CAN', [param('ConfigCRC', 'Custom CAN', 0)], [], [],
    Buffer.from([2, 12, 12, 0, ...new Array(3776).fill(0)]));
const xml = '<ecu>' +
  el('DeviceDataInformationModel', el('ProductName', 'DEMO') + el('ModelName', 'BENCH') + el('Version', '1')) +
  `<links>${links.map(([id, name, unit, lo, hi]) => el('DataLinkModel', el('id', String(id)) + el('name', name) + el('measureUnit', unit) +
    el('category', id <= 6 ? 'Engine' : 'Sensors') + el('ViewInTree', 'true') + el('StandardLogging', id <= 6 ? 'true' : 'false') +
    el('MinValue', String(lo)) + el('MaxValue', String(hi)))).join('')}` +
  // The onboard logger's state and entry count, which the simulator reports.
  [[1015, 'Data log status'], [1018, 'Data log entries']].map(([id, name]) => el('DataLinkModel', el('id', String(id)) +
    el('name', name) + el('category', 'Logging') + el('ViewInTree', 'false') + el('MinValue', '0') + el('MaxValue', '100000'))).join('') +
  `</links>` +
  '<tables>' +
  table(4096, 'Fuel VE', 'Fuel', 16, 16, 1, 2, 9, rpm, map, ve, 0.1) +
  table(4097, 'Ignition advance', 'Ignition', 16, 16, 1, 2, 8, rpm, map, ign, 0.5) +
  table(4098, 'Target AFR', 'Fuel', 16, 16, 1, 2, 6, rpm, map, afr, 0.1) +
  table(4099, 'Cranking fuel', 'Fuel', 16, 1, 4, 0, 9, clt, [0], clt.map((t) => 400 - 3 * t), 1) +
  table(4100, 'Intake temperature trim', 'Ignition', 16, 1, 5, 0, 8, iat, [0], iat.map((t) => (t > 30 ? -(t - 30) / 5 : 0)), 0.5) +
  `</tables><drivers>${drivers}</drivers></ecu>`;
process.stdout.write(xml);
