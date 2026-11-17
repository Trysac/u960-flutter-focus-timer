# Event-Sourced Pomodoro Engine with Injected Clock and Suspend Catch-Up

Status: accepted (generated, pending human review)

## Context

Traditional Pomodoro timer implementations rely on in-memory tick counters driven by periodic timers. When a mobile operating system suspends the application or a browser throttles background tab timers, ticks are missed, phase transitions happen late, and historical session statistics diverge from actual wall-clock time.

## Decision

Model the Pomodoro engine as a pure-Dart state machine backed by an append-only log of UTC-timestamped events (FocusStarted, BreakStarted, Paused, Resumed, FocusCompleted, BreakCompleted, Skipped, Reset) with an explicitly injected clock. On every tick or command, the timer deterministically catches up any phase completions and auto-started phases that occurred up to the given timestamp, and computes daily, tag, and streak statistics directly from the event log.

## Consequences

State survives app restarts and OS suspension without drift, replay from a persisted log produces the exact same state as a live timer, and all tests run deterministically without real wall-clock waits or platform dependencies.
