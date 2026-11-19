// A synthetic definition of our own for demos and screenshots: plausible names, units, ranges, a VE map, an
// ignition map, a lambda target and two curves. It describes no real ECU and holds no vendor content.
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
const lam = grid((n, m) => (m > 100 ? 0.78 + 0.12 * (215 - m) / 115 : 1.0));
const table = (id, name, category, cols, rows, in0, in1, out, x, y, z, inc) =>
  el('TableModel', el('id', String(id)) + el('name', name) + el('category', category) + el('ViewInTree', 'true') +
    el("type", `T${rows}x${cols}`) + el('cols', String(cols)) + el('rows', String(rows)) +
    el('input_0_LinkId', String(in0)) + el('input_1_LinkId', String(in1)) + el('output_LinkId', String(out)) +
    el('incVal', String(inc)) + el('input_0', floats(x)) + el('input_1', floats(y)) + el('output', floats(z)));
const xml = '<ecu>' +
  el('DeviceDataInformationModel', el('ProductName', 'DEMO') + el('ModelName', 'BENCH') + el('Version', '1')) +
  `<links>${links.map(([id, name, unit, lo, hi]) => el('DataLinkModel', el('id', String(id)) + el('name', name) + el('measureUnit', unit) +
    el('ViewInTree', 'true') + el('MinValue', String(lo)) + el('MaxValue', String(hi)))).join('')}</links>` +
  '<tables>' +
  table(4096, 'Fuel VE', 'Fuel', 16, 16, 1, 2, 9, rpm, map, ve, 0.1) +
  table(4097, 'Ignition advance', 'Ignition', 16, 16, 1, 2, 8, rpm, map, ign, 0.5) +
  table(4098, 'Lambda target', 'Fuel', 16, 16, 1, 2, 6, rpm, map, lam, 0.01) +
  table(4099, 'Cranking fuel', 'Fuel', 16, 1, 4, 0, 9, clt, [0], clt.map((t) => 400 - 3 * t), 1) +
  table(4100, 'Intake temperature trim', 'Ignition', 16, 1, 5, 0, 8, iat, [0], iat.map((t) => (t > 30 ? -(t - 30) / 5 : 0)), 0.5) +
  '</tables><drivers></drivers></ecu>';
process.stdout.write(xml);
