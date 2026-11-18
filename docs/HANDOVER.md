# Handover

Read this first in a new session, then [ARCHITECTURE.md](ARCHITECTURE.md) and [behaviour-changes.md](behaviour-changes.md).

## Getting the code into a new session

Halyard lives in the private GitHub repo `kurt-culley/halyard`; clone it so `halyard/` and `me360/` are siblings. If
Kurt's Mac is linked, both projects are also in `~/Desktop/rea-meite/`. Otherwise he attaches `me360-reference.zip`;
unzip it next to the clone. The reference zip leaves out `me360/defs/` (vendor files); the core tests don't need them.

A cloud session needs `storage.googleapis.com` (the Dart SDK zip from `dart-archive/channels/stable/release/latest/`)
and `pub.dev` allowed in the network settings. Node 22.18 or later runs the vector generator.

## What this is

Halyard is a ground-up rebuild of the ME360 tuning app in Flutter. The previous project, `../me360`, is a
TypeScript/browser port of the vendor's Windows tool (MEITE 3.3.1), finished to full feature parity with 610 passing
tests. That project is the **reference implementation**: its `src/` is the behaviour to port, its `docs/requirements/`
are the functional specs, and its engine generates the golden vectors the Dart tests compare against.

## Standing instructions from Kurt

- Flutter, Material widgets with **no custom theming**.
- State: **Provider**; GetX only where needed (reactive state only, never its routing or DI). Routing: **auto_route**.
- Charts: fl_chart, plus custom painters for the log plot and live trace.
- MVP: **full feature parity on desktop**. Mobile connects to the ECU but **reads only** (no editing). Android uses
  native USB serial; iOS uses a Wi-Fi-to-serial bridge over TCP.
- Product name "Halyard" is a placeholder.
- **No vendor definitions, base maps or presets in the repo or the app.** They will come from a folder, file or URL
  (S3 later).
- Personal/educational, possibly a product later: avoid dependencies with commercial-use licence terms.
- Store to flash: reviewed store by default; **automatic store is a setting, off by default**.
- **No user-facing mention of "MEITE" or Motorsport Electronics.** Code comments may reference them.
- The architecture must stay **slim and well considered**, down to file and folder structure.
- Carried over from the earlier project: no VM in any capacity, no .NET oracle, don't hit the vendor's FTP server.
- Kurt has only an Intel MacBook (8 GB). Sync work to `~/Desktop/rea-meite/halyard` on his Mac when linked.

## State (18 Nov 2026, third session)

The core covers every decision-free module of the reference engine that the build order needs before the app: reading,
the session, live data and playback, logs, faults, CAN, import, presets, settings pages, table editing, the tuning
assistant and firmware files. What's left in the core waits on the write gate, on flashing, or on a question below.
Dart SDK 3.14.1; `dart analyze --fatal-infos` clean, `dart format` clean at 120 columns, 124 tests pass in about 13 s
on the VM and run in Chrome too (one more skips until `HALYARD_DEFS` is set), and both rule checks pass.
`node tool/export_vectors.mjs` regenerates every vector file byte for byte. CI is green on every push.

| Done and tested against the TypeScript engine | Files |
|---|---|
| Wire: framing, all message classes, reply factory | `core/lib/src/wire/` |
| Link: transport interface, channel, connection, read-only policy | `core/lib/src/link/` |
| Definition and calibration reading, blobs, hashes | `core/lib/src/definition/`, `core/lib/src/calibration/calibration.dart` |
| `.mecal` writer, backup file name | `core/lib/src/calibration/calibration_file.dart` |
| ECU simulator and its transport | `core/lib/src/sim/` |
| Session read path: identify, definition, password state, hashes, reads, reporting and lifesign | `core/lib/src/session/session.dart` |
| Import-rule and branding checks | `tool/check_imports.dart`, `tool/check_branding.dart` |
| Live data store | `core/lib/src/live/` |
| Fault codes, records, freeze frames, active-code bits, fault-log reader; simulated fault log | `core/lib/src/faults/`, `core/lib/src/sim/sim_faults.dart` |
| Measurement units and conversions (Fahrenheit input fixed) | `core/lib/src/units/` |
| Custom CAN: bit packing, CAN ids, the 3780-byte configuration, checks, OEM reserved ids; DBC file reading | `core/lib/src/can/` |
| Calibration import: file onto a definition, item-by-item analysis, applying a selection (incl. 16→2, 2→16, 16x16→8x8) | `core/lib/src/calibration/calibration_import.dart` |
| Onboard logging: support, configuration, start/stop, logs, erase, format, download, CSV; .NET number text and parsing for files | `core/lib/src/logs/` |
| PC logging: CSV header and lines, a recorder sampling the live store at its rate | `core/lib/src/logs/pc_log.dart` |
| Log review: CSV logs into sessions, statistics, events, difference sessions | `core/lib/src/logs/log_review.dart` |
| Log-plot decimation (MinMaxLTTB; new in Halyard, so property tests rather than vectors) | `core/lib/src/analysis/decimation.dart` |
| Fuel tuning assistant: analysis and suggestions from live or CSV samples (applying them waits for the write gate) | `core/lib/src/analysis/tuning_assistant.dart` |
| Live value text (listed texts, trim and plain percentages, fixed decimals), out-of-bounds, name with unit, and each link's feedback states with acknowledgement | `core/lib/src/live/link_values.dart` |
| Playback in the live store: pause, seek back, go live (reports kept aside meanwhile), load a recording; the strip's buttons and timer are app work | `core/lib/src/live/live_store.dart` |
| Live-data recordings: rolling CSV files of every report while a folder is set, read back for playback (times kept as milliseconds so they stay exact on the web) | `core/lib/src/logs/live_recording.dart` |
| Settings pages: rows and sections, units by preference, read-only by view constraint, typed values, the checks before a change (duplicates in a group, range, idle duties, Nissan SR trigger and phasing) and link choices, all as typed results. Applying a change waits for the write gate. The unlock warning names the vendor, so its wording is the app's | `core/lib/src/calibration/driver_settings.dart` |
| Table editing: decimals per table (the user's choice, AFR/lambda, VE, increment), the formula box, pasted cell blocks, .NET custom decimal text. The decimals choice and smoothing radius are stored however the app keeps settings, not as the original's XML strings; the heat colours are left to the theme | `core/lib/src/calibration/table_editing.dart` |
| Table presets: `.mepres` reading and writing, a table saved as a preset, the library by table id, the import list's search. No presets ship; the library holds the user's files (where they live is app work). As in the original, a preset holding an infinite value saves as `Infinity`, which it can't read back | `core/lib/src/calibration/presets.dart` |
| Firmware files: `.mefw` reading, Intel HEX to an image, region CRC (the update protocol waits for flashing, last in the build order) | `core/lib/src/firmware/firmware_file.dart` |

### What the second session changed and found

- **First compile.** Only small fixes: a closure that swallowed a cascade in a test, a set comparison in the requests
  test, and the fake transport's `close()` under `fake_async` (it settles on a root-zone future that the fake clock
  never flushes). `analysis_options.yaml` now sets the formatter width (120), and the SDK floor is `^3.7.0`.
