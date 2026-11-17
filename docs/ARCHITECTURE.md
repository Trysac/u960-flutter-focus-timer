# Architecture

## Context & Purpose

`trysac_flutter_focus_timer` is the pure-Dart, framework-free domain core for a local-first Pomodoro focus timer. Instead of relying on `Timer.periodic` tick counters that drift when mobile OSes suspend background processes or browsers throttle inactive tabs, all transitions are derived from an append-only log of UTC-timestamped `TimerEvent` records.

## Module Structure

- `lib/src/timer_config.dart`: Validated cycle configuration (`TimerConfig`).
- `lib/src/timer_event.dart`: Sealed `TimerEvent` hierarchy and `BreakKind` enum.
- `lib/src/timer_state.dart`: Immutable `TimerState` value object and `Phase` enum.
- `lib/src/event_store.dart`: `EventStore` interface and bounded `MemoryEventStore`.
- `lib/src/focus_timer.dart`: `FocusTimer` state machine, transactional draft evaluation, and suspend catch-up loop.
- `lib/src/log_codec.dart`: Deterministic JSON encoder and defensive, size-capped decoder (`LogCodec`).
- `lib/src/stats.dart`: Aggregation engine (`Stats.compute`) for per-day minutes, per-tag minutes, streaks, and completion rate.
- `lib/src/exceptions.dart`: `FocusTimerException` with machine-readable error codes and input snippet truncation.

## Key Design Decisions

1. **Injected UTC Clock**: Every command accepts an explicit `DateTime now` (normalized via `.toUtc()`). If `now` is earlier than the last recorded event timestamp, `FocusTimerException('clock_went_backwards')` is thrown before mutating state or the store.
2. **Transactional Command Application**: Commands clone the internal engine state, run catch-up transitions and the requested command on the draft, and only append events to `EventStore` once all validations succeed.
3. **Deterministic JSON Serialization**: `LogCodec.encode` writes keys in a fixed order starting with `{"format":"focus-timer-log","version":1,"events":[...]}` so exports are byte-for-byte reproducible.
