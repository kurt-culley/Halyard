# Halyard

Tuning and data tool for the ME360 ECU. Flutter app (`app/`, not created yet) over a pure-Dart core (`core/`).
Design and rules: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Deliberate differences from the original tool:
[docs/behaviour-changes.md](docs/behaviour-changes.md).

## Core tests

```sh
cd core
dart pub get
dart test
```

The tests compare the Dart core with the TypeScript engine through golden vectors in `core/test/vectors/`. To
regenerate them, with the TypeScript project checked out next to this one as `../me360` and Node 22.18 or later
(it runs the `.ts` sources directly):

```sh
node tool/export_vectors.mjs
```

The vectors are built from synthetic definitions; no vendor file is committed. To also check that real definitions
load, point `HALYARD_DEFS` at a folder of `.medef` files:

```sh
HALYARD_DEFS=/path/to/definitions dart test
```

## Checks

From the repository root, as CI will run them:

```sh
(cd core && dart analyze --fatal-infos && dart format --set-exit-if-changed . && dart test && dart test -p chrome)
dart run tool/check_imports.dart
dart run tool/check_branding.dart
```
