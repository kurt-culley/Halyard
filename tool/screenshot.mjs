// Screenshots of the web build for reviews: serve app/build/web, then run this with Node 22.
// Headless Chrome over the DevTools protocol: open a URL, run optional steps, save screenshots.
// usage: node shot.mjs <url> <out.png> [steps.json]
// steps: [{wait:ms} | {click:[x,y]} | {right:[x,y]} | {drag:[[x,y],[x,y]]} | {shot:"file.png"} | {files:[path...]} | {type:"text"} | {key:"Enter"}]
import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
const [url, out, stepsFile] = process.argv.slice(2);
const steps = stepsFile ? JSON.parse(readFileSync(stepsFile, 'utf8')) : [{ wait: 8000 }, { shot: out }];
const chrome = spawn(process.env.CHROME_EXECUTABLE ?? 'google-chrome', ['--headless=new', '--disable-gpu', '--remote-debugging-port=9333', '--window-size=1280,800', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws;
for (let i = 0; i < 50 && !ws; i++) {
  await sleep(200);
  try {
    const list = await (await fetch('http://127.0.0.1:9333/json')).json();
    const page = list.find((t) => t.type === 'page');
    if (page) ws = new WebSocket(page.webSocketDebuggerUrl);
  } catch {}
}
await new Promise((r) => ws.addEventListener('open', r));
let id = 0; const pending = new Map(); const handlers = [];
ws.addEventListener('message', (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } else handlers.forEach((h) => h(m)); });
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await send('Page.enable'); await send('Runtime.enable'); await send('DOM.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 800, deviceScaleFactor: 1, mobile: false });
handlers.push((m) => { if (m.method === 'Runtime.exceptionThrown') console.error('page error:', m.params.exceptionDetails.exception?.description ?? m.params.exceptionDetails.text); });
let chooser = null;
await send('Page.setInterceptFileChooserDialog', { enabled: true });
handlers.push((m) => { if (m.method === 'Page.fileChooserOpened') chooser = m.params; });
await send('Page.navigate', { url });
for (const s of steps) {
  if (s.wait) await sleep(s.wait);
  if (s.click) {
    const [x, y] = s.click;
    for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
  }
  if (s.right) {
    const [x, y] = s.right;
    for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) await send('Input.dispatchMouseEvent', { type, x, y, button: 'right', buttons: type === 'mousePressed' ? 2 : 0, clickCount: 1 });
  }
  if (s.drag) {
    const [[x1, y1], [x2, y2]] = s.drag;
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: x1, y: y1 });
    await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: x1, y: y1, button: 'left', buttons: 1, clickCount: 1 });
    for (let k = 1; k <= 10; k++) await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: x1 + (x2 - x1) * k / 10, y: y1 + (y2 - y1) * k / 10, button: 'left', buttons: 1 });
    await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: x2, y: y2, button: 'left', buttons: 0, clickCount: 1 });
  }
  if (s.type) await send('Input.insertText', { text: s.type });
  if (s.key) {
    const one = s.key.length === 1;
    const code = one ? `Key${s.key.toUpperCase()}` : s.key;
    const vk = s.key === 'Enter' ? 13 : one ? s.key.toUpperCase().charCodeAt(0) : 0;
    for (let n = 0; n < (s.times ?? 1); n++) for (const type of ['keyDown', 'keyUp']) await send('Input.dispatchKeyEvent', { type, key: s.key, code, windowsVirtualKeyCode: vk, text: type === 'keyDown' ? (s.key === 'Enter' ? '\r' : one ? s.key : undefined) : undefined });
  }
  if (s.files) { for (let i = 0; i < 30 && !chooser; i++) await sleep(100); if (chooser) await send('DOM.setFileInputFiles', { files: s.files, backendNodeId: chooser.backendNodeId }); chooser = null; }
  if (s.shot) { const r = await send('Page.captureScreenshot', { format: 'png' }); writeFileSync(s.shot, Buffer.from(r.result.data, 'base64')); console.log('saved', s.shot); }
}
ws.close(); chrome.kill();
