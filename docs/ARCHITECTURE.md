# Halyard architecture

Halyard is a tuning and data tool for the ME360 ECU. "Halyard" is a placeholder name.

This document fixes the shape of the code before any is written. Anything that isn't here needs a reason before it is added. The aim is a small number of well-placed boundaries, not many layers.

## Decisions

| Area | Decision |
|---|---|
| Toolkit | Flutter, Dart 3, one codebase |
| Look | Material widgets, default `ThemeData`, no custom theming. Flutter 3.50 moved Material into its own package; we depend on it as shipped. |
| State | Provider. GetX only for `Rx`/`Obx` inside one feature when Provider's rebuild scope is measured to be too wide. No GetX routing, dependency injection, snackbars or `GetMaterialApp`. |
| Routing | auto_route. Two routers: desktop and mobile. |
| Charts | fl_chart for small charts (histograms, bars, short trends). Custom painters for the log plot, live trace and 3D surface. |
| Desktop and web | Full feature parity with the existing app |
| Mobile | Connects to the ECU but reads only: live data, logging, log viewing, fault codes. No editing. |
| Android link | Native USB serial |
| iOS link | TCP to a Wi-Fi-to-serial bridge |
| Vendor files | Definitions, base maps and presets are not in the repo or the app. They load from a folder, a file or a URL (S3 later). |
| Branding | No user-facing mention of the original software or its vendor. "ME360" appears only as the connected device's model. |
| Store to flash | Reviewed store by default. Automatic store is a setting, off by default. |
| Posture | Personal and educational, possibly a product later. Avoid dependencies with commercial-use licence terms. |

## Repository layout

Two packages in one Dart workspace. The split exists for one reason: the core cannot import Flutter, because it doesn't depend on it. Everything else is folders.

```
halyard/
├─ pubspec.yaml                  workspace root, no code
├─ analysis_options.yaml         strict analysis shared by both packages
├─ core/                         package:halyard_core, pure Dart, no Flutter, no dart:io
│  ├─ lib/
│  │  ├─ halyard_core.dart       the only public entry point
│  │  └─ src/
│  │     ├─ wire/                bytes ⇄ frames ⇄ typed messages
│  │     │  ├─ framing.dart
│  │     │  ├─ checksum.dart
│  │     │  └─ messages/         one file per message class
│  │     ├─ link/                transport interface, request/reply channel, connect, guards
│  │     ├─ definition/          .medef import, internal schema, catalogue overlay
│  │     ├─ calibration/         model, .mecal codec, diff, undo
│  │     ├─ session/             session state machine, capabilities, write gate, journal, restore points, auto-store
│  │     ├─ live/                report decoding, ring buffers, staleness
│  │     ├─ logs/                capture, file formats, onboard-log download, playback source
│  │     ├─ analysis/            decimation, histogram, log-to-table, autotune, tuning assistant
│  │     ├─ firmware/            .mefw reader, flashing state machine
│  │     ├─ faults/
│  │     ├─ can/                 custom CAN and DBC
│  │     ├─ units/
│  │     └─ sim/                 ECU simulator, used by tests and demo mode
│  └─ test/                      mirrors lib/src; test/vectors/ holds golden vectors
├─ app/                          package:halyard, Flutter
│  ├─ lib/
│  │  ├─ main.dart               desktop and web entry
│  │  ├─ main_mobile.dart        iOS and Android entry, read-only
│  │  ├─ app/                    composition roots, routers, shells
│  │  ├─ platform/               transports and storage, one file per platform
│  │  ├─ workspace/              pages, tiles, split tree, drag and drop, command palette
│  │  ├─ instruments/            readout, bar, dial, map and curve grids, trace, log plot, surface
│  │  └─ features/               one folder per feature
│  ├─ assets/catalogue/          our own presentation layer; no vendor content
│  ├─ test/
│  └─ android/ ios/ macos/ windows/ linux/ web/
├─ tool/
│  ├─ check_imports.dart         layer rules, run in CI
│  ├─ check_branding.dart        vendor-name scan, run in CI
│  └─ export_vectors.mjs         runs the TypeScript engine to produce golden vectors
└─ docs/
   ├─ ARCHITECTURE.md
   └─ requirements/              unit specs carried over from the TypeScript project
```

