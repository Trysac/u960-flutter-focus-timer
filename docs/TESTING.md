# Testing

## Running

```sh
dart test                    # tests, property tests included
dart run scripts/check.dart  # every gate, as CI and the factory run it
```

## Policy

- Line coverage of `lib/` (measured by package:coverage) must stay at or above 80 %; the gate
  fails below it, every file of `lib/` with code must be loaded by a test, and
  `// coverage:ignore-*` comments are refused.
- Tests exercise the public API through `package:trysac_flutter_focus_timer/trysac_flutter_focus_timer.dart`. They
  assert every observable effect: returned values, thrown errors (`throwsA`) and their messages.
- Property tests state invariants such as idempotence or round trips with kiri_check's `property`
  and `forAll`, always with a fixed `seed`, so every run checks the same cases.
- Each bug fix starts with a failing test that reproduces it.
- Tests are deterministic: no network, no wall clock, no dependence on order.

## Tiers

- Local tier (every gate run, coverage measured here): unit and property tests, plus conformance
  on small fixtures kept in the repository.
- CI tier: conformance that needs an external tool or a download. Tag the file with
  `@Tags(['conformance'])` or the test with `tags: 'conformance'`; the tests gate excludes the tag
  (`--exclude-tags conformance`) unless `scripts/check.dart` runs with `FABRICA_CI=1`, while the
  analyzer always checks it. The CI `conformance` job sets `FABRICA_CI=1` and runs the full suite.
  Tools are installed by the optional `ci/conformance-setup.sh` (bash, CI only; verify every
  download against a pinned SHA-256), and tests pass `skip:` with a clear message when their tool
  is missing.

## Layout

Tests live in `test/`, mirroring `lib/src/` (`test/<name>_test.dart`). Fixtures and golden files
go in `test/fixtures/` (read them with paths relative to the package root, where `dart test`
runs).
