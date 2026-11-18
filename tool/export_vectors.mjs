// Generates the golden vectors the Dart core is tested against, by running the TypeScript engine (the oracle).
//
//   node tool/export_vectors.mjs [path-to-me360]      (default: ../me360, a sibling of this repo)
//
// Writes core/test/vectors/{requests,replies,reporting,recognition,device_files,calibration_files,simulator,
// session,live,faults,sim_faults,units,custom_can,sim_can,calibration_import,onboard_logs,dbc}.json and copies the original-decoder fuzz corpus.
// Deterministic: the same engine produces byte-identical files.
import { writeFileSync, copyFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

process.env.TZ = 'UTC'; // the simulator's on-board logs carry local dates
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const me360 = resolve(process.argv[2] ?? resolve(root, '../me360'));
const out = resolve(root, 'core/test/vectors');
mkdirSync(out, { recursive: true });
const src = (f) => import(pathToFileURL(resolve(me360, 'src', f)).href);

const kinds = await src('kinds.ts');
const tables = await src('tables-msg.ts');
const drivers = await src('drivers-msg.ts');
const sys = await src('sys-msg.ts');
const reporting = await src('reporting.ts');
const datalog = await src('datalog-msg.ts');
const trigger = await src('trigger-dbw-msg.ts');
const faults = await src('faults.ts');
const firmware = await src('firmware.ts');

// ---------------------------------------------------------------- helpers
let seed = 0x5eed;
const rnd = () => (seed = (Math.imul(seed, 1103515245) + 12345) >>> 0) / 0x100000000;
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const bytes = (n) => Array.from({ length: n }, () => int(256));
const le16 = (v) => [v & 0xff, (v >> 8) & 0xff];
const le32 = (v) => [v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff];
const f32 = (v) => [...new Uint8Array(Float32Array.of(v).buffer)];
const randF32 = () => (rnd() < 0.85 ? f32((rnd() - 0.5) * 2 * 10 ** int(6)) : bytes(4));
const hex = (a) => Buffer.from(a).toString('hex');
const frameHex = (f) => hex([f.type, f.cls, f.cmd, ...f.payload]);

/** JSON-safe form shared with the Dart side: bytes as "hex:..", non-finite numbers as strings, Maps as entry lists. */
function norm(v) {
  if (v === undefined) return undefined;
  if (v === null) return null;
  if (v instanceof Uint8Array) return 'hex:' + hex(v);
  if (typeof v === 'number') return Number.isFinite(v) ? v : String(v);
  if (Array.isArray(v)) return v.map(norm);
  if (v instanceof Map) return [...v.entries()].map(norm);
  if (typeof v === 'object') {
    const o = {};
    for (const [k, x] of Object.entries(v)) { const n = norm(x); if (n !== undefined) o[k] = n; }
    return o;
  }
  return v;
}
const attempt = (fn) => { try { return { ok: norm(fn()) }; } catch (e) { return { error: true }; } };
const write = (name, data) => writeFileSync(resolve(out, name), JSON.stringify(data) + '\n');

// ---------------------------------------------------------------- requests
const requests = [];
const req = (name, args, fn) => {
  const r = attempt(fn);
  requests.push({ name, args: norm(args), ...(r.error ? { error: true } : { frame: frameHex(fn()) }) });
};
const ascii = (n) => String.fromCharCode(...Array.from({ length: n }, () => 32 + int(95)));
const anyText = (n) => Array.from({ length: n }, () => (rnd() < 0.8 ? String.fromCharCode(32 + int(95)) : pick(['é', 'Ω', '€', '😀', '\u0000']))).join('');
for (let i = 0; i < 40; i++) {
  const id = int(65536), u = rnd() < 0.2 ? int(2 ** 31) : id;
  req('tables.get', [u], () => tables.getTableRequest(u));
  req('tables.store', [u], () => tables.storeTableRequest(u));
  req('tables.enable', [u], () => tables.enableTableRequest(u));
  req('tables.disable', [u], () => tables.disableTableRequest(u));
  const on = rnd() < 0.5;
  req('tables.setReporting', [id, on], () => tables.setTableReportingRequest(id, on));
  const blob = Uint8Array.from(bytes(int(40)));
  req('tables.set', [id, blob], () => tables.setTableRequest({ id, serialize: () => [...blob] }));
  req('drivers.set', [id, blob], () => drivers.setDriverRequest({ id, serialize: () => [...blob] }));
  const n = int(5), offsets = Array.from({ length: n }, () => int(70000)), elem = int(300);
  const chunks = Array.from({ length: rnd() < 0.1 ? n + 1 : n }, () => Array.from({ length: 1 + int(4) }, () => Math.fround((rnd() - 0.5) * 1e4)));
  req('tables.setData', [id, elem, offsets, chunks], () => tables.setTableDataRequest(id, elem, offsets, chunks));
  req('drivers.get', [u], () => drivers.getDriverRequest(u));
  req('drivers.store', [u], () => drivers.storeDriverRequest(u));
  const mode = int(300);
  req('sys.getHash', [mode], () => sys.getHashRequest(mode));
  const enc = Uint8Array.from(bytes(int(20)));
  req('sys.raceUnlock', [enc], () => sys.raceUnlockRequest(enc));
  const rtc = [int(40), int(14), 1990 + int(100), int(30), int(70)];
  req('sys.setRtc', rtc, () => sys.setRtcRequest(...rtc));
  const pw = anyText(int(20)), contact = anyText(rnd() < 0.9 ? int(100) : 97 + int(5)), lockedIds = Array.from({ length: int(6) }, () => int(65536));
  const lock = rnd() < 0.5, temp = rnd() < 0.5;
  req('sys.pwLockSetState', [lock, temp, pw, contact, lockedIds], () => sys.pwLockSetStateRequest(lock, temp, pw, contact, lockedIds));
  req('reporting.setState', [on], () => reporting.setStateRequest(on));
  const freq = int(400), ids = Array.from({ length: int(8) }, () => int(65536));
  req('reporting.setSpecialCfg', [freq, ids], () => reporting.setSpecialCfgRequest(freq, ids));
  req('datalog.eraseLog', [id], () => datalog.eraseLogRequest(id));
  req('datalog.getLogDetail', [u], () => datalog.getLogDetailRequest(u));
  const start = int(2 ** 32), count = int(2 ** 32);
  req('datalog.getLogRegion', [id, start, count], () => datalog.getLogRegionRequest(id, start, count));
  req('datalog.setConfig', [freq, on, ids], () => datalog.setConfigRequest(freq, on, ids));
  const chans = Array.from({ length: int(5) }, () => int(300) - 2);
  req('trigger.setState', [on, chans], () => trigger.triggerSetStateRequest(on, chans));
  req('trigger.setStateMask', [on, id], () => trigger.triggerSetStateRequestMask(on, id));
  const duty = (rnd() - 0.5) * 300;
  req('dbw.setDuty', [id & 0x1ff, duty], () => trigger.setDbwDutyRequest(id & 0x1ff, duty));
  req('faults.getFrameLayout', [id, int(400)], () => faults.faultsGetFrameLayoutRequest(id, requests.at(-1)?.args?.[1] ?? 0));
  const c2 = int(100);
  req('faults.getSummary', [id, c2], () => faults.faultsGetSummaryRequest(id, c2));
  req('faults.getOccurrence', [u], () => faults.faultsGetOccurrenceRequest(u));
}
// the getFrameLayout lambda above reads its own args; recompute to keep the vector honest
for (const r of requests) if (r.name === 'faults.getFrameLayout') r.frame = frameHex(faults.faultsGetFrameLayoutRequest(...r.args));
for (const [name, fn] of Object.entries({
  'sys.getEcuInfo': sys.getEcuInfoRequest, 'sys.factoryReset': sys.factoryResetRequest, 'sys.pwLockGetState': sys.pwLockGetStateRequest,
  'drivers.getCanReservedIds': drivers.getCanReservedIdsRequest, 'datalog.isSupported': datalog.isSupportedRequest,
  'datalog.getConfig': datalog.getConfigRequest, 'datalog.start': datalog.startRequest, 'datalog.stop': datalog.stopRequest,
  'datalog.getLogsSummary': datalog.getLogsSummaryRequest, 'datalog.formatMemory': datalog.formatMemoryRequest,
  'trigger.isSupported': trigger.triggerIsSupportedRequest, 'faults.getInfo': faults.faultsGetInfoRequest,
  'faults.clear': faults.faultsClearRequest, 'faults.eraseLog': faults.faultsEraseLogRequest, 'firmware.enterBootloader': firmware.enterBootloaderRequest,
})) req(name, [], fn);
write('requests.json', requests);

// ---------------------------------------------------------------- replies (classes 1–9; class 0 is stateful, below)
const status = () => (rnd() < 0.85 ? pick([0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 255]) : int(256));
const utf8 = (s) => [...new TextEncoder().encode(s)];
const logInfo = () => {
  const valid = rnd() < 0.85;
  return [int(256), valid ? 1 + int(28) : int(40), valid ? 1 + int(12) : int(16), ...le16(valid ? 2000 + int(40) : int(65536)),
    valid ? int(24) : int(30), valid ? int(60) : int(70), ...randF32(), ...le32(int(2 ** 32)), ...le16(int(6))];
};
const GEN = {
  '1/1': () => { const n = int(30); return [status(), ...le16(int(65536)), ...le16(n), ...bytes(n)]; },
  '1/4': () => { const n = int(5); return [status(), ...le16(int(65536)), int(256), ...le16(n), ...Array.from({ length: n }, () => [...le16(int(65536)), ...randF32()]).flat()]; },
  '2/1': () => { const n = int(30); return [status(), ...le16(int(65536)), ...le16(n), ...bytes(n)]; },
  '2/3': () => { const n = int(6); return [status(), n, ...Array.from({ length: n }, () => [...le32(int(2 ** 32)), int(8)]).flat()]; },
  '4/0': () => {
    const parts = [ascii(int(10)), ascii(int(10)), ascii(int(6)), ascii(int(6)), ascii(int(16)),
      pick(['', '1a2b', '0x00ff', 'FFFF', '10000', 'zz', '0x', '000000001', '123456789']), pick(['PW', '', 'pw'])];
    let s = parts.slice(0, 3 + int(6)).join('\0');
    if (rnd() < 0.2) s += '\0' + anyText(4);
    const b = utf8(s);
    if (rnd() < 0.15) b.splice(int(b.length + 1), 0, pick([0xff, 0xc3, 0xe2, 0x80, 0xf0, 0xed]));
    return [status(), ...b];
  },
  '4/1': () => {
    const mode = pick([0, 1, 1, 2]), n = int(5), keys = Array.from({ length: n }, () => (rnd() < 0.15 ? 7 : int(65536)));
    return [status(), mode, ...le16(int(65536)), ...(mode === 1 ? [...le16(n), ...keys.flatMap((k) => [...le16(k), ...le16(int(65536))])] : [])];
  },
  '4/4': () => [status(), int(3), int(3)],
  '4/5': () => [status(), int(3), int(3), ...utf8(anyText(int(20)))],
  '6/0': () => [status(), ...le16(int(65536)), ...le16(int(65536))],
  '6/1': () => { const n = int(6); return [status(), ...le16(int(1000)), ...le16(n), int(3), ...Array.from({ length: n }, () => le16(int(65536))).flat()]; },
  '6/5': () => { const n = int(4); return [status(), ...le16(n), ...bytes(8), ...Array.from({ length: n }, logInfo).flat()]; },
  '6/6': () => { const li = logInfo(); const nc = li[15] | (li[16] << 8); return [status(), ...li, ...Array.from({ length: nc }, () => le16(int(65536))).flat()]; },
  '6/7': () => { const nc = int(4), ne = int(4); return [status(), int(256), ...le16(nc), ...le32(int(2 ** 32)), ...le32(ne), ...Array.from({ length: ne * (nc + 1) }, randF32).flat()]; },
  '6/8': () => [status(), int(256)],
  '7/0': () => [status(), ...(rnd() < 0.7 ? [int(256)] : [])],
  '7/1': () => [status(), int(3), int(256), ...le32(int(2 ** 32))],
  '7/2': () => { const n = int(6); return [status(), ...le16(n), ...bytes(3 * n)]; },
  '9/0': () => [status(), ...bytes(24)],
  '9/1': () => { const n = int(6); return [status(), ...le16(int(100)), ...le16(n), ...le16(int(200)), ...bytes(3 * n)]; },
  '9/2': () => { const n = int(3); return [status(), ...le16(int(100)), ...le16(n), ...le16(int(200)), ...bytes(26 * n)]; },
  '9/3': () => {
    const body = bytes(int(40)), size = 28 + (rnd() < 0.8 ? body.length : int(60));
    const rec = [...le16(rnd() < 0.7 ? 0xfa17 : int(65536)), int(5), int(256), ...le32(int(2 ** 32)), ...le16(int(65536)), ...le16(int(65536)),
      ...le32(int(2 ** 32)), ...le32(int(2 ** 32)), ...le32(int(2 ** 32)), ...le16(rnd() < 0.8 ? body.length : int(80)), ...le16(int(65536)), ...body];
    return [status(), ...le16(int(65536)), ...le16(size), ...rec];
  },
};
const RECOGNISED = { 1: [0, 1, 2, 3, 4, 6, 7], 2: [0, 1, 2, 3], 4: [0, 1, 3, 4, 5, 6], 5: [0, 1, 2, 3], 6: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], 7: [0, 1, 2], 9: [0, 1, 2, 3, 4, 5] };
const mutate = (p) => {
  const r = rnd();
  if (r < 0.55) return p;
  if (r < 0.8) return p.slice(0, int(p.length + 1));
  const q = [...p];
  for (let k = 1 + int(3); k > 0 && q.length; k--) q[int(q.length)] = int(256);
  if (rnd() < 0.3) q.push(...bytes(int(8)));
  return q;
};
const replies = [];
for (const [cls, cmds] of Object.entries(RECOGNISED)) for (const cmd of cmds) {
  const gen = GEN[`${cls}/${cmd}`] ?? (() => [status(), ...(cls === '1' || (cls === '2' && cmd <= 2) ? le16(int(65536)) : []), ...bytes(int(4))]);
  for (let i = 0; i < 120; i++) {
    const frame = { type: 0x0f, cls: Number(cls), cmd, payload: Uint8Array.from(mutate(gen())) };
    const f = new kinds.MessageFactory();
    replies.push({ frame: frameHex(frame), reply: norm(f.create(frame)) });
  }
}
write('replies.json', replies);

