# Security notes

## Threat model

The Dart package `trysac_flutter_focus_timer` is a pure library without I/O. The main risks are:

- **Supply chain**: a compromised package or CI action. Mitigation: Dart SDK libraries only, every
  package pinned with its SHA-256 by the committed `pubspec.lock` (installs run
  `dart pub get --enforce-lockfile`), pub.dev's security advisories and OSV-Scanner over
  `pubspec.lock` in the gates, Dependabot weekly updates, actions pinned by commit SHA, minimal
  workflow permissions.
- **Leaked secrets**: tokens committed by mistake. Mitigation: `gitleaks` runs in the local gates
  and in CI; `.env` files and pub credentials are never committed.
- **Insecure code**: processes run through a shell, code loaded from a URI or invoked by name
  through `dart:mirrors`, disabled TLS verification, predictable random tokens. Mitigation:
  `dart analyze` with the strict modes and the lints package, and the factory's Semgrep rules
  (`.semgrep/factory-rules.yml`, `nosemgrep` ignored); fix the code instead of silencing it.
- **Untrusted input**: callers may pass hostile strings. Mitigation: validate input and throw
  explicit, documented errors; never build a shell command line from data.

## Publishing

Releases are git tags; publishing on pub.dev needs a verified publisher account, whose
credentials are never stored in the repository.

To report a vulnerability, see [SECURITY.md](../SECURITY.md).