### Rules

1. **Dependencies point one way:** `features → workspace, instruments → core`. Features never import other features; they reach each other through the router. Instruments never import core message or session types; they take a descriptor (name, units, range, thresholds) and a value source. `tool/check_imports.dart` fails CI on a violation.
2. **The core has no I/O.** Byte transport, clock, file storage and "ask the user" are interfaces the app passes in. The whole core runs under `dart test` in seconds.
3. **Only `halyard_core.dart` is public.** The app never imports `package:halyard_core/src/...`.
4. **No barrel files** apart from that one entry point. No `utils/`, `helpers/` or `common/` folders: code lives with the thing that owns it.
5. **File names carry their feature** (`tables_page.dart`, `tables_controller.dart`), so a file search is never ambiguous.
6. **Code generation is auto_route only.** Models are Dart 3 classes, records and sealed types with hand-written codecs. The interchange formats are few and fixed, so freezed and json_serializable would cost more than they save.
7. **Folders nest at most three deep under `lib/`** (`features/tables/widgets/`).

## Core

### Wire

Frames, checksums and one file per message class: reporting, tables, drivers, sys, firmware, datalog, trigger, drive-by-wire and faults. These are pure functions from bytes to typed values and back.

Dart integers are 64-bit on the VM and under Wasm, but JavaScript doubles in the JS web build. All checksum and bit-field code masks explicitly, and the wire tests run on the VM and in Chrome (`dart test -p chrome`).

### Link

`Transport` is the only thing a platform implements:

```dart
abstract interface class Transport {
  Stream<Uint8List> get input;
  Future<void> write(Uint8List bytes);
  Future<void> setBaudRate(int baud); // no-op where the link can't change it
  Future<void> close();
}
```

On top of it sit:
- the request/reply channel (matching, timeouts, lifesign);
- the connect state machine (probe, baud cycling);
- `ReadOnlyPolicy`, the default-deny allow-list from the bench test. The channel checks it before encoding, so a refused frame never reaches the transport. Besides reads it lets through RAM-only switches: reporting on/off, the table live cursor, and the trigger scope's on/off (throttle duty, class 8, stays refused).

Timeouts are chosen per kind of link (`LinkTiming.cable`, `LinkTiming.wifi`), so the Wi-Fi bridge can be more patient than a cable.

### Definition

`.medef` XML is imported into an internal schema and never edited. The catalogue overlay is keyed by stable item ids and adds what the vendor file lacks:
- display name, plain description and home section;
- tags, synonyms and the original name;
- soft and hard limits and a risk class.

The catalogue is our own content and ships as an asset. The definitions it overlays come from the user.

