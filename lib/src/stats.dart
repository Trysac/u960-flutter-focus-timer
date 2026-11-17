import 'timer_event.dart';

/// Aggregated focus statistics computed from a [TimerEvent] log.
final class Stats {
  /// Creates an immutable [Stats] summary.
  const Stats({
    required this.focusMinutesByDay,
    required this.minutesByTag,
    required this.longestStreakDays,
    required this.currentStreakDays,
    required this.completionRate,
  });

  /// Total completed focus minutes grouped by shifted local date (`yyyy-MM-dd`).
  ///
  /// Each completed focus session's minutes are attributed to the day on which
  /// that focus session started.
  final Map<String, int> focusMinutesByDay;

  /// Total completed focus minutes grouped by the tag provided on
  /// [FocusStarted] (untagged sessions are omitted from this map).
  final Map<String, int> minutesByTag;

  /// Longest run of consecutive calendar days with at least one completed
  /// focus session.
  final int longestStreakDays;

  /// Active streak of consecutive calendar days with at least one completed
  /// focus session ending on `today` (or `yesterday` if `today` has none yet).
  final int currentStreakDays;

  /// Ratio of completed focus sessions to `completed + skipped` focus sessions
  /// (`0.0` when both are zero).
  final double completionRate;

  /// Computes [Stats] over [log] relative to [today] and [utcOffset].
  ///
  /// Every event timestamp (and [today]) is shifted into the fixed offset
  /// timezone by adding [utcOffset] to its UTC representation before extracting
  /// its calendar day (`yyyy-MM-dd`).
  ///
  /// The active focus duration for a completed session is the active (unpaused)
  /// elapsed time between its [FocusStarted] event and its matching
  /// [FocusCompleted] event, in whole minutes.
  static Stats compute(List<TimerEvent> log, {required DateTime today, Duration utcOffset = Duration.zero}) {
    final byDay = <String, int>{};
    final byTag = <String, int>{};
    final completedDayNumbers = <int>{};

    var completedFocusSessions = 0;
    var skippedFocusSessions = 0;

    var inFocus = false;
    var paused = false;
    DateTime? focusStartedAt;
    DateTime? runningSegmentStart;
    var accumulatedActive = Duration.zero;
    String? activeTag;

    for (final event in log) {
      switch (event) {
        case FocusStarted():
          inFocus = true;
          paused = false;
          focusStartedAt = event.at.toUtc();
          runningSegmentStart = focusStartedAt;
          accumulatedActive = Duration.zero;
          activeTag = event.tag;

        case BreakStarted():
          inFocus = false;
          paused = false;
          focusStartedAt = null;
          runningSegmentStart = null;
          accumulatedActive = Duration.zero;
          activeTag = null;

        case Paused():
          if (inFocus && !paused && runningSegmentStart != null) {
            final delta = event.at.toUtc().difference(runningSegmentStart);
            if (!delta.isNegative) {
              accumulatedActive += delta;
            }
            paused = true;
            runningSegmentStart = null;
          }

        case Resumed():
          if (inFocus && paused) {
            paused = false;
            runningSegmentStart = event.at.toUtc();
          }

        case FocusCompleted():
          if (inFocus && focusStartedAt != null) {
            if (!paused && runningSegmentStart != null) {
              final delta = event.at.toUtc().difference(runningSegmentStart);
              if (!delta.isNegative) {
                accumulatedActive += delta;
              }
            }
            final minutes = accumulatedActive.inMinutes;
            final shiftedStart = focusStartedAt.add(utcOffset);
            final dayKey = _formatDayKey(shiftedStart);
            final dayNumber = _epochDayNumber(shiftedStart);

            completedDayNumbers.add(dayNumber);
            byDay[dayKey] = (byDay[dayKey] ?? 0) + minutes;
            if (activeTag != null) {
              byTag[activeTag] = (byTag[activeTag] ?? 0) + minutes;
            }
            completedFocusSessions += 1;
          }
          inFocus = false;
          paused = false;
          focusStartedAt = null;
          runningSegmentStart = null;
          accumulatedActive = Duration.zero;
          activeTag = null;

        case BreakCompleted():
          inFocus = false;
          paused = false;
          focusStartedAt = null;
          runningSegmentStart = null;
          accumulatedActive = Duration.zero;
          activeTag = null;

        case Skipped():
          if (inFocus) {
            skippedFocusSessions += 1;
          }
          inFocus = false;
          paused = false;
          focusStartedAt = null;
          runningSegmentStart = null;
          accumulatedActive = Duration.zero;
          activeTag = null;

        case Reset():
          inFocus = false;
          paused = false;
          focusStartedAt = null;
          runningSegmentStart = null;
          accumulatedActive = Duration.zero;
          activeTag = null;
      }
    }

    final sortedDays = completedDayNumbers.toList()..sort();
    final longestStreak = _computeLongestStreak(sortedDays);
    final shiftedToday = today.toUtc().add(utcOffset);
    final todayDayNumber = _epochDayNumber(shiftedToday);
    final currentStreak = _computeCurrentStreak(completedDayNumbers, todayDayNumber);

    final totalFinishedOrSkipped = completedFocusSessions + skippedFocusSessions;
    final rate = totalFinishedOrSkipped == 0 ? 0.0 : completedFocusSessions / totalFinishedOrSkipped;

    return Stats(
      focusMinutesByDay: Map<String, int>.unmodifiable(byDay),
      minutesByTag: Map<String, int>.unmodifiable(byTag),
      longestStreakDays: longestStreak,
      currentStreakDays: currentStreak,
      completionRate: rate,
    );
  }

  static String _formatDayKey(DateTime shiftedUtc) {
    final y = shiftedUtc.year.toString().padLeft(4, '0');
    final m = shiftedUtc.month.toString().padLeft(2, '0');
    final d = shiftedUtc.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static int _epochDayNumber(DateTime shiftedUtc) {
    final midnightUtc = DateTime.utc(shiftedUtc.year, shiftedUtc.month, shiftedUtc.day);
    return midnightUtc.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  }

  static int _computeLongestStreak(List<int> sortedDayNumbers) {
    if (sortedDayNumbers.isEmpty) {
      return 0;
    }
    var longest = 1;
    var current = 1;
    for (var i = 1; i < sortedDayNumbers.length; i++) {
      if (sortedDayNumbers[i] == sortedDayNumbers[i - 1] + 1) {
        current += 1;
        if (current > longest) {
          longest = current;
        }
      } else {
        current = 1;
      }
    }
    return longest;
  }

  static int _computeCurrentStreak(Set<int> dayNumbers, int todayDayNumber) {
    if (dayNumbers.isEmpty) {
      return 0;
    }
    int cursor;
    if (dayNumbers.contains(todayDayNumber)) {
      cursor = todayDayNumber;
    } else if (dayNumbers.contains(todayDayNumber - 1)) {
      cursor = todayDayNumber - 1;
    } else {
      return 0;
    }
    var streak = 0;
    while (dayNumbers.contains(cursor)) {
      streak += 1;
      cursor -= 1;
    }
    return streak;
  }
}
