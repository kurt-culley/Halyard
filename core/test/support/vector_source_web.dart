import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// A vector file's text, fetched from the test server, which serves the package's test/ folder next to the page.
Future<String> readVectorText(String name) async {
  final path = web.window.location.pathname;
  final root = path.substring(0, path.indexOf('/test/') + '/test/'.length);
  final r = await web.window.fetch('${root}vectors/$name'.toJS).toDart;
  if (!r.ok) throw StateError('vector file $name: HTTP ${r.status}');
  return (await r.text().toDart).toDart;
}