// ---------------------------------------------------------------- reporting: stateful sequences through one factory
const linkMap = (n) => Array.from({ length: n }, () => [...le16(rnd() < 0.2 ? int(4) : int(65536)), rnd() < 0.9 ? int(6) : int(256)]);
const sizeOf = (t) => [4, 2, 2, 1, 1, 1][t] ?? 4;
const reportingSeq = [];
for (let s = 0; s < 400; s++) {
  const f = new kinds.MessageFactory(); const frames = []; const results = [];
  let layout = [];
  for (let k = 1 + int(6); k > 0; k--) {
    let p; let cmd = pick([0, 0, 0, 1, 2, 2, 3, 0]);
    if (cmd === 2) {
      if (rnd() < 0.3) p = [status()];
      else { const m = linkMap(int(6)); layout = m; p = [status(), ...le16(m.length), ...m.flat()]; }
    } else if (cmd === 3) { const m = linkMap(int(6)); layout = m; p = [status(), int(256), ...le16(m.length), ...m.flat()]; }
    else if (cmd === 1) p = [status()];
    else if (rnd() < 0.5 && layout.length) {
      p = [status()];
      const seen = new Set();
      for (const e of layout) { const id = e[0] | (e[1] << 8); if (seen.has(id)) continue; seen.add(id); p.push(...bytes(sizeOf(e[2]))); }
    } else { const n = int(4); p = [status(), ...le16(n), ...Array.from({ length: n }, () => [...le16(int(65536)), ...randF32()]).flat()]; }
    if (rnd() < 0.15) p = p.slice(0, int(p.length + 1));
    const frame = { type: 0x0f, cls: 0, cmd, payload: Uint8Array.from(p) };
    frames.push(frameHex(frame)); results.push(norm(f.create(frame)));
  }
  reportingSeq.push({ frames, replies: results });
}
write('reporting.json', reportingSeq);

// ---------------------------------------------------------------- recognition, reply matching, ECU-side firmware requests
const recognition = [];
for (let i = 0; i < 3000; i++) {
  const type = pick([0x0f, 0x0f, 0x00, 0x00, int(256)]), cls = rnd() < 0.9 ? int(11) : int(256), cmd = rnd() < 0.9 ? int(11) : int(256);
  const gen = GEN[`${cls}/${cmd}`];
  const payload = Uint8Array.from(gen && type === 0x0f && rnd() < 0.6 ? mutate(gen()) : bytes(int(14)));
  const frame = { type, cls, cmd, payload };
  const f = new kinds.MessageFactory();
  const row = {
    frame: frameHex(frame), recognised: kinds.isRecognised(frame, f), countsAsReply: kinds.countsAsReply(frame, f),
    entityId: kinds.entityId(frame) ?? null, successful: kinds.isSuccessful(frame), expected: norm(kinds.expectedReply(frame)),
  };
  if (type === 0 && cls === 5 && (cmd === 1 || cmd === 2)) row.fwRequest = attempt(() => firmware.parseFwRequest(frame));
  recognition.push(row);
}
write('recognition.json', recognition);

// ---------------------------------------------------------------- device files: synthetic definitions and calibrations
// Made up here, so no vendor content enters the repo. Each is loaded by the TypeScript engine; the vectors hold what it
// built: wire blobs and hashes per table and driver, the overall hash, and which items it kept.
const { DeviceDataModel } = await src('device-model.ts');
const TYPES = [['T1x16', 1, 16], ['T1x32', 1, 32], ['T16x16', 16, 16], ['T32x32', 32, 32], ['T1x2', 1, 2], ['T8x8', 8, 8]];
const numText = (v) => pick([String(v), ` ${v} `, v.toExponential(), String(v).replace(/^0\./, '.'), String(v)]);
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const el = (name, body) => `<${name}>${body}</${name}>`;
const floatsXml = (vals) => vals.map((v) => el('float', numText(v))).join('');
const randVal = () => Math.round((rnd() - 0.3) * 10 ** int(5)) / 10 ** int(3);
function deviceXml() {
  const nLinks = 3 + int(12), linkIds = Array.from({ length: nLinks }, (_, i) => i + 1 + (rnd() < 0.2 ? 500 : 0));
  const parts = [];
  parts.push(el('DeviceDataInformationModel', el('ProductName', 'SIM-ECU') + el('ModelName', pick(['GENERIC', 'TEST'])) + el('Version', String(1 + int(99))) + (rnd() < 0.5 ? el('FWVersion', '1.' + int(9)) : '')));
  if (rnd() < 0.5) parts.push(el('CalibrationNotes', el('Text', esc(anyText(int(30)).replace(/\u0000/g, ''))))); // XML forbids NUL
  const links = linkIds.map((id) => el('DataLinkModel', el('id', String(id)) + el('name', 'Link ' + id) + el('category', pick(['Inputs', 'Fuel', 'Ignition'])) +
    (rnd() < 0.5 ? el('ViewInTree', pick(['true', 'false', '1'])) : '') + (rnd() < 0.3 ? el('MinValue', numText(-10)) + el('MaxValue', numText(100 + int(9000))) : '') +
    (rnd() < 0.3 ? el('StandardLogging', 'true') : '') + (rnd() < 0.2 ? el('MeasurementUnitTypes', '<Celsius /><Fahrenheit />') : '') +
    (rnd() < 0.2 ? el('TextValues', [0, 1, 2].map((v) => el('TextValueModel', el('value', String(v)) + el('text', 'T' + v))).join('')) : '') +
    (rnd() < 0.2 ? el('Feedbacks', el('Warning', el('Constraints', `<Gt Value="${int(100)}" /><Eq Value="1 2  3" />`)) + `<Alarm Flashing="true">${el('Constraints', `<LtEq Value="-${int(9)}.5" />`)}</Alarm>`) : '') +
    (rnd() < 0.1 ? el('DataTypeSet', pick(['Normal', 'Percent', 'ADCRaw'])) : '')));
  const tableIds = Array.from({ length: 2 + int(8) }, (_, i) => (rnd() < 0.1 ? 4096 : 4096 + i));
  const tables = tableIds.map((id) => {
    const [type, rows, cols] = pick(TYPES);
    const lk = () => (rnd() < 0.07 ? 999 : pick(linkIds));
    const n = (k) => (rnd() < 0.15 ? Math.max(0, k + int(5) - 2) : k);
    return el('TableModel', el('name', 'Table ' + id) + el('id', String(id)) + el('type', type) + el('cols', String(cols)) + el('rows', String(rows)) +
      el('input_0_LinkId', String(lk())) + (rows > 1 || rnd() < 0.3 ? el('input_1_LinkId', String(lk())) : '') + el('output_LinkId', String(lk())) +
      el('enabled', pick(['true', 'false'])) + (rnd() < 0.3 ? el('incVal', numText(0.25)) : '') +
      (rnd() < 0.85 ? el('input_0', floatsXml(Array.from({ length: n(cols) }, randVal))) : '') +
      (rows > 1 && rnd() < 0.85 ? el('input_1', floatsXml(Array.from({ length: n(rows) }, randVal))) : '') +
      (rnd() < 0.85 ? el('output', floatsXml(Array.from({ length: n(rows * cols) }, randVal))) : ''));
  });
  const drivers = Array.from({ length: 1 + int(5) }, (_, i) => {
    const nc = int(8), no = int(5), ni = int(5), ps = rnd() < 0.4 ? 1 + int(12) : 0;
    const params = Array.from({ length: nc }, (_, k) => el('DriverModelParam', el('name', 'P' + k) + el('type', pick(['InputBox', 'ComboBox'])) +
      (rnd() < 0.8 ? el('value', numText(randVal())) : '') + (rnd() < 0.3 ? el('Min', '0') + el('Max', '100') + el('CheckRange', 'true') : '') +
      (rnd() < 0.2 ? el('options', [0, 1].map((o) => el('comboBoxOption', el('id', String(o)) + el('name', 'O' + o))).join('')) : '')));
    const ids = (k) => el('unsignedShort', String(int(65536))).repeat(1) && Array.from({ length: rnd() < 0.15 ? Math.max(0, k + int(3) - 1) : k }, () => el('unsignedShort', String(int(65536)))).join('');
    const priv = Buffer.from(bytes(ps === 0 ? 0 : rnd() < 0.2 ? Math.max(0, ps + int(5) - 2) : ps)).toString('base64');
    return el('DriverModel', el('id', String(8192 + i)) + el('name', 'Driver ' + i) + el('numberOfConfigs', String(nc)) + el('configParams', params.join('')) +
      el('numberOfOutputs', String(no)) + el('outputLinkIds', ids(no)) + el('numberOfInputs', String(ni)) + el('inputLinkIds', ids(ni)) +
      (ps ? el('privSize', String(ps)) + el('privData', priv) : '') + (rnd() < 0.2 ? el('ConfigValidation', el('CheckDuplicates', 'true')) : ''));
  });
  return '﻿<?xml version="1.0" encoding="utf-8"?>\n<ecu>\n' + parts.join('\n') + `\n<links>${links.join('\n')}</links>\n<tables>${tables.join('\n')}</tables>\n<drivers>${drivers.join('\n')}</drivers>\n</ecu>\n`;
}
const deviceFiles = [];
for (let i = 0; i < 150; i++) {
  let xml = deviceXml();
  if (i % 15 === 14) xml = xml.replace(/<cols>(\d+)<\/cols>/, '<cols>x$1</cols>');          // a malformed number
  if (i % 25 === 24) xml = xml.replace('<tables>', '<tablez>').replace('</tables>', '</tablez>'); // a missing section
  let m;
  try { m = DeviceDataModel.fromXml(xml, null); } catch { deviceFiles.push({ xml, error: true }); continue; }
  const v = m.versionInformation;
  deviceFiles.push({
    xml,
    info: norm({ productName: v.productName ?? null, modelName: v.modelName ?? null, version: v.version ?? null, fwVersion: v.fwVersion ?? null }),
    notes: m.notes.text,
    links: [...m.allDataLinks.keys()],
    tables: [...m.allTables.values()].map((t) => ({ id: t.id, blob: hex(t.serialize()), hash: t.getHash() })),
    drivers: [...m.allDrivers.values()].map((d) => ({ id: d.id, blob: hex(d.serialize()), hash: d.getHash() })),
    overall: m.getOverallHash(),
  });
}
write('device_files.json', deviceFiles);

