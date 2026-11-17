# Stack

## Used

| Tool | Why |
|---|---|
| Dart 3.14 | The current stable SDK; sound null safety, pure Dart (no Flutter). |
| pub | The standard package manager; `pubspec.lock` committed with every package's SHA-256, installs with `--enforce-lockfile`. |
| dart format | The SDK formatter (format gate), 120 columns. |
| dart analyze + lints | The analyzer with strict casts, inference and raw types, the recommended lints and public API docs (lint gate). |
| package:test + package:coverage | Tests and line coverage of `lib/` (read by the gate). |
| kiri_check | Property tests with generators, a fixed seed and shrinking, integrated with package:test. |
| dart doc | The docs gate builds the API documentation (`--dry-run`). |
| Semgrep CE + OSV-Scanner | The factory's own rules; OSV advisories over `pubspec.lock`. |
| pub.dev advisories | The security advisories `dart pub get` reports, for every locked package. |
| gitleaks | Secret scanning locally and in CI. |
| GitHub Actions + Dependabot | Thin CI wrapper over the local gates; weekly dependency updates. |

## Discarded

| Tool | Why not |
|---|---|
| Flutter | A pure Dart library needs only the Dart SDK. |
| glados | Not updated since 2023 and limited to Dart 2 SDK constraints; kiri_check is maintained. |
| `dart pub publish --dry-run` | It asks for a `doc/` folder and a released changelog entry, against the factory's `docs/` layout and Unreleased changelog. |
| very_good_analysis | The lints package plus an explicit rule list keeps every rule visible. |
| Shell scripts for gates | Not portable to Windows; the gates are a Dart script. |
