# Security & Threat Model

## Defended Threats

- **Resource Exhaustion**: `LogCodec.decode` rejects inputs over 16,777,216 characters. `MemoryEventStore` rejects events beyond 100,000 entries.
- **Invalid Configuration**: All constructors validate durations (1 minute to 4 hours) and cycle counts (1 to 12). Tags are limited to 40 characters.
- **Input Sanitization**: `FocusTimerException` truncates error messages containing input snippets to 200 characters to prevent log flooding.
- **Platform Safety**: The library contains no `dart:io`, `dart:html`, or `package:flutter` imports, ensuring no unauthorized file, network, or UI access.

## Not Defended

- **Persistence Layer Integrity**: The library assumes the provided `EventStore` correctly persists data across application sessions. It does not encrypt logs; data security at rest is the responsibility of the host application.
