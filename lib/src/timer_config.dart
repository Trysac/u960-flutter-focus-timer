import 'exceptions.dart';
import 'focus_timer.dart';

/// Configuration for a [FocusTimer] cycle.
///
/// Each duration ([focus], [shortBreak], [longBreak]) must be between
/// 1 minute and 4 hours inclusive, and [longBreakEvery] must be between
/// 1 and 12 inclusive. Violations throw a [FocusTimerException] with
/// code `'invalid_config'`.
final class TimerConfig {
  /// Creates and validates a [TimerConfig].
  TimerConfig({
    this.focus = const Duration(minutes: 25),
    this.shortBreak = const Duration(minutes: 5),
    this.longBreak = const Duration(minutes: 15),
    this.longBreakEvery = 4,
    this.autoStartBreaks = true,
    this.autoStartFocus = false,
  }) {
    _validateDuration('focus', focus);
    _validateDuration('shortBreak', shortBreak);
    _validateDuration('longBreak', longBreak);
    if (longBreakEvery < _minLongBreakEvery || longBreakEvery > _maxLongBreakEvery) {
      throw FocusTimerException(
        'invalid_config',
        'longBreakEvery must be between $_minLongBreakEvery and '
            '$_maxLongBreakEvery (got $longBreakEvery)',
      );
    }
  }

  static const Duration _minDuration = Duration(minutes: 1);
  static const Duration _maxDuration = Duration(hours: 4);
  static const int _minLongBreakEvery = 1;
  static const int _maxLongBreakEvery = 12;

  /// Length of each focus phase.
  final Duration focus;

  /// Length of a short break phase.
  final Duration shortBreak;

  /// Length of a long break phase.
  final Duration longBreak;

  /// Number of completed focus phases required before a long break.
  final int longBreakEvery;

  /// Whether a break starts automatically when a focus phase completes.
  final bool autoStartBreaks;

  /// Whether a new focus phase starts automatically when a break completes.
  final bool autoStartFocus;

  static void _validateDuration(String fieldName, Duration value) {
    if (value < _minDuration || value > _maxDuration) {
      throw FocusTimerException(
        'invalid_config',
        '$fieldName duration must be between 1 minute and 4 hours '
            '(got ${value.inSeconds}s)',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimerConfig &&
          focus == other.focus &&
          shortBreak == other.shortBreak &&
          longBreak == other.longBreak &&
          longBreakEvery == other.longBreakEvery &&
          autoStartBreaks == other.autoStartBreaks &&
          autoStartFocus == other.autoStartFocus;

  @override
  int get hashCode => Object.hash(focus, shortBreak, longBreak, longBreakEvery, autoStartBreaks, autoStartFocus);

  @override
  String toString() =>
      'TimerConfig(focus: $focus, shortBreak: $shortBreak, '
      'longBreak: $longBreak, longBreakEvery: $longBreakEvery, '
      'autoStartBreaks: $autoStartBreaks, autoStartFocus: $autoStartFocus)';
}
