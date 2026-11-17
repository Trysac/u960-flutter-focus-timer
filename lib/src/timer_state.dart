import 'focus_timer.dart';

/// Phase of a [FocusTimer].
enum Phase {
  /// No phase is currently running.
  idle,

  /// A focus work interval is active or paused.
  focus,

  /// A short break interval is active or paused.
  shortBreak,

  /// A long break interval is active or paused.
  longBreak,
}

/// Immutable snapshot of a [FocusTimer] at a point in time.
final class TimerState {
  /// Creates a [TimerState] snapshot.
  const TimerState({
    required this.phase,
    required this.paused,
    required this.remaining,
    required this.completedFocusCount,
    this.currentTag,
  });

  /// Initial idle state before any events have occurred.
  static const TimerState initial = TimerState(
    phase: Phase.idle,
    paused: false,
    remaining: Duration.zero,
    completedFocusCount: 0,
  );

  /// Current phase of the timer.
  final Phase phase;

  /// Whether the current phase is paused.
  final bool paused;

  /// Remaining time in the current phase (`Duration.zero` when [Phase.idle]).
  final Duration remaining;

  /// Total number of focus phases completed since the start of the log or the
  /// most recent reset.
  final int completedFocusCount;

  /// Optional tag associated with the active or most recently started focus
  /// phase (`null` when idle or when started without a tag).
  final String? currentTag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimerState &&
          phase == other.phase &&
          paused == other.paused &&
          remaining == other.remaining &&
          completedFocusCount == other.completedFocusCount &&
          currentTag == other.currentTag;

  @override
  int get hashCode => Object.hash(phase, paused, remaining, completedFocusCount, currentTag);

  @override
  String toString() =>
      'TimerState(phase: $phase, paused: $paused, remaining: $remaining, '
      'completedFocusCount: $completedFocusCount, currentTag: $currentTag)';
}
