# Architecture

## Purpose

The Dart package `trysac_flutter_focus_timer` is a small, dependency-free library: Local-first Pomodoro engine rebuilt from an append-only event log, with suspend-safe catch-up on an injected clock, streak statistics and a versioned JSON export

## Shape

```text
caller code --> import 'package:trysac_flutter_focus_timer/trysac_flutter_focus_timer.dart' (lib/trysac_flutter_focus_timer.dart)
                    |
                    +-- export 'src/...' (lib/src/)
                          +-- top-level functions and classes; no I/O, no global mutable state
                          +-- private helpers (`_name`, or files the public library does not export)
```

- **Public API**: every declaration exported by `lib/trysac_flutter_focus_timer.dart`. Files of `lib/src/`
  that it does not export, and names starting with `_`, may change without a major version.
- **Errors**: invalid input throws an `ArgumentError` subclass of the library (such as
  `BlankInputError`) documented in the `///` comment. The library never prints, exits or changes
  global state.
- **Side effects**: none. If a feature needs I/O, accept a `Stream`, a `String` or a small
  interface instead of opening files, and record the choice in an ADR.

## Quality contract

`scripts/check.dart` is the single definition of the gates; `fabrica.json` tells the factory and
CI how to run it. See [TESTING.md](TESTING.md).

## Decisions

Architecture decisions are recorded in [decisions/](decisions/) as numbered ADRs.