// ---------------------------------------------------------------- calibration files: the .mecal writer
// Richer synthetic files that use every member the writer knows, odd text and awkward float values. For each: the file
// as loaded and saved by the TypeScript writer, then edits through wire blobs (as reads from the ECU arrive) and new
// notes, and the file saved again.
const { saveCalibrationXml } = await src('calibration.ts');
const ODD_FLOATS = [0, -0, 1, -1, 0.1, 1 / 3, NaN, Infinity, -Infinity, 1e-45, 1.1754943508222875e-38, 3.4028234663852886e38,
  0.00048828125, 0.0009765625, 16777216, 123456792, 1e7, 9999999, 1e-5, 0.0001, 12345.678, 100000, 1234567.5, -2.5e-7, 0.5, 65535];
const oddF32 = () => (rnd() < 0.5 ? pick(ODD_FLOATS) : Math.fround((rnd() - 0.5) * 10 ** (int(16) - 8)));
const xmlNum = (v) => (Number.isNaN(v) ? 'NaN' : v === Infinity ? 'INF' : v === -Infinity ? '-INF' : Object.is(v, -0) ? '-0' : numText(v));
const oddText = () => pick(['', ' ', 'Plain', '  padded  ', 'Fuel & <Air> "quoted" \'single\'', 'tab\there', 'line\nbreak', 'cr\r\nlf', 'lone\rcr',
  'é Ω € 😀', ']]> end', anyText(int(12)).replace(/\u0000/g, '')]);
const textEl = (name) => (rnd() < 0.15 ? `<${name} />` : rnd() < 0.1 ? `<${name}><![CDATA[c<d>&]]></${name}>` : el(name, esc(oddText())));
const attrText = () => pick(['g1', 'a&amp;b', 'q&quot;t', 'tab&#x9;ref', 'nl&#xA;ref', 'raw\ttab', 'raw\nnl', '&lt;x&gt;', '']);
const UNIT_NAMES = ['Raw', 'Volt', 'Ohm', 'KPa', 'PSI', 'Celsius', 'Fahrenheit'];
const unitsXml = () => el('MeasurementUnitTypes', Array.from({ length: int(3) }, () => `<${pick(UNIT_NAMES)} />`).join(''));
const maybe = (p, f) => (rnd() < p ? f() : '');
const baseXml = (id) => maybe(0.3, () => el('DefaultLocked', pick(['true', 'false']))) + el('id', String(id)) + maybe(0.9, () => textEl('name')) +
  maybe(0.4, () => el('ViewInTree', pick(['true', 'false']))) + maybe(0.3, () => el('BoardSpecific', pick(['true', '1', 'false']))) + maybe(0.8, () => textEl('category'));
const validationXml = (name) => el(name, maybe(0.7, () => el('CheckDuplicates', pick(['true', 'false']))) +
  maybe(0.6, () => el('DefaultValues', Array.from({ length: int(4) }, () => `<DefaultValue${maybe(0.6, () => ` Group="${attrText()}"`)}${maybe(0.9, () => ` Value="${xmlNum(oddF32())}"`)} />`).join(''))) +
  maybe(0.5, () => el('Exceptions', Array.from({ length: int(3) }, () => `<${pick(['AllowMultipleDuplicates', 'AllowIndex', 'AllowValue', 'DenyValue', 'DenyIndex'])}${maybe(0.5, () => ` Group="${attrText()}"`)} Value="${int(9)}" />`).join(''))));
const linkCfgXml = (name) => el(name, Array.from({ length: int(4) }, () => el('LinkConfig', el('Index', String(int(9))) + el('Visible', pick(['true', 'false'])))).join(''));
const namesXml = (name, n) => el(name, Array.from({ length: n }, () => (rnd() < 0.2 ? '<string />' : el('string', esc(oddText())))).join(''));

function richXml() {
  const linkIds = Array.from({ length: 3 + int(8) }, (_, i) => 1 + i);
  const parts = [];
  if (rnd() < 0.9) parts.push(el('DeviceDataInformationModel', maybe(0.9, () => el('ProductName', 'SIM-ECU')) + maybe(0.9, () => el('ModelName', pick(['GENERIC', 'TEST']))) +
    maybe(0.9, () => el('Version', String(1 + int(99)))) + maybe(0.5, () => el('FWVersion', '1.' + int(9)))));
  if (rnd() < 0.7) parts.push(rnd() < 0.2 ? '<CalibrationNotes />' : el('CalibrationNotes', textEl('Text')));
  const links = linkIds.map((id) => el('DataLinkModel', baseXml(id) + maybe(0.3, () => textEl('DataKey')) +
    maybe(0.3, () => el('Feedbacks', Array.from({ length: 1 + int(3) }, () => {
      const kind = pick(['Default', 'Ok', 'Warning', 'Alarm']);
      const cons = maybe(0.8, () => el('Constraints', Array.from({ length: int(3) }, () => {
        const k = pick(['Eq', 'Gt', 'GtEq', 'GtInc', 'Lt', 'LtEq']);
        if (k === 'Eq') return rnd() < 0.2 ? '<Eq />' : `<Eq Value="${Array.from({ length: 1 + int(3) }, () => xmlNum(oddF32())).join(pick([' ', '  ', '\t']))}" />`;
        return `<${k} Value="${xmlNum(oddF32())}" />`;
      }).join('')));
      return `<${kind}${maybe(0.4, () => ` Flashing="${pick(['true', 'false'])}"`)}>${cons}</${kind}>`;
    }).join(''))) +
    maybe(0.5, () => unitsXml()) + maybe(0.4, () => textEl('measureUnit')) + maybe(0.3, () => el('StandardLogging', pick(['true', 'false']))) +
    maybe(0.3, () => el('TextValues', [0, 1, 2, 5].slice(0, int(5)).map((v) => el('TextValueModel', el('value', String(v)) + maybe(0.8, () => textEl('text')))).join(''))) +
    maybe(0.3, () => el('DataTypeSet', pick(['Normal', 'TrimModPercent', 'Percent', 'ADCRaw']))) +
    maybe(0.4, () => el('MinValue', xmlNum(oddF32())) + el('MaxValue', xmlNum(oddF32())))));
  const tables = Array.from({ length: 1 + int(6) }, (_, i) => {
    const [type, rows, cols] = pick(rnd() < 0.9 ? TYPES.filter(([n]) => n !== 'T32x32') : TYPES);
    const vals = (n) => Array.from({ length: n }, () => el('float', xmlNum(oddF32()))).join('');
    return el('TableModel', baseXml(4096 + i) + maybe(0.8, () => el('enabled', pick(['true', 'false']))) + el('type', type) +
      maybe(0.3, () => el('function', pick(['Normal', 'PercentTrim']))) + el('cols', String(cols)) + el('rows', String(rows)) +
      el('input_0_LinkId', String(pick(linkIds))) + el('input_1_LinkId', String(rows > 1 ? pick(linkIds) : pick([0, ...linkIds]))) + el('output_LinkId', String(pick(linkIds))) +
      maybe(0.5, () => textEl('input_0_name')) + maybe(0.5, () => textEl('input_1_name')) + maybe(0.5, () => textEl('output_name')) +
      maybe(0.9, () => el('input_0', vals(cols))) + maybe(0.7, () => el('input_1', vals(rows))) + maybe(0.9, () => el('output', vals(rows * cols))) +
      maybe(0.5, () => el('incVal', xmlNum(oddF32()))) + maybe(0.5, () => el('defaultValue', xmlNum(oddF32()))) + maybe(0.3, () => textEl('DataKey')));
  });
  const drivers = Array.from({ length: 1 + int(4) }, (_, i) => {
    const nc = int(7), no = int(5), ni = int(5), ps = rnd() < 0.4 ? 1 + int(12) : 0;
    const params = Array.from({ length: nc }, () => el('DriverModelParam', maybe(0.3, () => textEl('ValidationGroup')) + maybe(0.9, () => textEl('name')) +
      maybe(0.5, () => textEl('DisplayName')) + maybe(0.5, () => textEl('SectionName')) + maybe(0.8, () => el('type', pick(['InputBox', 'ComboBox']))) +
      maybe(0.3, () => el('readOnly', pick(['true', 'false']))) + maybe(0.3, () => el('Hidden', pick(['true', 'false']))) + maybe(0.3, () => el('RequiresReset', 'true')) +
      maybe(0.4, () => textEl('ToolTipText')) + maybe(0.8, () => el('value', xmlNum(oddF32()))) + maybe(0.4, () => el('Min', xmlNum(oddF32())) + el('Max', xmlNum(oddF32()))) +
      maybe(0.3, () => el('CheckRange', pick(['true', 'false']))) +
      maybe(0.2, () => el('ViewConstraint', el('ParamIndex', String(int(nc))) + maybe(0.8, () => el('AcceptedValues', Array.from({ length: int(3) }, () => el('float', String(int(4)))).join(''))))) +
      maybe(0.3, () => el('options', Array.from({ length: int(4) }, (_, o) => el('comboBoxOption', el('id', String(o)) + maybe(0.8, () => textEl('name')))).join(''))) +
      maybe(0.4, () => unitsXml())));
    const ids = (k) => Array.from({ length: k }, () => el('unsignedShort', String(int(65536)))).join('');
    return el('DriverModel', baseXml(8192 + i) + maybe(0.3, () => validationXml('ConfigValidation')) + el('numberOfConfigs', String(nc)) + el('configParams', params.join('')) +
      (ps ? el('privSize', String(ps)) + maybe(0.8, () => el('privData', Buffer.from(bytes(ps)).toString('base64'))) : '') +
      maybe(0.3, () => validationXml('OutputValidation')) + el('numberOfOutputs', String(no)) + maybe(0.9, () => el('outputLinkIds', ids(no))) +
      maybe(0.4, () => el('editableOutputs', pick(['true', 'false']))) + maybe(0.5, () => namesXml('outputNames', no)) + maybe(0.3, () => validationXml('InputValidation')) +
      maybe(0.4, () => el('editableInputs', pick(['true', 'false']))) + maybe(0.5, () => namesXml('inputNames', ni)) + el('numberOfInputs', String(ni)) +
      maybe(0.9, () => el('inputLinkIds', ids(ni))) + maybe(0.3, () => linkCfgXml('InputLinksConfigs')) + maybe(0.3, () => linkCfgXml('OutputLinkConfigs')));
  });
  return '﻿<?xml version="1.0" encoding="utf-8"?>\r\n<ecu>\r\n' + parts.join('\r\n') + `\r\n<links>${links.join('\n')}</links>\n<drivers>${drivers.join('\n')}</drivers>\n<tables>${tables.join('\n')}</tables>\n</ecu>`;
}