The definition library has three sources: a folder (for example the user's existing install), a single file, and a URL manifest (the future S3 bucket). Each loaded file is cached by content hash in app storage, and the ECU is matched to a definition by product, model and version.

### Session

The session is an explicit state machine whose transitions are its only API:

`offline → connecting → identifying → loading definition → reading calibration → online`, plus `flashing`.

A state that stops short of online carries a problem: no definition describes the ECU, or the ECU stopped answering. The session finds definitions through a lookup function that the definition library provides. It keeps the ECU's identity and calibration across a dropped link, so after a reconnect it either confirms the overall hash or reads only what changed.

Reporting state changes go through the session (`pauseReporting`, `resumeReporting`) so that the 1.5 s lifesign follows them. The original started and stopped the lifesign on any reporting request it saw sent.

It hands out capabilities, not a raw link:
- `reader` always exists.
- `writer`, the `WriteGate`, exists only when the composition root grants it. The mobile root never does, and also gives its channel the `ReadOnlyPolicy`. "Mobile can't write" therefore holds in two independent places.

The write gate is the one path to the ECU for any change. It applies the original tool's checks and nothing more
(Kurt, 19 Nov 2026): the definition's ranges, duplicate values in a group, and the original's relation rules (idle
duties, Nissan SR trigger and phasing). Changes go to the ECU as the original sent them, and storing to flash works as
the original's did. The deviations are the ones in behaviour-changes.md, made because the original was unsafe there:
a batch stops at the first unanswered request (so nothing unacknowledged is stored), and only a reply with a good
checksum confirms a write. Any further deviation needs the same justification and its own row there.

**Auto-store** is a preference, off by default; when on, it stores a few seconds after the last acknowledged write.

### Live

Report frames decode into a store with one preallocated ring buffer per channel, a latest value with timestamp, and a staleness flag. The store exposes a single version counter and per-channel dirty bits. The app turns that into one `Listenable` tick per frame, and instruments repaint from it directly. Live values never pass through Provider or GetX rebuilds.

Logging subscribes to the decoded stream itself, so the display may skip updates but the log never does.

### Analysis

Min/max-preserving decimation (MinMaxLTTB) lives here as a pure function, so a single-sample spike never vanishes from the log plot. Statistics and log-to-table always run on raw samples.

## App

### Composition

`main.dart` and `main_mobile.dart` each build a composition root (`app/desktop_root.dart`, `app/mobile_root.dart`). A root:
- picks the transport for the platform;
- creates the session and grants capabilities;
- registers app-wide providers: definition library, session, live tick, preferences, workspace;
- mounts its router.

The mobile entry doesn't import any editing feature, so that code isn't in the mobile build at all.

### Features

Every feature has the same shape:

```
features/tables/
├─ tables_page.dart          route entry; creates the controller with ChangeNotifierProvider
├─ tables_controller.dart    ChangeNotifier; the only file in the feature that talks to the core
├─ strings.dart              every user-facing string in the feature
└─ widgets/                  private to this feature
```

| Feature | Covers | Mobile |
|---|---|---|
| `connect` | port picker, scan, Wi-Fi bridge address, demo mode (simulator) | yes |
| `bench` | read-only bench test and report | yes |
| `definitions` | definition library and sources | yes |
| `live` | vital-signs strip, curated live pages, warnings | yes |
| `logging` | PC logging, onboard log download, log workspace, playback, histogram | yes |
| `faults` | fault log; clearing is desktop-only | read |
| `calibration` | open, save, new project, compare, notes, import review, restore points, store review | — |
| `tables` | map and curve editors, 3D surface, live-cell trail | — |
| `parameters` | settings pages from the catalogue | — |
| `assist` | autotune, tuning assistant, setup wizards | — |
| `can` | custom CAN editor and DBC import | — |
| `trigger_scope` | trigger logger | — |
| `ecu_tools` | clock, password protection, factory reset | — |
| `firmware` | firmware update | — |
| `settings` | units, shortcuts, auto-store | partial |

`workspace/` is the frame every desktop feature sits in:
- a fixed shell with navigator, pages, inspector and status bar;
- curated read-only pages plus user pages built from non-overlapping tiles in a split tree;
- pointer drag with drop zones, and a menu command for every drag;
- a command palette that reaches every item.

The page model is plain data with its own undo history, separate from calibration undo. Flutter has no maintained docking package, so the split tree is our own. It is small, and owning it keeps drag behaviour consistent. Pop-out windows wait for stable multi-window support.

### Platform

| Platform | Transport | Package | Setup |
|---|---|---|---|
| Web | Web Serial | `package:web` with a hand-written `dart:js_interop` binding (one file) | none |
| macOS, Windows, Linux | native serial | flutter_libserialport | macOS `com.apple.security.device.serial` entitlement |
| Android | USB host serial | usb_serial (CDC-ACM, FTDI, CP210x, CH34x) | USB host feature and device filter in the manifest |
| iOS | TCP socket to a Wi-Fi bridge | `dart:io` | Local Network usage description; RFC 2217 if the bridge needs a baud rate |

The protocol notes record the ECU's USB interface as CDC. That was found by static analysis and hasn't been confirmed on hardware. If it is CDC, the iOS bridge needs a USB host, such as an ESP32-S3, and baud rate doesn't matter on that hop. The bench report will record the USB vendor and product ids and the baud rate that worked.

Storage sits behind one core interface:
- Native platforms use the app support directory.
- Web uses the origin-private file system, treated as a working copy with a prompt to export.

The journal is JSON Lines, append-only.

## Testing

- **Core:** the TypeScript engine is the oracle.
  - `tool/export_vectors.mjs` produces golden vectors for frames, codecs and parsing, saved calibration files, scripted simulator sessions, and the connect sequence as the TypeScript app ran it against its simulator.
  - The 610 existing tests are ported one for one.
  - Recorded serial sessions are replayed.
  - Simulator scenarios with injected faults cover the write gate.
  - Runs on the VM and in Chrome.
- **Vendor files in tests:** tests that need a real definition or calibration read it from the path in `HALYARD_DEFS` and skip when it's unset. Unit tests use small hand-written fixtures. No vendor file is committed.
- **App:** widget tests run against the simulator transport. Golden-image tests cover instruments only, in five states: nominal, over limit, stale, disconnected and read-only.
- **CI:** `dart analyze --fatal-infos`, `dart format --set-exit-if-changed`, the import-rule check, the branding check, and core plus app tests.
- **Mutation testing:** applies to `wire/`, `link/` and `session/`. Dart has no mature mutation tool, so this needs a short trial (the `mutation_test` package is the first candidate).

## Porting map

The TypeScript modules in `me360/src` move like this.

| From | To |
|---|---|
| framing, protocol, requests, responses, message-handler, reporting, `*-msg` | `core/wire` |
| channel, connection, probe, port-scan, protocol-service, the bench guard | `core/link` |
| bench (the checklist and its report text, run over a session) | `core/session` |
| def-readers, def-manager, def-picker, datamodel, kinds, device-model, datalink, xml, xmlser | `core/definition` |
| calibration, load-calibration, import-review, calibration-notes, undo, presets, driver-settings (rows, parsing, change checks), the value operations of table-format and table-grid (decimals, formulas, pasted cells, interpolation, live position, smoothing) | `core/calibration` |
| app-model, app-settings | `core/session`, plus the `settings` feature |
| pc-logging, rolling-csv, datalogging, log-review, trigger-logger | `core/logs` |
| playback (pausing, seeking and loading recordings in the ring buffers), datalink presentation (value text, feedback states) | `core/live` |
| histogram, autotune, tuning-assistant, calibration-wizards | `core/analysis` |
| firmware, firmware-controller | `core/firmware` |
| faults, fault-log-model | `core/faults` |
| custom-can, dbc, custom-can-dbc | `core/can` |
| units | `core/units` |
| ecu-sim | `core/sim` |
| web-serial | `app/platform` |
| layout, layout-manager, widget-edit, widget-place, live-dash, favorites, main-menu, shortcuts, status-strip, warning-center, gauge, dro, table-grid, table-format, table-menu, table-trail, table-graph, graph3d, new-project, ecu-tools | redesigned in `app`, not ported line by line; the logic they share with files or other features is in the core rows above |
| netfmt, netcoll, help, resources, resources-http | dropped |

Why the last row is dropped:
- netfmt and netcoll emulated the original's runtime (number formatting and collection ordering). Their output is kept where text goes into interchange files, and the core's display helpers (live value text, table decimals, settings values) use the same rules so numbers read as they did; the app may present them differently.
- help and resources served the vendor's manual and its download server.

## Build order

1. **Scaffold and core read path.** Workspace and CI; wire, link, definition, calibration and session up to `online`; simulator; golden vectors.
2. **Desktop read-only slice.** Connect (simulator and serial), workspace shell, live instruments, palette, bench test.
3. **Editing.** Map and curve editors, parameters, write gate, store review, auto-store, restore points.
4. **Logging and analysis.**
5. **Remaining tools to parity.** CAN, trigger scope, faults, ECU tools, assist; firmware last.
6. **Mobile.** Android USB and iOS bridge, read-only shells.
