# Project record

## Objective

Local-first Pomodoro engine rebuilt from an append-only event log, with suspend-safe catch-up on an injected clock, streak statistics, and a versioned JSON export.

## Scope

- Pure Dart domain core for a Pomodoro timer.
- Append-only event logging for state reconstruction.
- Suspend-safe catch-up logic.
- Statistics computation (daily, tags, streaks).
- Deterministic JSON log serialization/deserialization.

## Out of Scope

- Flutter widgets or application UI.
- Audio, notifications, or alarm scheduling.
- Multi-device synchronization.
- Daylight-saving-aware local time zones (uses fixed UTC offsets only).
- Complex goal setting or gamification.

## Factory run u960 (measured from API usage)

| Date (UTC) | Phase | Model | Batch | Input | Output | Cache write | Cache read | Cost (USD) |
|---|---|---|---|---|---|---|---|---|
| 2026-11-17 | generation | google/gemini-4-argon | yes | 5800 | 23540 | 0 | 0 | 0.4940 |
| 2026-11-17 | fix-1 | google/gemini-3.8-flash | no | 36492 | 709 | 0 | 80972 | 0.0361 |
| 2026-11-17 | audit | google/gemini-3.8-flash | no | 140497 | 1372 | 0 | 809637 | 0.1712 |
| 2026-11-17 | docs | google/gemini-3.1-flash-lite | no | 14754 | 1369 | 0 | 0 | 0.0057 |

Total: $0.7071. Prices: vertex line, as measured by its adapter. Providers serve the current version of each model id, so the date tells which version answered; versions, launch stages and price sources per line are in the factory's model register (docs/MODELS.md).