const f32Bytes = (vals) => vals.flatMap(f32);
const calibrationFiles = [];
for (let i = 0; i < 60; i++) {
  const xml = richXml();
  const m = DeviceDataModel.fromXml(xml, null);
  const saved = saveCalibrationXml(m);
  const tableEdits = [...m.allTables.values()].filter(() => rnd() < 0.6).map((t) => {
    const blob = Uint8Array.from([t.type, int(2), t.rows, t.cols, ...(t.rows > 1 ? f32Bytes(Array.from({ length: t.rows }, oddF32)) : []),
      ...f32Bytes(Array.from({ length: t.cols }, oddF32)), ...f32Bytes(Array.from({ length: t.rows * t.cols }, oddF32))]);
    t.deserialize(blob);
    return { id: t.id, blob: hex(blob) };
  });
  const driverEdits = [...m.allDrivers.values()].filter(() => rnd() < 0.6).map((d) => {
    const blob = Uint8Array.from([d.numberOfConfigs, d.numberOfOutputs, d.numberOfInputs, ...f32Bytes(Array.from({ length: d.numberOfConfigs }, oddF32)),
      ...Array.from({ length: d.numberOfOutputs + d.numberOfInputs }, () => le16(int(65536))).flat(), ...bytes(d.privSize)]);
    d.deserialize(blob);
    return { id: d.id, blob: hex(blob) };
  });
  const notes = rnd() < 0.2 ? null : oddText();
  m.updateNotes({ text: notes });
  calibrationFiles.push({ xml, saved, tableEdits, driverEdits, notes, savedAfterEdits: saveCalibrationXml(m) });
}
write('calibration_files.json', calibrationFiles);

// ---------------------------------------------------------------- simulator: scripted sessions against the TypeScript ECU
// Each session loads a synthetic definition into the simulator at a fixed clock, then sends requests and runs report
// ticks; the vectors hold every reply. Timers are stubbed so nothing runs on its own.
const { SimEcu } = await src('ecu-sim.ts');
const SPECIAL_LINKS = [1, 1015, 1018, 2331, 2332, 2333, 2334, 2335, 2339, 2340, 2341];
const DBW_KEYS = ['DBW_PWM', 'DBW_BATT_V_MULT', 'TPPS1_VAL', 'TPPS2_VAL', 'TPPS1_RAW', 'TPPS2_RAW', 'RPM'];
let lastSimXml = '';
function simXml() {
  const ids = [...new Set([...SPECIAL_LINKS.filter(() => rnd() < 0.5), ...Array.from({ length: 3 + int(8) }, () => 3 + int(900))])];
  const links = ids.map((id) => el('DataLinkModel', el('id', String(id)) + el('name', 'L' + id) + maybe(0.6, () => el('ViewInTree', 'true')) +
    maybe(0.5, () => el('StandardLogging', 'true')) + maybe(0.3, () => el('DataKey', pick(DBW_KEYS))) +
    maybe(0.2, () => el('TextValues', [0, 1, 3].slice(0, 1 + int(3)).map((v) => el('TextValueModel', el('value', String(v)) + el('text', 'T' + v))).join(''))) +
    maybe(0.4, () => el('MinValue', String(-int(50))) + el('MaxValue', String(int(9000)))) + maybe(0.05, () => el('MinValue', 'INF'))));
  const tables = Array.from({ length: 1 + int(5) }, (_, i) => {
    const [type, rows, cols] = pick(TYPES.filter(([n]) => n !== 'T32x32'));
    const axis = (n) => Array.from({ length: n }, (_, k) => el('float', String(k * (1 + int(500)) - int(100)))).join('');
    return el('TableModel', el('id', String(4096 + i)) + el('type', type) + el('cols', String(cols)) + el('rows', String(rows)) + maybe(0.6, () => el('ViewInTree', 'true')) +
      el('input_0_LinkId', String(pick(ids))) + el('input_1_LinkId', String(pick(ids))) + el('output_LinkId', String(pick(ids))) +
      el('input_0', axis(cols)) + el('input_1', axis(rows)) + el('output', Array.from({ length: rows * cols }, () => el('float', numText(randVal()))).join('')));
  });
  const drivers = Array.from({ length: 1 + int(3) }, (_, i) => {
    const nc = int(5), no = int(4), ni = int(4), ps = rnd() < 0.3 ? 1 + int(8) : 0;
    return el('DriverModel', el('id', String(8192 + i)) + el('numberOfConfigs', String(nc)) +
      el('configParams', Array.from({ length: nc }, (_, k) => el('DriverModelParam', el('name', 'P' + k) + el('value', numText(randVal())))).join('')) +
      el('numberOfOutputs', String(no)) + el('outputLinkIds', Array.from({ length: no }, () => el('unsignedShort', String(int(65536)))).join('')) +
      el('numberOfInputs', String(ni)) + el('inputLinkIds', Array.from({ length: ni }, () => el('unsignedShort', String(int(65536)))).join('')) +
      (ps ? el('privSize', String(ps)) + el('privData', Buffer.from(bytes(ps)).toString('base64')) : ''));
  });
  return (lastSimXml = '<ecu>' + el('DeviceDataInformationModel', el('ProductName', 'SIM-ECU') + el('ModelName', 'TEST') + el('Version', String(1 + int(99)))) +
    `<links>${links.join('')}</links><tables>${tables.join('')}</tables><drivers>${drivers.join('')}</drivers></ecu>`);
}
const realSetInterval = globalThis.setInterval, realClearInterval = globalThis.clearInterval;
globalThis.setInterval = () => ({}); globalThis.clearInterval = () => {};
const simSessions = [];
for (let i = 0; i < 25; i++) {
  const xml = simXml();
  const m = DeviceDataModel.fromXml(xml, null);
  let now = Date.UTC(2026, 10, 18, 12, 34, 56, 789) + int(1e9);
  const options = { uuid: 'SIM-' + i, fwVersion: '1.' + int(9), reportMs: 100, engineStopped: rnd() < 0.3 };
  const ecu = new SimEcu(m, { ...options, now: () => now });
  const replies = [];
  ecu.reply = (cls, cmd, p) => replies.push(hex([0x0f, cls, cmd, ...p]));
  const steps = [];
  const step = (what, fn) => { replies.length = 0; fn(); steps.push({ ...what, at: now, replies: [...replies] }); };
  const send = (f) => step({ send: frameHex(f) }, () => ecu.handle(f));
  const op = (name) => step({ op: name }, () => ecu[name]());
  const later = (ms) => { now += ms; };
  const tableIds = [...m.allTables.keys()], driverIds = [...m.allDrivers.keys()];

  send(sys.getEcuInfoRequest()); send(sys.getHashRequest(0)); send(sys.getHashRequest(1)); send(sys.pwLockGetStateRequest());
  for (const id of tableIds) send(tables.getTableRequest(id));
  for (const id of driverIds) send(drivers.getDriverRequest(id));
  send(tables.getTableRequest(9999)); send(drivers.getDriverRequest(9999)); send(tables.setTableRequest({ id: 9999, serialize: () => [] }));
  for (const id of tableIds.filter(() => rnd() < 0.7)) {
    const t = m.allTables.get(id);
    const blob = [t.type, int(2), t.rows, t.cols, ...(t.rows > 1 ? f32Bytes(Array.from({ length: t.rows }, oddF32)) : []),
      ...f32Bytes(Array.from({ length: t.cols }, oddF32)), ...f32Bytes(Array.from({ length: t.rows * t.cols }, oddF32))];
    send(tables.setTableRequest({ id, serialize: () => blob }));
    const elem = int(3), n = elem === 0 ? t.cols : elem === 1 ? t.rows : t.rows * t.cols;
    const offsets = Array.from({ length: 1 + int(4) }, () => int(n));
    send(tables.setTableDataRequest(id, elem, offsets, offsets.map(() => [oddF32()])));
    send(tables.storeTableRequest(id)); send(tables.getTableRequest(id));
  }
  for (const id of driverIds.filter(() => rnd() < 0.7)) {
    const d = m.allDrivers.get(id);
    const blob = [d.numberOfConfigs, d.numberOfOutputs, d.numberOfInputs, ...f32Bytes(Array.from({ length: d.numberOfConfigs }, oddF32)),
      ...Array.from({ length: d.numberOfOutputs + d.numberOfInputs }, () => le16(int(65536))).flat(), ...bytes(d.privSize)];
    send(drivers.setDriverRequest({ id, serialize: () => blob })); send(drivers.storeDriverRequest(id)); send(drivers.getDriverRequest(id));
  }
  send(sys.getHashRequest(1)); send(drivers.getCanReservedIdsRequest()); send(sys.factoryResetRequest());
  send(reporting.setStateRequest(true));
  for (let k = 0; k < 4; k++) { later(100 + int(5000)); op('report'); }
  send(trigger.setDbwDutyRequest(1, (rnd() - 0.3) * 200)); op('report');
  send(reporting.setStateRequest(false));

  if (rnd() < 0.7) op('seedDataLogging');
  send(datalog.isSupportedRequest()); send(datalog.getConfigRequest()); send(datalog.getLogsSummaryRequest());
  const chans = [...m.allDataLinks.keys()].filter(() => rnd() < 0.5);
  send(datalog.setConfigRequest(1 + int(100), rnd() < 0.5, chans));
  send(datalog.startRequest()); later(1000 + int(60000)); op('report'); send(datalog.setConfigRequest(10, false, []));
  send(datalog.stopRequest()); send(datalog.getLogsSummaryRequest());
  for (const id of [1, 2, 3, 77]) { send(datalog.getLogDetailRequest(id)); send(datalog.getLogRegionRequest(id, int(50), 1 + int(60))); }
  send(datalog.eraseLogRequest(1)); send(datalog.eraseLogRequest(1)); send(datalog.getLogsSummaryRequest());
  send(datalog.formatMemoryRequest()); send(datalog.getLogsSummaryRequest());
  send(trigger.triggerIsSupportedRequest()); send(trigger.triggerSetStateRequest(true, pick([[0], [1], [0, 1]])));
  for (let k = 0; k < 5; k++) op('triggerReport');
  send(trigger.triggerSetStateRequest(false, [])); send(faults.faultsGetInfoRequest());
  ecu.attach(null);
  simSessions.push({ xml, options, steps });
}
globalThis.setInterval = realSetInterval; globalThis.clearInterval = realClearInterval;
write('simulator.json', simSessions);

