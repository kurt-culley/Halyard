@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:halyard/platform/serial_web.dart';

/// A stand-in for `navigator.serial` with one granted port, built from real streams.
const _fake = '''(() => {
  let ctl = null;
  const port = {
    opened: [], written: [], readable: null, writable: null,
    async open(o) {
      this.opened.push(o.baudRate);
      this.readable = new ReadableStream({ start(c) { ctl = c; } });
      this.writable = new WritableStream({ write: (ch) => { this.written.push(Array.from(ch)); } });
    },
    async close() { this.readable = null; this.writable = null; },
    getInfo() { return { usbVendorId: 0x1234, usbProductId: 0x5678 }; },
    push(bytes) { ctl.enqueue(new Uint8Array(bytes)); },
  };
  return { getPorts: async () => [port], requestPort: async () => port, port };
})()''';

void main() {
  test('a granted port opens, reads, writes, changes rate and closes', () async {
    final fake = globalContext.callMethod<JSObject>('eval'.toJS, _fake.toJS);
    final port = fake.getProperty<JSObject>('port'.toJS);
    final ports = WebSerialPorts(fake as JSSerial);

    final listed = await ports.list();
    expect([for (final p in listed) p.label], ['USB 1234:5678']);
    expect((await ports.ask())?.id, 'USB 1234:5678');

    final t = await listed.single.open(230400);
    final received = <int>[];
    t.input.listen(received.addAll);
    port.callMethod<JSAny?>('push'.toJS, [1, 2, 3].jsify());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(received, [1, 2, 3]);

    await t.write(Uint8List.fromList([9, 8]));
    expect(port.getProperty<JSAny?>('written'.toJS).dartify(), [
      [9, 8],
    ]);

    await t.setBaudRate(115200);
    port.callMethod<JSAny?>('push'.toJS, [4].jsify());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(received, [1, 2, 3, 4]);
    expect(port.getProperty<JSAny?>('opened'.toJS).dartify(), [230400, 115200]);

    await t.close();
    await expectLater(t.write(Uint8List(1)), throwsStateError);
  });
}
