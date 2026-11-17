import 'dart:io';

import 'package:test/test.dart';
import 'package:trysac_flutter_focus_timer/trysac_flutter_focus_timer.dart';

void main() {
  group('Acceptance Criterion 1: Focus phases, shortBreak, and 4th focus longBreak', () {
    test('transitions from focus to shortBreak at 09:25:00 and longBreak after 4th focus', () {
      final config = TimerConfig();
      final store = MemoryEventStore();
      final timer = FocusTimer(config, store);

      final start = DateTime.utc(2026, 1, 5, 9);
      timer.startFocus(start, tag: 'deep-work');
      expect(timer.state.phase, Phase.focus);
      expect(timer.state.currentTag, 'deep-work');

      final oneSecBefore = DateTime.utc(2026, 1, 5, 9, 24, 59);
      final stateBefore = timer.tick(oneSecBefore);
      expect(stateBefore.phase, Phase.focus);
      expect(stateBefore.remaining, const Duration(seconds: 1));
      expect(stateBefore.completedFocusCount, 0);

      final exactEnd = DateTime.utc(2026, 1, 5, 9, 25, 0);
      final stateAtEnd = timer.tick(exactEnd);
      expect(stateAtEnd.phase, Phase.shortBreak);
      expect(stateAtEnd.completedFocusCount, 1);
      expect(stateAtEnd.remaining, const Duration(minutes: 5));
      expect(stateAtEnd.currentTag, isNull);

      // Complete shortBreak 1 at 09:30:00
      var cursor = DateTime.utc(2026, 1, 5, 9, 30, 0);
      expect(timer.tick(cursor).phase, Phase.idle);

      // Focus 2: 09:30 -> 09:55, shortBreak 2: 09:55 -> 10:00
      timer.startFocus(cursor);
      cursor = cursor.add(const Duration(minutes: 25));
      expect(timer.tick(cursor).phase, Phase.shortBreak);
      expect(timer.state.completedFocusCount, 2);
      cursor = cursor.add(const Duration(minutes: 5));
      expect(timer.tick(cursor).phase, Phase.idle);

      // Focus 3: 10:00 -> 10:25, shortBreak 3: 10:25 -> 10:30
      timer.startFocus(cursor);
      cursor = cursor.add(const Duration(minutes: 25));
      expect(timer.tick(cursor).phase, Phase.shortBreak);
      expect(timer.state.completedFocusCount, 3);
      cursor = cursor.add(const Duration(minutes: 5));
      expect(timer.tick(cursor).phase, Phase.idle);

      // Focus 4: 10:30 -> 10:55 -> triggers longBreak of 15 minutes
      timer.startFocus(cursor);
      cursor = cursor.add(const Duration(minutes: 25));
      final afterFourth = timer.tick(cursor);
      expect(afterFourth.phase, Phase.longBreak);
      expect(afterFourth.completedFocusCount, 4);
      expect(afterFourth.remaining, const Duration(minutes: 15));
    });
  });

  group('Acceptance Criterion 2: Pause, resume, and invalid transitions', () {
    test('shifts completion by paused duration and rejects invalid transitions', () {
      final timer = FocusTimer(TimerConfig(), MemoryEventStore());
      final emitted = <TimerState>[];
      final sub = timer.changes.listen(emitted.add);
      addTearDown(sub.cancel);

      // skip while idle throws invalid_transition
      expect(
        () => timer.skip(DateTime.utc(2026, 1, 5, 8, 59)),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'invalid_transition')),
      );

      // Focus starts at 09:00, paused at 09:10, resumed at 09:17
      timer.startFocus(DateTime.utc(2026, 1, 5, 9, 0));

      // resume while running throws invalid_transition
      expect(
        () => timer.resume(DateTime.utc(2026, 1, 5, 9, 5)),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'invalid_transition')),
      );

      final pausedState = timer.pause(DateTime.utc(2026, 1, 5, 9, 10));
      expect(pausedState.paused, isTrue);
      expect(pausedState.remaining, const Duration(minutes: 15));

      // pause while paused throws invalid_transition
      expect(
        () => timer.pause(DateTime.utc(2026, 1, 5, 9, 12)),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'invalid_transition')),
      );

      final resumedState = timer.resume(DateTime.utc(2026, 1, 5, 9, 17));
      expect(resumedState.paused, isFalse);
      expect(resumedState.remaining, const Duration(minutes: 15));

      // One second before 09:32:00 it is still in focus
      expect(timer.tick(DateTime.utc(2026, 1, 5, 9, 31, 59)).phase, Phase.focus);

      // At 09:32:00 the focus phase completes
      final completedState = timer.tick(DateTime.utc(2026, 1, 5, 9, 32, 0));
      expect(completedState.phase, Phase.shortBreak);
      expect(completedState.completedFocusCount, 1);
      expect(emitted, isNotEmpty);
    });

    test('pause during a break and reset while paused records no completion', () {
      final store = MemoryEventStore();
      final timer = FocusTimer(TimerConfig(), store);

      timer.startFocus(DateTime.utc(2026, 1, 5, 9, 0));
      timer.tick(DateTime.utc(2026, 1, 5, 9, 25));
      expect(timer.state.phase, Phase.shortBreak);

      // Pause 2 minutes into the short break
      final pausedBreak = timer.pause(DateTime.utc(2026, 1, 5, 9, 27));
      expect(pausedBreak.phase, Phase.shortBreak);
      expect(pausedBreak.paused, isTrue);
      expect(pausedBreak.remaining, const Duration(minutes: 3));

      // Reset while paused during break
      final afterReset = timer.reset(DateTime.utc(2026, 1, 5, 9, 28));
      expect(afterReset, TimerState.initial);

      // Start another focus, pause it, then reset while paused: no FocusCompleted
      timer.startFocus(DateTime.utc(2026, 1, 5, 10, 0));
      timer.pause(DateTime.utc(2026, 1, 5, 10, 10));
      timer.reset(DateTime.utc(2026, 1, 5, 10, 20));
      final completionsAfterReset = store.load().whereType<FocusCompleted>().toList();
      expect(completionsAfterReset, hasLength(1));
    });
  });

  group('Acceptance Criterion 3: Suspend catch-up', () {
    test('focus started at 09:00 and ticked at 09:45 appends exact intermediate timestamps', () {
      final config = TimerConfig(autoStartBreaks: true, autoStartFocus: false);
      final store = MemoryEventStore();
      final timer = FocusTimer(config, store);

      timer.startFocus(DateTime.utc(2026, 1, 5, 9, 0));
      final endState = timer.tick(DateTime.utc(2026, 1, 5, 9, 45));

      expect(endState.phase, Phase.idle);
      expect(endState.completedFocusCount, 1);
      expect(endState.remaining, Duration.zero);

      final log = store.load();
      expect(log, [
        FocusStarted(DateTime.utc(2026, 1, 5, 9, 0)),
        FocusCompleted(DateTime.utc(2026, 1, 5, 9, 25, 0)),
        BreakStarted(DateTime.utc(2026, 1, 5, 9, 25, 0), kind: BreakKind.short),
        BreakCompleted(DateTime.utc(2026, 1, 5, 9, 30, 0)),
      ]);
    });

    test('catches up across several long-break cycles in one tick when autoStartFocus is true', () {
      final config = TimerConfig(
        focus: const Duration(minutes: 10),
        shortBreak: const Duration(minutes: 2),
        longBreak: const Duration(minutes: 5),
        longBreakEvery: 2,
        autoStartBreaks: true,
        autoStartFocus: true,
      );
      final store = MemoryEventStore();
      final timer = FocusTimer(config, store);

      // Each 2-focus cycle takes: 10 + 2 + 10 + 5 = 27 minutes.
      // Two full cycles = 54 minutes; after 55 minutes we are 1 minute into focus #5.
      timer.startFocus(DateTime.utc(2026, 1, 5, 9, 0));
      final state = timer.tick(DateTime.utc(2026, 1, 5, 9, 55));

      expect(state.completedFocusCount, 4);
      expect(state.phase, Phase.focus);
      expect(state.remaining, const Duration(minutes: 9));

      final longBreaks = store.load().whereType<BreakStarted>().where((b) => b.kind == BreakKind.long).toList();
      expect(longBreaks, hasLength(2));
    });
  });

  group('Acceptance Criterion 5: Stats.compute', () {
    test('computes focusMinutesByDay, streaks, and completionRate for 2026-01-05, 06, 08', () {
      final log = <TimerEvent>[];

      void addCompletedFocus(DateTime start, {String? tag}) {
        log.add(FocusStarted(start, tag: tag));
        log.add(FocusCompleted(start.add(const Duration(minutes: 25))));
      }

      void addSkippedFocus(DateTime start) {
        log.add(FocusStarted(start));
        log.add(Skipped(start.add(const Duration(minutes: 5))));
      }

      // 2026-01-05: 3 completed sessions (75 minutes)
      addCompletedFocus(DateTime.utc(2026, 1, 5, 9, 0), tag: 'coding');
      addCompletedFocus(DateTime.utc(2026, 1, 5, 10, 0), tag: 'coding');
      addCompletedFocus(DateTime.utc(2026, 1, 5, 11, 0), tag: 'reading');

      // 2026-01-06: 2 completed sessions (50 minutes) + 1 skipped
      addCompletedFocus(DateTime.utc(2026, 1, 6, 9, 0), tag: 'coding');
      addCompletedFocus(DateTime.utc(2026, 1, 6, 10, 0));
      addSkippedFocus(DateTime.utc(2026, 1, 6, 11, 0));

      // 2026-01-07: 1 skipped focus session
      addSkippedFocus(DateTime.utc(2026, 1, 7, 9, 0));

      // 2026-01-08: 1 completed session (25 minutes)
      addCompletedFocus(DateTime.utc(2026, 1, 8, 9, 0), tag: 'reading');

      final stats = Stats.compute(log, today: DateTime.utc(2026, 1, 8, 18, 0), utcOffset: Duration.zero);

      expect(stats.focusMinutesByDay, {'2026-01-05': 75, '2026-01-06': 50, '2026-01-08': 25});
      expect(stats.minutesByTag, {'coding': 75, 'reading': 50});
      expect(stats.longestStreakDays, 2);
      expect(stats.currentStreakDays, 1);
      expect(stats.completionRate, 0.75);
    });

    test('handles utcOffset of +14:00 and -12:00 moving a session across days and midnight crossing', () {
      // Session starts at 2026-01-05T23:50:00Z and ends 25 minutes later on 2026-01-06T00:15:00Z.
      // Under UTC (00:00), it started on 2026-01-05.
      // Under +14:00, start time is 2026-01-06T13:50:00 -> counted on 2026-01-06.
      // Under -12:00, a session at 2026-01-06T05:00:00Z is 2026-01-05T17:00:00 -> counted on 2026-01-05.
      final log = <TimerEvent>[
        FocusStarted(DateTime.utc(2026, 1, 5, 23, 50)),
        FocusCompleted(DateTime.utc(2026, 1, 6, 0, 15)),
      ];

      final statsUtc = Stats.compute(log, today: DateTime.utc(2026, 1, 6, 1, 0), utcOffset: Duration.zero);
      expect(statsUtc.focusMinutesByDay, {'2026-01-05': 25});
      // Today is 2026-01-06, session was yesterday (2026-01-05) -> currentStreakDays is still 1!
      expect(statsUtc.currentStreakDays, 1);

      final statsPlus14 = Stats.compute(
        log,
        today: DateTime.utc(2026, 1, 5, 23, 55),
        utcOffset: const Duration(hours: 14),
      );
      expect(statsPlus14.focusMinutesByDay, {'2026-01-06': 25});
      expect(statsPlus14.currentStreakDays, 1);

      final morningUtcLog = <TimerEvent>[
        FocusStarted(DateTime.utc(2026, 1, 6, 5, 0)),
        FocusCompleted(DateTime.utc(2026, 1, 6, 5, 25)),
      ];
      final statsMinus12 = Stats.compute(
        morningUtcLog,
        today: DateTime.utc(2026, 1, 6, 6, 0),
        utcOffset: const Duration(hours: -12),
      );
      expect(statsMinus12.focusMinutesByDay, {'2026-01-05': 25});
      expect(statsMinus12.currentStreakDays, 1);
    });

    test('returns 0.0 completionRate and 0 streaks on empty log or paused focus', () {
      final emptyStats = Stats.compute(const [], today: DateTime.utc(2026, 1, 8));
      expect(emptyStats.focusMinutesByDay, isEmpty);
      expect(emptyStats.minutesByTag, isEmpty);
      expect(emptyStats.longestStreakDays, 0);
      expect(emptyStats.currentStreakDays, 0);
      expect(emptyStats.completionRate, 0.0);

      // Session with pause/resume still counts only active focus minutes
      final pausedLog = <TimerEvent>[
        FocusStarted(DateTime.utc(2026, 1, 5, 9, 0), tag: 'work'),
        Paused(DateTime.utc(2026, 1, 5, 9, 10)),
        Resumed(DateTime.utc(2026, 1, 5, 9, 20)),
        FocusCompleted(DateTime.utc(2026, 1, 5, 9, 35)),
      ];
      final pausedStats = Stats.compute(pausedLog, today: DateTime.utc(2026, 1, 10));
      expect(pausedStats.focusMinutesByDay, {'2026-01-05': 25});
      expect(pausedStats.minutesByTag, {'work': 25});
      expect(pausedStats.currentStreakDays, 0);
      expect(pausedStats.longestStreakDays, 1);
    });
  });

  group('Acceptance Criterion 6: LogCodec encode and decode', () {
    test('round-trips every event type and starts with required header prefix', () {
      final events = <TimerEvent>[
        FocusStarted(DateTime.utc(2026, 1, 5, 9, 0), tag: 'plan'),
        Paused(DateTime.utc(2026, 1, 5, 9, 10)),
        Resumed(DateTime.utc(2026, 1, 5, 9, 15)),
        FocusCompleted(DateTime.utc(2026, 1, 5, 9, 30)),
        BreakStarted(DateTime.utc(2026, 1, 5, 9, 30), kind: BreakKind.short),
        BreakCompleted(DateTime.utc(2026, 1, 5, 9, 35)),
        FocusStarted(DateTime.utc(2026, 1, 5, 9, 40)),
        Skipped(DateTime.utc(2026, 1, 5, 9, 45)),
        BreakStarted(DateTime.utc(2026, 1, 5, 9, 45), kind: BreakKind.long),
        Reset(DateTime.utc(2026, 1, 5, 9, 50)),
      ];

      final encoded = LogCodec.encode(events);
      expect(encoded.startsWith('{"format":"focus-timer-log","version":1,'), isTrue);

      final decoded = LogCodec.decode(encoded);
      expect(decoded, events);
    });

    test('rejects version 2, corrupt JSON, unknown event types, and oversized input', () {
      expect(
        () => LogCodec.decode('{"format":"focus-timer-log","version":2,"events":[]}'),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'unsupported_version')),
      );

      expect(
        () => LogCodec.decode('{not valid json'),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'corrupt_log')),
      );

      expect(
        () => LogCodec.decode(
          '{"format":"focus-timer-log","version":1,"events":[{"type":" MysteriousEvent","at":"2026-01-05T09:00:00.000Z"}]}',
        ),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'corrupt_log')),
      );

      // Test custom maxChars and the default 16_777_216 limit
      expect(
        () => LogCodec.decode('{"format":"focus-timer-log"}', maxChars: 10),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'input_too_large')),
      );

      final over16M = 'a' * (16777216 + 1);
      expect(
        () => LogCodec.decode(over16M),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'input_too_large')),
      );
    });

    test('rejects malformed envelopes and event fields with corrupt_log and truncates long snippets', () {
      final badInputs = <String>[
        '[]',
        '{"format":"wrong","version":1,"events":[]}',
        '{"format":"focus-timer-log","version":"1","events":[]}',
        '{"format":"focus-timer-log","version":1,"events":{}}',
        '{"format":"focus-timer-log","version":1,"events":[42]}',
        '{"format":"focus-timer-log","version":1,"events":[{"type":123}]}',
        '{"format":"focus-timer-log","version":1,"events":[{"type":"Paused","at":123}]}',
        '{"format":"focus-timer-log","version":1,"events":[{"type":"Paused","at":"not-a-date"}]}',
        '{"format":"focus-timer-log","version":1,"events":[{"type":"FocusStarted","at":"2026-01-05T09:00:00.000Z","tag":123}]}',
        '{"format":"focus-timer-log","version":1,"events":[{"type":"FocusStarted","at":"2026-01-05T09:00:00.000Z","tag":"${'x' * 41}"}]}',
        '{"format":"focus-timer-log","version":1,"events":[{"type":"BreakStarted","at":"2026-01-05T09:00:00.000Z","kind":123}]}',
        '{"format":"focus-timer-log","version":1,"events":[{"type":"BreakStarted","at":"2026-01-05T09:00:00.000Z","kind":"huge"}]}',
      ];

      for (final payload in badInputs) {
        expect(
          () => LogCodec.decode(payload),
          throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'corrupt_log')),
        );
      }

      // Ensure untrusted input in error messages is capped
      final longCorrupt = '{${'z' * 500}';
      try {
        LogCodec.decode(longCorrupt);
        fail('Expected FocusTimerException');
      } on FocusTimerException catch (e) {
        expect((e.message as String).length, lessThanOrEqualTo(283));
      }
    });
  });

  group('Acceptance Criterion 7: Monotonic clock and MemoryEventStore capacity', () {
    test('throws clock_went_backwards and leaves log unchanged', () {
      final store = MemoryEventStore();
      final timer = FocusTimer(TimerConfig(), store);

      timer.startFocus(DateTime.utc(2026, 1, 5, 9, 0));
      timer.tick(DateTime.utc(2026, 1, 5, 9, 10));
      final snapshotBefore = store.load();
      final stateBefore = timer.state;

      expect(
        () => timer.pause(DateTime.utc(2026, 1, 5, 9, 9, 59)),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'clock_went_backwards')),
      );

      expect(store.load(), snapshotBefore);
      expect(timer.state, stateBefore);
    });

    test('MemoryEventStore(maxEvents: 100000) throws log_full on event 100_001', () {
      final store = MemoryEventStore(maxEvents: 100000);
      final event = Reset(DateTime.utc(2026, 1, 5, 9, 0));
      for (var i = 0; i < 100000; i++) {
        store.append(event);
      }
      expect(store.load(), hasLength(100000));

      expect(() => store.append(event), throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'log_full')));
    });
  });

  group('Acceptance Criterion 8: Platform neutrality', () {
    test('no file under lib/ imports dart:io, dart:html, dart:ui, package:flutter or package:http', () {
      final libDir = Directory('lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      expect(dartFiles, isNotEmpty);

      final forbidden = <String>['dart:io', 'dart:html', 'dart:ui', 'package:flutter', 'package:http'];

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        for (final token in forbidden) {
          expect(content.contains(token), isFalse, reason: 'File ${file.path} must not import $token');
        }
      }
    });
  });

  group('Config, non-UTC conversion, and value equality edge cases', () {
    test('validates TimerConfig boundaries and tag length', () {
      expect(
        () => TimerConfig(focus: const Duration(seconds: 59)),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'invalid_config')),
      );
      expect(
        () => TimerConfig(shortBreak: const Duration(hours: 4, seconds: 1)),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'invalid_config')),
      );
      expect(
        () => TimerConfig(longBreakEvery: 0),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'invalid_config')),
      );
      expect(
        () => TimerConfig(longBreakEvery: 13),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'invalid_config')),
      );
      expect(
        () => FocusStarted(DateTime.utc(2026, 1, 5), tag: 't' * 41),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'invalid_config')),
      );
      expect(
        () => MemoryEventStore(maxEvents: 0),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'invalid_config')),
      );
      expect(
        () => LogCodec.decode('{}', maxChars: 0),
        throwsA(isA<FocusTimerException>().having((e) => e.code, 'code', 'invalid_config')),
      );
    });

    test('converts non-UTC DateTime inputs to UTC and supports skip during break', () {
      final config = TimerConfig(autoStartBreaks: true, autoStartFocus: true);
      final store = MemoryEventStore();
      final timer = FocusTimer(config, store);

      final localTime = DateTime(2026, 1, 5, 9, 0);
      timer.startFocus(localTime, tag: 'local');
      expect(store.load().first.at.isUtc, isTrue);

      // Skip focus -> auto-starts shortBreak
      final afterFocusSkip = timer.skip(localTime.add(const Duration(minutes: 5)));
      expect(afterFocusSkip.phase, Phase.shortBreak);
      expect(afterFocusSkip.completedFocusCount, 0);

      // Skip shortBreak -> auto-starts focus because autoStartFocus is true
      final afterBreakSkip = timer.skip(localTime.add(const Duration(minutes: 6)));
      expect(afterBreakSkip.phase, Phase.focus);

      // Value equality and toString coverage
      expect(TimerConfig(), equals(TimerConfig()));
      expect(TimerConfig().hashCode, equals(TimerConfig().hashCode));
      expect(TimerConfig().toString(), contains('TimerConfig'));
      expect(afterBreakSkip.toString(), contains('TimerState'));
      for (final ev in store.load()) {
        expect(ev.toString(), isNotEmpty);
        expect(ev.hashCode, isNonZero);
      }
    });
  });
}