// ---------------------------------------------------------------- session: the connect sequence of the TypeScript app
// The TypeScript app model connects to its simulator over the real channel and connection code, with real timers. The
// vectors hold the session's own requests (classes 0, 1, 2 and 4, without the lifesign) and what the host ended up with.
// Scenarios: a first connect, a reconnect to an unchanged ECU, a reconnect after the ECU changed, a password-protected
// ECU, and an ECU with no matching definition.
const { AppModel } = await src('app-model.ts');
const { simSerial } = await src('ecu-sim.ts');
const sleep = (ms) => new Promise((r) => realSetTimeout(r, ms));
const realSetTimeout = globalThis.setTimeout;
const until = async (c, ms = 5000) => { const t0 = Date.now(); while (!c()) { if (Date.now() - t0 > ms) throw new Error('timeout'); await sleep(2); } };
const timing = { handshakeMs: 300, watchdogMs: 5000, holdMs: 200, awaitMs: 300 };
const sessionCases = [];
function ecuEdits(m, p) {
  const edits = [];
  for (const t of m.allTables.values()) if (rnd() < p) {
    const blob = [t.type, int(2), t.rows, t.cols, ...(t.rows > 1 ? f32Bytes(Array.from({ length: t.rows }, oddF32)) : []),
      ...f32Bytes(Array.from({ length: t.cols }, oddF32)), ...f32Bytes(Array.from({ length: t.rows * t.cols }, oddF32))];
    t.deserialize(Uint8Array.from(blob)); edits.push({ table: t.id, blob: hex(blob) });
  }
  for (const d of m.allDrivers.values()) if (rnd() < p) {
    const blob = [d.numberOfConfigs, d.numberOfOutputs, d.numberOfInputs, ...f32Bytes(Array.from({ length: d.numberOfConfigs }, oddF32)),
      ...Array.from({ length: d.numberOfOutputs + d.numberOfInputs }, () => le16(int(65536))).flat(), ...bytes(d.privSize)];
    d.deserialize(Uint8Array.from(blob)); edits.push({ driver: d.id, blob: hex(blob) });
  }
  return edits;
}
const hostState = (app) => {
  const m = app.model;
  return {
    load: app.load.kind,
    tables: m ? [...m.allTables.values()].map((t) => [t.id, hex(t.serialize())]) : [],
    drivers: m ? [...m.allDrivers.values()].map((d) => [d.id, hex(d.serialize())]) : [],
    uuid: m?.ecuUuid ?? null,
    password: m?.passwordProtectionState ? { locked: m.passwordProtectionState.locked, contact: m.passwordProtectionState.tunerContact } : null,
  };
};
for (let i = 0; i < 12; i++) {
  const xml = simXml();
  const ecuModel = DeviceDataModel.fromXml(xml, null);
  const kind = i % 4 === 3 ? 'password' : i % 6 === 5 ? 'noDefinition' : 'reconnect';
  const options = { uuid: 'SIM-' + i, fwVersion: '1.' + int(9), reportMs: 1e6, engineStopped: false };
  const ecu = new SimEcu(ecuModel, options);
  const password = kind === 'password' ? { locked: rnd() < 0.5, temporary: rnd() < 0.5, contact: anyText(int(20)).replace(/\u0000/g, '') } : null;
  if (password) {
    const reply = ecu.reply.bind(ecu);
    ecu.reply = (cls, cmd, p) => reply(cls, cmd, cls === 4 && cmd === 0 ? [...p, ...Buffer.from('PW\0')]
      : cls === 4 && cmd === 5 ? [0, password.locked ? 1 : 0, password.temporary ? 1 : 0, ...Buffer.from(password.contact)] : p);
  }
  const hostXml = kind === 'noDefinition' ? xml.replace(/<Version>(\d+)<\/Version>/, (_, v) => `<Version>${Number(v) + 100}</Version>`) : xml;
  let sent = [];
  const handle = ecu.handle.bind(ecu);
  ecu.handle = (f) => { if ([0, 1, 2, 4].includes(f.cls) && !(f.cls === 0 && f.cmd === 1)) sent.push(frameHex(f)); handle(f); };
  const store = { m: new Map(), getItem(k) { return this.m.get(k) ?? null; }, setItem(k, v) { this.m.set(k, v); } };
  const app = new AppModel({ serial: simSerial(ecu), defs: [{ name: 'sim.medef', xml: hostXml }], store, timing, lifesignMs: 1e6 });
  const phases = [];
  const settle = async () => {
    await until(() => app.load.kind === 'loaded' || app.load.kind === 'notFound');
    await sleep(30);
    phases.push({ sent, host: hostState(app) }); sent = [];
  };
  const before = ecuEdits(ecuModel, 0.6);
  await app.refreshPorts();
  await app.connect('USB 5349:4D00'); await settle();
  let between = [];
  if (kind === 'reconnect') {
    for (const p of [0, 0.4]) {
      app.disconnect(); await until(() => !app.isConnected); await sleep(20);
      between.push(ecuEdits(ecuModel, p)); app.load = { kind: 'idle' };
      await app.connect('USB 5349:4D00'); await settle();
    }
  }
  app.disconnect(); app.service.handler.stop(); ecu.attach(null);
  sessionCases.push({ kind, xml, hostXml, options, password, before, between, phases });
}
write('session.json', sessionCases);

// ---------------------------------------------------------------- live data: reports applied to the model's links
// The TypeScript handler gets report frames at set times; the vectors hold every link's value after each report (as
// float bits, so -0 and NaN survive) and each link's history at the end. One case runs past the 1200-sample history.
const { ProtocolServiceMessageHandler } = await src('message-handler.ts');
const { CHANNEL_FACTORY } = kinds;
const TICKS_AT_EPOCH = 621355968000000000n;
const liveCases = [];
for (let i = 0; i < 6; i++) {
  const m = DeviceDataModel.fromXml(simXml(), null);
  CHANNEL_FACTORY.create({ type: 0x0f, cls: 0, cmd: 2, payload: Uint8Array.from([0]) }); // reports as (id, float) pairs
  let ticks = 0n;
  const h = new ProtocolServiceMessageHandler({ setReportingState() {}, sendMessageFrame() {} },
    { defs: { getDeviceDataModel: () => null }, makeInfo: () => ({}), lifesignMs: 1e6, nowTicks: () => ticks });
  h.model = m;
  const ids = [...m.allDataLinks.keys()];
  let at = Date.UTC(2026, 10, 18, 9, 0, 0) + int(1e6);
  const steps = [];
  for (let k = 0, n = i === 0 ? 1300 : 40 + int(80); k < n; k++) {
    at += 1 + int(200);
    ticks = BigInt(at) * 10000n + TICKS_AT_EPOCH;
    const entries = Array.from({ length: int(ids.length + 3) }, () => (rnd() < 0.1 ? 3000 + int(100) : pick(ids)));
    const status = rnd() < 0.05 ? 1 : 0;
    const payload = [status, ...le16(entries.length), ...entries.flatMap((id) => [...le16(id), ...f32(oddF32())])];
    const frame = { type: 0x0f, cls: 0, cmd: 0, payload: Uint8Array.from(payload) };
    h.visitReceived(frame);
    steps.push({ at, frame: frameHex(frame), values: [...m.allDataLinks.values()].map((l) => hex(f32(l.value))) });
  }
  const histories = [...m.allDataLinks.values()].map((l) => ({
    id: l.id,
    at: l.historicalValues.map((v) => Number((v.ticks - TICKS_AT_EPOCH) / 10000n)),
    values: l.historicalValues.map((v) => hex(f32(v.value))),
  }));
  liveCases.push({ xml: lastSimXml, steps, histories });
}
write('live.json', liveCases);

