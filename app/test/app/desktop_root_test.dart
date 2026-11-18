import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:halyard/app/desktop_root.dart';
import 'package:halyard/features/connect/connect_controller.dart';
import 'package:halyard/instruments/readout.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// A synthetic definition from the core's vectors (no vendor file).
String _definition() {
  final cases = jsonDecode(File('../core/test/vectors/live.json').readAsStringSync()) as List<dynamic>;
  return (cases.first as Map<String, dynamic>)['xml'] as String;
}

void main() {
  testWidgets('demo mode connects, shows live data and passes the bench test', (tester) async {
    await tester.pumpWidget(const DesktopRoot());
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);

    final connect = tester.element(find.text('Definitions')).read<ConnectController>();
    expect(connect.addDefinition('demo.medef', _definition()), isTrue);
    await tester.pump();
    expect(find.text('demo.medef'), findsWidgets);

    await tester.tap(find.text('Start demo'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Online'), findsOneWidget);

    await tester.tap(find.text('Live'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(Readout), findsWidgets);

    await tester.tap(find.text('Bench test'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Run the checks'));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Copy the report'), findsOneWidget);
    expect(find.byIcon(Icons.error), findsNothing);

    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  });
}
