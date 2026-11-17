# flutter-focus-timer

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/Trysac/u960-flutter-focus-timer/actions/workflows/ci.yml/badge.svg)](https://github.com/Trysac/u960-flutter-focus-timer/actions/workflows/ci.yml)

Local-first Pomodoro engine rebuilt from an append-only event log, with suspend-safe catch-up on an injected clock, streak statistics and a versioned JSON export

## Problem

Describe in two or three sentences the concrete problem this utility solves, who hits it, and what
they do today without it. Replace this paragraph when the first real feature lands.

## Install

```sh
dart pub add trysac_flutter_focus_timer
```

Until it is published on pub.dev, depend on a release tag in `pubspec.yaml`:

```yaml
dependencies:
  trysac_flutter_focus_timer:
    git:
      url: https://github.com/Trysac/u960-flutter-focus-timer.git
      ref: v0.1.0
```

Requires Dart 3.14 or newer. No dependencies outside the Dart SDK.

## Usage

```dart
import 'package:trysac_flutter_focus_timer/trysac_flutter_focus_timer.dart';

void main() {
  // normalize trims surrounding whitespace and lower-cases the text.
  print(normalize('  Hello World ')); // hello world

  // Blank input is rejected explicitly instead of returning an empty string.
  normalize('   '); // throws BlankInputError ("input is blank")
}
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) and [decisions](docs/decisions/)
- [Testing](docs/TESTING.md) and [security](docs/SECURITY.md)
- [Project record](docs/PROJECT.md) and [stack](docs/STACK.md)
- [Changelog](CHANGELOG.md) and [contributing guide](CONTRIBUTING.md)

## License

[MIT](LICENSE) (c) 2026 Miguel Gomez