// ---------------------------------------------------------------- faults: catalogue, stamps, records, freeze frames
// Pure functions of the TypeScript fault module over random inputs, and scripted fault-log sessions against its
// simulator with a seeded log.
{
  const F = faults;
  const codes = [...F.catalogueCodes().map((c) => c.code), 0, 100, 999, 65535, ...Array.from({ length: 20 }, () => int(65536))];
  const lookups = codes.map((code) => { const c = F.lookup(code); return { code, index: c.index, name: c.name, kind: c.kind, severity: c.severity, known: c.isKnown }; });
  const u32s = [0, 1, 59, 60, 1440, 0xffffffff, 2 ** 31, 4_000_000_000, 2_000_000_000, ...Array.from({ length: 40 }, () => int(2 ** 32))];
  const stamps = u32s.map((x) => ({ x, hours: hex(f32(F.hours(x))), rtc: (() => { try { return F.rtcIso(x); } catch { return 'error'; } })() }));
  const record = (type, body) => ({ ordinal: 0, magic: rnd() < 0.8 ? 0xfa17 : int(65536), type, catalogueVersion: 1, seq: 0, code: pick(codes), count: 0,
    lifetime: 0, hoursX100: int(2 ** 32), rtc: 0, bodyLength: body.length, slotSize: 64, body: Uint8Array.from(body) });
  const records = Array.from({ length: 80 }, () => {
    const type = int(6);
    const body = type === 2 && rnd() < 0.7 ? [...le32(int(2 ** 32)), ...le16(int(4)), ...bytes(24 * int(4) + int(30))] : bytes(int(12));
    const r = record(type, body);
    return { type, magic: r.magic, body: hex(body), valid: F.recordIsValid(r), oldMode: F.configOldMode(r), newMode: F.configNewMode(r),
      checkpointHours: F.checkpointHoursX100(r), entries: F.checkpointEntries(r) };
  });
  const frames = Array.from({ length: 120 }, () => {
    const layout = Array.from({ length: int(8) }, () => { const e = F.layoutEntry(int(3000), pick([0, 1, 2, 3, 4, 4, 4, 8])); if (rnd() < 0.4) e.type = int(6); return e; });
    const body = Uint8Array.from(bytes(int(30)));
    const values = F.decodeFrame(layout, body).map((v) => [v.linkId, hex(f32(v.value))]);
    return { layout: layout.map((e) => [e.linkId, e.size, e.type]), body: hex(body), values };
  });
  const actives = Array.from({ length: 60 }, () => {
    const v = () => pick([0, -1, NaN, Infinity, 2 ** 31, 2 ** 24 - 1, int(2 ** 24), Math.fround(int(2 ** 30)), 0.5, 1, 3.9]);
    const a = v(), b = v(), c = v();
    return { values: [a, b, c].map((x) => hex(f32(x))), active: [...F.activeIndexes(Math.fround(a), Math.fround(b), Math.fround(c))].sort((x, y) => x - y) };
  });
  write('faults.json', [{ lookups, stamps, records, frames, actives }]);
}
{
  globalThis.setInterval = () => ({}); globalThis.clearInterval = () => {};
  const sessions = [];
  for (let i = 0; i < 8; i++) {
    const base = simXml();
    const have = new Set([...base.matchAll(/<DataLinkModel><id>(\d+)<\/id>/g)].map((x) => Number(x[1])));
    const xml = base.replace('<links>', '<links>' + [1, 2, 6, 14, 18, 924, 2339, 2340, 2341].filter((id) => !have.has(id) && rnd() < 0.8)
      .map((id) => `<DataLinkModel><id>${id}</id></DataLinkModel>`).join(''));
    const m = DeviceDataModel.fromXml(xml, null);
    const now = Date.UTC(2026, 10, 18, 12, 0, 0) + int(1e9);
    const options = { uuid: 'SIM-F' + i, fwVersion: '1.0', reportMs: 100, engineStopped: rnd() < 0.5 };
    const ecu = new SimEcu(m, { ...options, now: () => now });
    const seeded = rnd() < 0.85;
    if (seeded) ecu.seedFaults();
    const replies = [];
    ecu.reply = (cls, cmd, p) => replies.push(hex([0x0f, cls, cmd, ...p]));
    const steps = [];
    const send = (f) => { replies.length = 0; ecu.handle(f); steps.push({ send: frameHex(f), replies: [...replies] }); };
    const report = () => { replies.length = 0; ecu.report(); steps.push({ op: 'report', replies: [...replies] }); };
    send(faults.faultsGetInfoRequest()); send(faults.faultsGetFrameLayoutRequest(0, 200)); send(faults.faultsGetFrameLayoutRequest(3, 2));
    send(faults.faultsGetSummaryRequest(0, 40)); send(faults.faultsGetSummaryRequest(2, 1));
    for (let o = 0; o < 8; o++) send(faults.faultsGetOccurrenceRequest(o));
    report(); send(faults.faultsClearRequest()); send(faults.faultsGetSummaryRequest(0, 40)); send(faults.faultsGetOccurrenceRequest(0));
    send(faults.faultsEraseLogRequest()); send(faults.faultsGetInfoRequest()); report();
    send({ type: 0, cls: 9, cmd: 7, payload: new Uint8Array(0) });
    sessions.push({ xml, options, seeded, now, steps });
  }
  globalThis.setInterval = realSetInterval; globalThis.clearInterval = realClearInterval;
  write('sim_faults.json', sessions);
}

// ---------------------------------------------------------------- units: raw-value conversions
{
  const U = await src('units.ts');
  const units = Object.keys(U.UNITS);
  const values = [0, -0, 1, -1, 0.5, 100, 4095, 32767, 64999, 65000, 65001, 65535, 70000, -70000, 1e30, -1e30, NaN, Infinity, -Infinity,
    ...Array.from({ length: 30 }, () => oddF32())];
  const cases = [];
  for (const unit of units) for (const v of values) for (const check of [false, true]) {
    cases.push({ unit, v: hex(f32(v)), check, from: hex(f32(U.fromRaw(unit, v, check))), to: hex(f32(U.toRaw(unit, v, check))) });
  }
  write('units.json', cases);
}

// ---------------------------------------------------------------- custom CAN: bit packing, ids, the config blob, checks
{
  const C = await src('custom-can.ts');
  const { DriverModelParam, DriverModel } = await src('driver.ts');
  const bits = Array.from({ length: 400 }, () => {
    const frame = Uint8Array.from(bytes(8));
    const start = rnd() < 0.9 ? int(64) : pick([-1, 64, 70]), len = rnd() < 0.9 ? 1 + int(64) : pick([0, 65]);
    const be = rnd() < 0.5;
    const value = (BigInt(int(2 ** 32)) << 32n) | BigInt(int(2 ** 32));
    const packed = Uint8Array.from(frame); C.pack(packed, start, len, be, value);
    const x = C.extract(frame, start, len, be);
    return { frame: hex(frame), start, len, be, valid: C.spanValid(start, len, be), extract: x.toString(16), value: value.toString(16),
      packed: hex(packed), signed: C.signExtend(x, len).toString(16) };
  });
  const idTexts = ['', ' ', '0x7FF', '7ff', '&H1FFFFFFF', '0X20000000', '1FFFFFFF', '123456789', ' 0x12 ', '0x', 'xyz', '-1', '+1', '\t7e8\n', '0x 12', '00000000',
    ...Array.from({ length: 30 }, () => (rnd() < 0.5 ? '0x' : '') + int(2 ** 30).toString(16))];
  const ids = idTexts.map((t) => ({ text: t, id: C.tryParseCanId(t), ext: C.tryParseCanId(t) === null ? null : C.isExtendedId(C.tryParseCanId(t)), fmt: C.tryParseCanId(t) === null ? null : C.formatCanId(C.tryParseCanId(t)) }));
  const randConfig = () => {
    const c = new C.CustomCanConfig();
    for (const m of c.rxMessages) {
      Object.assign(m, { enabled: rnd() < 0.5, canId: rnd() < 0.8 ? int(0x800) : int(2 ** 32), extended: rnd() < 0.3, bigEndian: rnd() < 0.5, muxEnabled: rnd() < 0.3,
        muxStartBit: int(70), muxBitLength: int(40), muxMatch: int(2 ** 32) });
      for (const sg of m.signals) Object.assign(sg, { enabled: rnd() < 0.5, format: int(4), startBit: int(70), bitLength: int(70), mult: pick([1, 0, 0.1, NaN, Infinity, oddF32()]),
        offset: oddF32(), timeoutMs: int(65536), fallback: oddF32(), dstLinkId: pick([0, 1, 2, 3, 999, int(65536)]) });
    }
    for (const m of c.txMessages) {
      Object.assign(m, { enabled: rnd() < 0.5, canId: rnd() < 0.8 ? int(0x800) : int(2 ** 32), extended: rnd() < 0.3, mode: int(4), freqHz: pick([0, 1, 10, 1000, 1001, int(65536)]),
        triggerLinkId: pick([0, 1, 999]) });
      for (const sg of m.signals) Object.assign(sg, { enabled: rnd() < 0.5, bigEndian: rnd() < 0.5, signed: rnd() < 0.5, startBit: int(70), bitLength: int(70),
        mult: pick([1, 0, -2.5, NaN]), offset: oddF32(), srcLinkId: pick([0, 1, 999]), constValue: oddF32() });
    }
    return c;
  };
  const linkSet = new Set([1, 2, 3]);
  const reserved = new Set([0x700, 0x340, 0x1ba]);
  const msgs = (v) => ({ errors: v.errors, warnings: v.warnings });
  const configs = Array.from({ length: 40 }, () => {
    const c = randConfig();
    const blob = c.encode();
    const v = C.validate(c, (id) => linkSet.has(id), rnd() < 0.5 ? reserved : null);
    const mutated = Uint8Array.from(blob); for (let k = 0; k < 20; k++) mutated[4 + int(C.BLOB_SIZE - 4)] = int(256); if (rnd() < 0.15) mutated[0] = int(256);
    const d = C.CustomCanConfig.decode(mutated);
    return { blob: hex(blob), rx: v.rx.map(msgs), tx: v.tx.map(msgs), mutated: hex(mutated), wasReset: d.wasReset, reencoded: hex(d.encode()) };
  });
  const reservedIds = Array.from({ length: 20 }, () => {
    const d = new DriverModel();
    const names = ['Pri. Stream Selection', 'Sec. Stream Selection', 'Other'];
    const params = Array.from({ length: int(4) }, () => { const p = new DriverModelParam(); p.name = pick(names); p.value = pick([0, 1, 2, 3, 4, 5, 6, 2.7, -1, NaN]); return p; });
    d.numberOfConfigs = params.length; d.setConfigParams(params);
    return { params: params.map((p) => [p.name, hex(f32(p.value))]), ids: C.getForCanSettings(d) };
  });
  write('custom_can.json', [{ bits, ids, configs, reservedIds }]);
}

// ---------------------------------------------------------------- simulator: CAN ids reserved by the CAN settings driver
{
  globalThis.setInterval = () => ({}); globalThis.clearInterval = () => {};
  const cases = [];
  for (let i = 0; i < 12; i++) {
    const params = Array.from({ length: 1 + int(4) }, () => el('DriverModelParam', el('name', pick(['Pri. Stream Selection', 'Sec. Stream Selection', 'Baud'])) +
      el('value', String(pick([0, 1, 2, 3, 4, 5, 6, 2.5])))));
    const xml = simXml().replace('<drivers>', '<drivers>' + el('DriverModel', el('id', '8224') + el('numberOfConfigs', String(params.length)) +
      el('configParams', params.join('')) + el('numberOfOutputs', '0') + el('numberOfInputs', '0')));
    const ecu = new SimEcu(DeviceDataModel.fromXml(xml, null), {});
    const replies = [];
    ecu.reply = (cls, cmd, p) => replies.push(hex([0x0f, cls, cmd, ...p]));
    ecu.handle(drivers.getCanReservedIdsRequest());
    cases.push({ xml, replies });
  }
  globalThis.setInterval = realSetInterval; globalThis.clearInterval = realClearInterval;
  write('sim_can.json', cases);
}

