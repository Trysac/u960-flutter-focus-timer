# Testing

## Test Files

- `test/focus_timer_test.dart`: Covers core acceptance criteria: phase transitions, pause/resume logic, clock suspension, and statistics computation (including UTC offset edge cases).
- `test/replay_properties_test.dart`: Property-based testing using `kiri_check`. It generates random sequences of commands and asserts that replaying the log results in the exact same state as the live timer.
- `test/text_properties_test.dart`: Property-based testing for text normalization, asserting idempotence, whitespace handling, and casing.
- `test/text_test.dart`: Unit tests for `normalize`, verifying trimming, casing, and error handling for blank/empty input.
