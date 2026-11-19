import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:halyard/app/desktop_root.dart';
import 'package:halyard/features/connect/connect_controller.dart';
import 'package:halyard/instruments/readout.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// A synthetic definition from the core's vectors (no vendor file).
String _definition() {
  final cases = jsonDecode(File('../core/test/vectors/live.json').readAsStringSync()) as List<dynamic>;
  return (cases.first as Map<String, dynamic>)['xml'] as String;
}

/// One port with a simulated ECU behind it.
final class _FakePorts implements PortFinder {
  _FakePorts(String xml)
    : _ecu = SimEcu(readDeviceFile(xml).calibration, reportPeriod: const Duration(milliseconds: 100));
  final SimEcu _ecu;

  @override
  bool get canAsk => false;
  @override
  Future<PortEntry?> ask() async => null;
  @override
  Future<List<PortEntry>> list() async => [
    PortEntry('sim', 'Bench ECU (USB 1234:5678)', (b) => openSimulator(_ecu, b)),
  ];
}

final class _MemoryStorage implements AppStorage {
  final files = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String name) async => files[name];
  @override
  Future<void> write(String name, Uint8List bytes) async => files[name] = bytes;
  @override
  Future<void> delete(String name) async => files.remove(name);
}

final class _NoFolders implements FolderPicker {
  @override
  bool get available => false;
  @override
  Future<List<(String, String)>?> pick(String extension) async => null;
}

Future<void> _bigWindow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester, int steps) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('a serial port connects through the read-only link', (tester) async {
    final xml = _definition();
    final storage = _MemoryStorage();
    await _bigWindow(tester);
    await tester.pumpWidget(DesktopRoot(ports: _FakePorts(xml), storage: storage, folders: _NoFolders()));
    await tester.pumpAndSettle();
    expect(find.text('Bench ECU (USB 1234:5678)'), findsOneWidget);
    await tester.element(find.text('Definitions')).read<ConnectController>().addDefinition('demo.medef', xml);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await _settle(tester, 20);
    expect(find.textContaining('Online'), findsOneWidget);
    await tester.tap(find.text('Disconnect'));
    await _settle(tester, 10);
    expect(find.text('Offline'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester, 20);

    // A new start finds the definition again.
    await tester.pumpWidget(DesktopRoot(ports: _FakePorts(xml), storage: storage, folders: _NoFolders()));
    await tester.pumpAndSettle();
    expect(find.text('demo.medef'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester, 20);
  });

  testWidgets('demo mode connects, shows live data and passes the bench test', (tester) async {
    await _bigWindow(tester);
    await tester.pumpWidget(
      DesktopRoot(ports: _FakePorts(_definition()), storage: _MemoryStorage(), folders: _NoFolders()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);

    final connect = tester.element(find.text('Definitions')).read<ConnectController>();
    expect(await connect.addDefinition('demo.medef', _definition()), isTrue);
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
