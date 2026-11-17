# trysac_flutter_focus_timer

Local-first Pomodoro engine rebuilt from an append-only event log, with suspend-safe catch-up on an injected clock, streak statistics, and a versioned JSON export.

## The Problem

Focus timer apps often count ticks in memory, causing them to lose time whenever the operating system suspends the app or a browser tab throttles background timers. This leads to drift between the timer state and reality. This package solves the issue by modeling the timer as an append-only log of timestamped events, allowing the state to be reconstructed deterministically from timestamps.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  trysac_flutter_focus_timer: any
```

## Usage Example

```dart
import 'package:trysac_flutter_focus_timer/trysac_flutter_focus_timer.dart';

void main() {
  final store = MemoryEventStore();
  final timer = FocusTimer(TimerConfig(), store);
  timer.startFocus(DateTime.utc(2026, 1, 5, 9, 0), tag: 'deep-work');
  final state = timer.tick(DateTime.utc(2026, 1, 5, 9, 25));
  print('${state.phase} completed=${state.completedFocusCount}');
}
```

## Public API

- `TimerConfig`: Configuration for `focus` (25m), `shortBreak` (5m), `longBreak` (15m), and `longBreakEvery` (4 cycles). Validates durations (1m to 4h) and cycles (1-12).
- `TimerEvent` (sealed): `FocusStarted`, `BreakStarted`, `Paused`, `Resumed`, `FocusCompleted`, `BreakCompleted`, `Skipped`, `Reset`.
- `FocusTimer`: The state machine. Methods: `startFocus`, `pause`, `resume`, `skip`, `reset`, `tick`, `state`, `changes`.
- `EventStore`: Interface for persistence, with `MemoryEventStore` implementation (default `maxEvents: 100000`).
- `LogCodec`: Handles JSON export (`encode`) and import (`decode`) with version checking and size limits.
- `Stats`: Computation engine for focus minutes, streaks, and completion rates with `utcOffset` support.
- `FocusTimerException`: Typed error codes (`invalid_transition`, `invalid_config`, `clock_went_backwards`, `corrupt_log`, `unsupported_version`, `input_too_large`, `log_full`).

## Why not traditional tick-counting alternatives?

Traditional packages rely on `Timer.periodic`, which drifts during suspension. This package is state-reconstructed from timestamps, ensuring consistency even after app restarts or long periods of inactivity.

## Security

See [docs/SECURITY.md](docs/SECURITY.md) for the threat model and resource limits.