- **Reader bugs the writer vectors exposed**, all now matching the original:
  - package:xml doesn't do XML end-of-line or attribute-value normalisation. `normaliseXmlSource` does both before
    parsing.
  - The original's arrays and parameters skip a value equal to the stored one, and 0 equals -0, so a zero keeps its
    sign. That shows in saved files and hashes. `assignFloats` does this when reading files and applying blobs.
  - `LinkDef.textValues` is null when the file has no list, so an empty list survives a save.
  - `parseTableBlob` and `parseDriverBlob` apply over the current values. A curve's wire form has no row axis, which
    zeroed it before.
- **Simulator.** Fully ported. The fault log is off until `ecu.faults.seed()`, as in the TypeScript simulator. It has a password
  option the TypeScript simulator lacks; the generator patches the TypeScript simulator the same way. Table-data writes
  assume one float per offset; the wire form doesn't say, and the editors only send one.
- **Session.** Reacts to every successful identity reply. On the same kind of ECU it confirms the overall hash or reads
  only what changed; otherwise it looks up a definition and reads everything. Each time it comes online it takes a
  snapshot of the calibration. Two behaviour changes are recorded in [behaviour-changes.md](behaviour-changes.md).
  Reporting state goes through `Session.pauseReporting` and `resumeReporting`, so the lifesign follows it.
- **Vectors.** Three new files: `calibration_files.json` (60 rich synthetic files, saved, then edited through wire
  blobs and saved again), `simulator.json` (25 scripted sessions) and `session.json` (12 connect scenarios run by the
  TypeScript app model with real timers). The generator pins `TZ=UTC` and stubs timers only for the simulator section.
  The vectors total about 15 MB.
- The TypeScript reference suite passes apart from 22 tests that read `me360/defs/`, which the reference zip leaves out.

## Next

1. **Repo and CI: done.** Private repo `kurt-culley/halyard` on GitHub; GitHub Actions (`.github/workflows/ci.yml`)
   runs analyze, format, tests and both rule checks on every push and pull request, green from the first push. A new
   cloud session attaches it with `add_repo` (push access) and clones it; it no longer needs the zip.
2. **Sending a calibration**: applying a file and the import analysis are done (`calibration_import.dart`); the
   review screen and quick selection (`load-calibration.ts`, U17) are app work. Sending (`message-handler.ts` K01–K04)
   is the first write path, so it goes with the write gate.
3. **Live data: done.** `core/lib/src/live/live_store.dart`: a ring buffer per link (1200 samples), latest value,
   staleness (not in the latest report), version counter and dirty bits. History follows the original handler; vectors
   in `live.json`. The session creates a store with each definition and feeds it reports.
4. **The 610 TypeScript tests one for one**: so far the Dart tests cover the ported units through vectors and
   scenarios, not test by test.
5. **Chrome: done.** The vector loader reads files on the VM and fetches them in a browser; every test except the
   `HALYARD_DEFS` check (`real_definitions_test.dart`) runs in Chrome too, and CI runs both. Locally as root, Chrome
   needs `--no-sandbox`: point `CHROME_EXECUTABLE` at a wrapper script that adds it.
6. Then the Flutter app scaffold (`flutter create`), step 2 of the build order.

## Questions for Kurt

- **PC log index (`LoggingInfo.xml`).** The original keeps an XML index of the logs it took next to them, with
  local-time stamps (U21a X03, X04). Halyard can write and read the same file, or keep its own index in app storage.
  Not ported until decided; the CSV itself is.

- **Fault diagnostic report files.** The original saves fault reports as JSON with `"format": "meite-fault-report"`
  and refuses to open files without that marker (U13-J01 to J04). Writing it puts the vendor's name in a file users
  share; changing it breaks compatibility both ways. Options: keep the marker; write our own marker and also accept
  the original's when opening; or our own only. Not ported until decided. Everything else in the fault module is.

## Open questions for the real ECU (bench test)

- Is the USB port native CDC (as static analysis suggested) or a USB-to-UART chip? Record VID/PID.
- Which baud rate connects?
- Does a flash store disturb a running engine? (Decides whether auto-store must wait for idle.)
- Real live-data report rate.