// ---------------------------------------------------------------- calibration import: analysis and applying a selection
// A target definition and a source made from it by renaming, renumbering, reshaping, reordering and dropping items.
// The vectors hold the TypeScript analysis, which candidates were then selected, the target after applying them, and
// the source file applied onto the target's definition (U10a F01).
{
  const { CalibrationImportReviewService } = await src('import-review.ts');
  const clone = (x) => JSON.parse(JSON.stringify(x));
  const SHAPES = { T1x16: [1, 16], T1x32: [1, 32], T16x16: [16, 16], T1x2: [1, 2], T8x8: [8, 8] };
  const CATS = ['Fuel', 'Ignition', 'Boost', 'Idle'];
  const PARAM_NAMES = ['Mode', 'Gain', 'Offset', 'Max Duty', 'Min Duty', 'Rate', 'Pin', 'Threshold', 'Delay', 'Enable'];
  const vals = (n) => Array.from({ length: n }, () => Math.fround(randVal()));
  const axis = (n) => Array.from({ length: n }, (_, k) => Math.fround(k * (1 + int(50)) - int(20)));
  function baseSpec() {
    const links = Array.from({ length: 6 + int(6) }, (_, i) => ({ id: 10 + i, name: 'Link ' + i }));
    const tables = Array.from({ length: 2 + int(6) }, (_, i) => {
      const type = pick(Object.keys(SHAPES)); const [rows, cols] = SHAPES[type];
      return { id: 4096 + i, name: 'Table ' + i, category: pick(CATS), type, rows, cols, in0: pick(links).id, in1: pick(links).id, out: pick(links).id,
        enabled: rnd() < 0.5, x: axis(cols), y: axis(rows), z: vals(rows * cols) };
    });
    const drivers = Array.from({ length: 1 + int(4) }, (_, i) => {
      const id = i === 0 && rnd() < 0.4 ? 8198 : 8192 + i;
      const names = [...PARAM_NAMES].sort(() => rnd() - 0.5).slice(0, 2 + int(5));
      if (id === 8198) names.push('CL Min Duty', 'CL Max Duty');
      const params = names.map((name) => { const combo = rnd() < 0.3; return { name, displayName: rnd() < 0.3 ? name + ' (shown)' : null, type: combo ? 'ComboBox' : 'InputBox',
        options: combo ? [[0, 'Off'], [1, 'On']] : null, value: combo ? int(2) : Math.fround(randVal()) }; });
      const ni = int(4), no = int(4);
      return { id, name: 'Driver ' + i, category: pick(CATS), params, editIn: rnd() < 0.6, editOut: rnd() < 0.6,
        inIds: Array.from({ length: ni }, () => pick(links).id), outIds: Array.from({ length: no }, () => pick(links).id),
        inNames: Array.from({ length: ni }, (_, k) => 'In ' + k), outNames: Array.from({ length: no }, (_, k) => 'Out ' + k) };
    });
    return { version: '10', links, tables, drivers };
  }
  function mutate(t) {
    const s = clone(t);
    if (rnd() < 0.4) s.version = '11';
    for (const l of s.links) { if (rnd() < 0.15) l.id += 100; if (rnd() < 0.1) l.name += ' X'; }
    const linkIds = s.links.map((l) => l.id);
    s.tables = s.tables.filter(() => rnd() > 0.1);
    for (const tb of s.tables) {
      if (rnd() < 0.2) tb.id += 50;
      if (rnd() < 0.1) tb.name += ' renamed';
      if (rnd() < 0.2) tb.enabled = !tb.enabled;
      for (const k of ['in0', 'in1', 'out']) if (!linkIds.includes(tb[k])) tb[k] = linkIds[0];
      const reshape = rnd();
      if (reshape < 0.1 && tb.type === 'T1x2') Object.assign(tb, { type: 'T1x16', rows: 1, cols: 16, x: axis(16), y: axis(1), z: vals(16) });
      else if (reshape < 0.2 && tb.type === 'T1x16') Object.assign(tb, { type: 'T1x2', rows: 1, cols: 2, x: axis(2), y: axis(1), z: vals(2) });
      else if (reshape < 0.3 && tb.type === 'T8x8') Object.assign(tb, { type: 'T16x16', rows: 16, cols: 16, x: axis(16), y: axis(16), z: vals(256) });
      else if (reshape < 0.35) Object.assign(tb, { type: 'T1x32', rows: 1, cols: 32, x: axis(32), y: axis(1), z: vals(32) });
      tb.z = tb.z.map((v) => (rnd() < 0.3 ? Math.fround(randVal()) : v));
      if (rnd() < 0.2) tb.x = tb.x.map((v) => Math.fround(v + 1));
    }
    s.drivers = s.drivers.filter(() => rnd() > 0.1);
    for (const d of s.drivers) {
      if (rnd() < 0.15) d.id += 20;
      if (d.id === 8198 && rnd() < 0.7) d.params = d.params.filter((p) => !p.name.startsWith('CL ')).concat([{ name: 'PWM Min Duty', displayName: null, type: 'InputBox', options: null, value: Math.fround(randVal()) },
        { name: 'PWM Max Duty', displayName: null, type: 'InputBox', options: null, value: Math.fround(randVal()) }]);
      if (rnd() < 0.3) d.params.reverse();
      d.params = d.params.filter(() => rnd() > 0.1);
      for (const p of d.params) {
        if (rnd() < 0.4) p.value = p.type === 'ComboBox' ? int(2) : Math.fround(randVal());
        if (rnd() < 0.05) p.name = ' ' + p.name.toUpperCase() + '  ';
        if (rnd() < 0.05) p.type = p.type === 'ComboBox' ? 'InputBox' : 'ComboBox';
        if (p.type === 'ComboBox' && rnd() < 0.1) p.options = [[0, 'Off'], [2, 'On']];
      }
      d.inIds = d.inIds.map((id) => (rnd() < 0.3 ? pick(s.links).id + (rnd() < 0.2 ? 500 : 0) : id));
      d.outIds = d.outIds.map((id) => (rnd() < 0.3 ? pick(s.links).id : id));
    }
    return s;
  }
  const specXml = (sp) => '<ecu>' + el('DeviceDataInformationModel', el('ProductName', 'SIM-ECU') + el('ModelName', 'TEST') + el('Version', sp.version)) +
    `<links>${sp.links.map((l) => el('DataLinkModel', el('id', String(l.id)) + el('name', l.name))).join('')}</links>` +
    `<tables>${sp.tables.map((t) => el('TableModel', el('id', String(t.id)) + el('name', t.name) + el('category', t.category) + el('enabled', String(t.enabled)) +
      el('type', t.type) + el('cols', String(t.cols)) + el('rows', String(t.rows)) + el('input_0_LinkId', String(t.in0)) + el('input_1_LinkId', String(t.in1)) +
      el('output_LinkId', String(t.out)) + el('input_0', t.x.map((v) => el('float', String(v))).join('')) + el('input_1', t.y.map((v) => el('float', String(v))).join('')) +
      el('output', t.z.map((v) => el('float', String(v))).join('')))).join('')}</tables>` +
    `<drivers>${sp.drivers.map((d) => el('DriverModel', el('id', String(d.id)) + el('name', d.name) + el('category', d.category) + el('numberOfConfigs', String(d.params.length)) +
      el('configParams', d.params.map((p) => el('DriverModelParam', el('name', p.name) + (p.displayName ? el('DisplayName', p.displayName) : '') + el('type', p.type) +
        el('value', String(p.value)) + (p.options ? el('options', p.options.map(([id, n]) => el('comboBoxOption', el('id', String(id)) + el('name', n))).join('')) : ''))).join('')) +
      el('numberOfOutputs', String(d.outIds.length)) + el('outputLinkIds', d.outIds.map((v) => el('unsignedShort', String(v))).join('')) +
      el('editableOutputs', String(d.editOut)) + el('outputNames', d.outNames.map((n) => el('string', n)).join('')) +
      el('editableInputs', String(d.editIn)) + el('inputNames', d.inNames.map((n) => el('string', n)).join('')) +
      el('numberOfInputs', String(d.inIds.length)) + el('inputLinkIds', d.inIds.map((v) => el('unsignedShort', String(v))).join('')))).join('')}</drivers></ecu>`;
  const svc = new CalibrationImportReviewService();
  const fbits = (v) => (v === null ? null : hex(f32(v)));
  const state = (m) => ({ tables: [...m.allTables.values()].map((t) => [t.id, hex(t.serialize())]), drivers: [...m.allDrivers.values()].map((d) => [d.id, hex(d.serialize())]) });
  const cases = [];
  for (let i = 0; i < 60; i++) {
    const tSpec = baseSpec(), sSpec = mutate(tSpec);
    const targetXml = specXml(tSpec), sourceXml = specXml(sSpec);
    const target = DeviceDataModel.fromXml(targetXml, null), source = DeviceDataModel.fromXml(sourceXml, null);
    const a = svc.analyse(target, source, null);
    const toggles = a.candidates.map((c, k) => (c.importable && rnd() < 0.2 ? k : -1)).filter((k) => k >= 0);
    for (const k of toggles) a.candidates[k].selected = !a.candidates[k].selected;
    const fresh = DeviceDataModel.fromXml(targetXml, null);
    svc.applySelected(fresh, source, a.candidates);
    // F01: the source file's values applied onto a fresh target definition, item by item; errors leave an item as it was
    const onto = DeviceDataModel.fromXml(targetXml, null);
    for (const [id, t] of source.allTables) { try { const x = onto.allTables.get(id); if (!x) throw new Error('KeyNotFound'); x.deserialize(t.serialize()); } catch { /* kept */ } }
    for (const [id, d] of source.allDrivers) {
      const x = onto.allDrivers.get(id);
      if (!x || x.numberOfConfigs !== d.numberOfConfigs || x.numberOfInputs !== d.numberOfInputs || x.numberOfOutputs !== d.numberOfOutputs || x.privSize !== d.privSize) continue;
      try { x.deserialize(d.serialize()); } catch { /* kept */ }
    }
    cases.push({
      targetXml, sourceXml, defMismatch: a.hasDefMismatch,
      candidates: a.candidates.map((c) => ({ kind: c.kind, matchType: c.matchType, importable: c.importable, selected: c.selected, safeDefault: c.safeDefault,
        changed: c.isChanged, targetId: c.targetModelId, sourceId: c.sourceModelId, targetIndex: c.targetIndex, sourceIndex: c.sourceIndex,
        delta: fbits(c.valueDelta), cells: c.changedCellCount, axis: c.changedAxisCount, minDelta: fbits(c.minCellDelta), maxDelta: fbits(c.maxCellDelta),
        enabledChanged: c.enabledChanged, reason: c.reason })),
      applied: state(fresh), onto: state(onto),
    });
  }
  write('calibration_import.json', cases);
}

