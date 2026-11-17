# AGENTS.md

Instructions for coding agents (and humans) working on the Dart package `trysac_flutter_focus_timer`
(imported as `package:trysac_flutter_focus_timer/trysac_flutter_focus_timer.dart`).

## Commands

| Task | Command |
|---|---|
| Install dependencies | `dart pub get --enforce-lockfile` |
| Run every gate (must pass before a PR) | `dart run scripts/check.dart` |
| Tests only | `dart test` |
| Format | `dart format .` |
| Lint | `dart analyze --fatal-infos` |
| Coverage | `dart run scripts/check.dart tests` |

The gate sequence is: format (`dart format`), lint (`dart analyze --fatal-infos` with the strict
`analysis_options.yaml`, public API docs included; any diagnostic fails, and so does any
`// ignore:` comment), Semgrep (the factory's rules in `.semgrep/`), `package:test` under
`package:coverage` with line coverage >= 80 % of `lib/`, documentation (`docs-manifest.json` plus
`dart doc --dry-run`), gitleaks, pub.dev's security advisories for every package of
`pubspec.lock`, and OSV-Scanner over `pubspec.lock`. It stops at the first failure.

## Folder map

| Path | Content |
|---|---|
| `lib/trysac_flutter_focus_timer.dart` | The public library: it exports the files of `lib/src/` that form the public API. |
| `lib/src/` | The implementation, one concern per file; only what the public library exports is public API. |
| `test/` | `package:test` tests (`*_test.dart`, mirroring `lib/src/`), including kiri_check property tests. |
| `test/fixtures/` | Optional fixtures and golden files used by tests. |
| `scripts/` | The single definition of the quality gates (`check.dart`) and the factory's dependency tool. |
| `docs/` | Architecture, decisions (ADRs), testing, security, project record, stack. |
| `fabrica.json` | Install and check commands used by the factory and CI. |
| `docs-manifest.json` | Documentation files the docs gate requires. |
| `.github/` | CI wrapper and Dependabot configuration. |

## Conventions

- Dart 3.14 or newer, sound null safety, single-quoted strings, clean under `dart analyze` with
  the strict casts, inference and raw types modes.
- Dart SDK libraries only unless an ADR in `docs/decisions/` justifies a dependency.
- Every public declaration has a `///` doc comment; invalid input throws a documented
  `ArgumentError` subclass of the library, never returns null or a sentinel.
- Write the failing test first; tests use every literal of the acceptance items verbatim, and
  property tests (kiri_check `forAll` with a fixed `seed`) cover invariants.
- CI-only conformance tests (external tools or downloads) carry the `conformance` tag
  (`@Tags(['conformance'])` on the file, or `tags: 'conformance'` on a test); only CI runs them.
- Every behavior change updates `README.md` usage, `CHANGELOG.md` (Unreleased) and, if it is a
  design choice, a new ADR.
- Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`).

## Limits

- Never push to `main`; work on a branch and open a pull request.
- Do NOT edit `.github/`, `fabrica.json`, `docs-manifest.json`, `scripts/`, `pubspec.yaml`,
  `pubspec.lock`, `analysis_options.yaml`, `dart_test.yaml`, `.editorconfig` or any tool
  configuration. They are the quality contract; changes to them are made by a human.
- Never lower the coverage threshold, add `// ignore:`, `// ignore_for_file:` or
  `// coverage:ignore-*` comments to silence a finding, or skip a test to make a gate pass.
- Never commit secrets, tokens, credentials or `.env` files; gitleaks blocks them.