// ---------------------------------------------------------------- onboard logs: download in chunks and save as CSV
// The TypeScript simulator holds seeded logs; each is fetched the way the TypeScript model does (detail, then regions
// of at most 512 bytes) and saved with its LogModel. Plus .NET "G" formatting of floats and doubles.
{
  const NF = await src('netfmt.ts');
  const { LogModel, entryCsv } = await src('datalogging.ts');
  const { entrySize } = datalog;
  const numbers = [0, -0, 1, -1, 0.1, 1 / 3, 123456789, 1e15, 1e16, 1e-5, 1e-4, 12345.678, 0.5, 2.5, 1e300, 5e-324, NaN, Infinity, -Infinity,
    ...Array.from({ length: 60 }, () => (rnd() - 0.5) * 10 ** (int(30) - 15))];
  const general = numbers.map((v) => ({ v: hex([...new Uint8Array(Float64Array.of(v).buffer)]), f: NF.formatGeneral(Math.fround(v)), d: NF.formatGeneral(v, false) }));
  globalThis.setInterval = () => ({}); globalThis.clearInterval = () => {};
  const sessions = [];
  for (let i = 0; i < 6; i++) {
    const xml = simXml();
    const m = DeviceDataModel.fromXml(xml, null);
    const now = Date.UTC(2026, 10, 18, 12, 0, 0) + int(1e9);
    const ecu = new SimEcu(m, { now: () => now });
    ecu.seedDataLogging();
    const sent = []; let reply = null;
    ecu.reply = (cls, cmd, p) => { reply = { type: 0x0f, cls, cmd, payload: Uint8Array.from(p) }; };
    const ask = (f) => { sent.push(frameHex(f)); reply = null; ecu.handle(f); return reply ? kinds.CHANNEL_FACTORY.create(reply) : null; };
    const summary = ask(datalog.getLogsSummaryRequest());
    const logs = [];
    for (const s of summary.logsSummaries) {
      const log = new LogModel(m, s.timestamp, s.id, s.durationSeconds, s.numOfChannels, s.numEntries);
      const detail = ask(datalog.getLogDetailRequest(log.id));
      log.updateChannels(detail.chanIds);
      const size = entrySize(log.numChannels);
      for (;;) {
        const chunk = Math.min(log.numEntries - log.entries.length, Math.trunc(512 / size));
        if (chunk === 0) break;
        log.addEntries(ask(datalog.getLogRegionRequest(log.id, log.entries.length, chunk >>> 0)).entries);
      }
      let text = '';
      const ok = log.save('logs/x.csv', { createDirectory() {}, createFile() { return { write: (t) => { text += t; }, flush() {}, close() {} }; } });
      logs.push({ id: log.id, csv: ok ? text : null });
    }
    sessions.push({ xml, now, sent, logs });
  }
  globalThis.setInterval = realSetInterval; globalThis.clearInterval = realClearInterval;
  write('onboard_logs.json', [{ general, sessions }]);
}

// ---------------------------------------------------------------- DBC files and .NET number parsing
{
  const { parseDbc } = await src('dbc.ts');
  const NF = await src('netfmt.ts');
  const numTexts = ['0', '1', '-1', '+2', ' 3 ', '1.5', '.5', '5.', '1e3', '1E-3', '-1.5e+2', '1,000', '1,000.5', ',5', '1e', 'e5', '', ' ', 'abc', '1.2.3',
    'Infinity', '-Infinity', 'NaN', ' NaN ', '1e400', '-1e400', '3.5e38', '3.4028236e38', '1e-50', '0x10', '00012', '1\0', '1\0\0', '\t7\n', '1 000',
    ...Array.from({ length: 30 }, () => String((rnd() - 0.5) * 10 ** (int(20) - 10)))];
  const tryIt = (f) => { try { const v = f(); return hex([...new Uint8Array(Float64Array.of(v).buffer)]); } catch { return 'error'; } };
  const numbers = numTexts.map((t) => ({ t, d: tryIt(() => NF.parseDouble(t)), f: tryIt(() => NF.parseSingle(t)) }));
  const ident = () => pick(['A', 'Eng', 'rpm_1', 'Throttle', 'X_y', 'Sig', 'S' + int(99), 'Ünïcode', 'Msg' + int(9)]);
  const num = () => pick(['0', '1', '0.1', '-40', '1e-3', '3.5', '255', '-1.25E+2', '65535', rnd() < 0.05 ? '1..2' : '10']);
  function dbcText() {
    const L = ['VERSION ""', '', 'NS_ :', '\tNS_DESC_', '\tCM_', '\tBA_DEF_', '', 'BS_:', '', 'BU_: ECU DASH'];
    const msgs = [];
    for (let i = 0; i < 1 + int(5); i++) {
      const id = rnd() < 0.2 ? (0x80000000 + int(0x1fffffff)) : int(0x800);
      const name = ident() + i;
      msgs.push({ id, name });
      L.push(`BO_ ${id} ${name}: ${pick([8, 4, 0])} ${pick(['ECU', 'DASH', 'Vector__XXX'])}`);
      if (rnd() < 0.1) L.push(`BO_ ${id} Dup${i}: 8 ECU`);
      for (let k = 0; k < int(6); k++) {
        const mux = pick(['', '', '', 'M', 'm0', 'm1', 'm12']);
        L.push(` SG_ ${ident()}${k} ${mux} : ${int(70)}|${int(70)}@${pick(['0', '1'])}${pick(['+', '-'])} (${num()},${num()}) [${num()}|${num()}] "${pick(['', 'rpm', 'kPa', '°C', 'a b'])}" ${pick(['ECU', 'DASH,ECU', 'Vector__XXX', 'A B'])}`);
      }
      L.push('');
    }
    const any = () => pick(msgs);
    if (rnd() < 0.7) L.push(`BA_DEF_ BO_ "GenMsgCycleTime" INT ${pick(['0 0', '0 1000', '-5 5'])};`);
    if (rnd() < 0.5) L.push(`BA_DEF_ BO_ "GenMsgSendType" ENUM "Cyclic","Event", "IfActive";`);
    if (rnd() < 0.5) L.push(`BA_DEF_ SG_ "GenSigStartValue" ${pick(['FLOAT 0 100', 'FLOAT 0 0', 'INT 0 10', 'HEX 0 255', 'STRING'])};`);
    if (rnd() < 0.3) L.push('BA_DEF_ "BusType" STRING ;');
    if (rnd() < 0.6) L.push(`BA_DEF_DEF_ "GenMsgCycleTime" ${pick(['100', '0', '"x"', '5000'])};`);
    if (rnd() < 0.4) L.push(`BA_DEF_DEF_ "GenMsgSendType" ${pick(['"Event"', '1', '"Nope"', '7'])};`);
    if (rnd() < 0.4) L.push(`BA_DEF_DEF_ "GenSigStartValue" ${pick(['5', '2.5', '"s"', '300'])};`);
    for (let k = 0; k < int(4); k++) L.push(`BA_ "GenMsgCycleTime" BO_ ${any().id} ${pick(['20', '2000', '-1', '"t"'])};`);
    if (rnd() < 0.4) L.push(`BA_ "GenMsgSendType" BO_ ${any().id} ${pick(['0', '2', '5', '"Event"'])};`);
    if (rnd() < 0.4) L.push(`BA_ "GenSigStartValue" SG_ ${any().id} ${ident()}0 ${pick(['7', '1.5', '"q"'])};`);
    if (rnd() < 0.3) L.push('BA_ "BusType" "CAN";');
    if (rnd() < 0.5) L.push(`SIG_VALTYPE_ ${any().id} ${ident()}${int(3)} : ${int(4)};`);
    if (rnd() < 0.4) L.push(`CM_ BO_ ${any().id} "A comment`, 'over two lines";');
    if (rnd() < 0.3) L.push(`CM_ SG_ ${any().id} Sig1 "x";`);
    if (rnd() < 0.3) L.push(`VAL_ ${any().id} Sig1 0 "Off" 1 "On" ;`);
    if (rnd() < 0.2) L.push(`VAL_ ${pick(['99999999999', '12'])} Sig1 0 "Off" ;`);
    if (rnd() < 0.2) L.push(`EV_ Env1: ${int(3)} [${num()}|${num()}] "u" ${num()} 1 DUMMY_NODE_VECTOR${pick(['', '800'])}${int(4)} ECU;`);
    if (rnd() < 0.1) L.push('ENVVAR_DATA_ Env1: 4;');
    if (rnd() < 0.1) L.push(`BO_ ${pick(['99999999999', '12'])} Big: 8 ECU`);
    return L.join(pick(['\r\n', '\n', '\r\n'])) + (rnd() < 0.5 ? '\r\n' : '');
  }
  const f64 = (v) => hex([...new Uint8Array(Float64Array.of(v).buffer)]);
  const propJson = (p) => ({ type: p.definition.dataType, integer: p.integer, hex: p.hex, float: p.float === null ? null : f64(p.float), string: p.string, enumValue: p.enumValue });
  const props = (m) => [...m.entries()].map(([k, v]) => [k, propJson(v)]);
  const files = Array.from({ length: 150 }, () => {
    const text = dbcText();
    try {
      const d = parseDbc(text);
      return { text, messages: d.messages.map((m) => ({ id: m.id, ext: m.isExtId, name: m.name, dlc: m.dlc, tx: m.transmitter, props: props(m.customProperties),
        signals: m.signals.map((g) => ({ name: g.name, mux: g.multiplexing, start: g.startBit, len: g.length, order: g.byteOrder, type: g.valueType, isInt: g.isInteger,
          factor: f64(g.factor), offset: f64(g.offset), min: f64(g.minimum), max: f64(g.maximum), unit: g.unit, rx: g.receiver, props: props(g.customProperties) })) })) };
    } catch { return { text, error: true }; }
  });
  write('dbc.json', [{ numbers, files }]);
}

copyFileSync(resolve(me360, 'test/u01-fuzz.json'), resolve(out, 'framing_fuzz.json'));
console.log(`requests ${requests.length}, replies ${replies.length}, reporting ${reportingSeq.length}, recognition ${recognition.length}, device files ${deviceFiles.length} (${deviceFiles.filter((d) => d.error).length} rejected), calibration files ${calibrationFiles.length}, simulator sessions ${simSessions.length}, session cases ${sessionCases.length}, live cases ${liveCases.length} → ${out}`);
