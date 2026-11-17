import 'dart:async';

import 'event_store.dart';
import 'exceptions.dart';
import 'timer_config.dart';
import 'timer_event.dart';
import 'timer_state.dart';

/// Local-first Pomodoro state machine backed by an append-only [EventStore].
///
/// Time is always injected into command methods (`startFocus`, `pause`,
/// `resume`, `skip`, `reset`, `tick`). The library never calls
/// `DateTime.now()` or starts background platform timers.
final class FocusTimer {
  /// Creates a [FocusTimer] using [config] and replaying any existing events
  /// from [store].
  FocusTimer(this.config, this.store) {
    final existing = store.load();
    _replayAll(existing);
  }

  /// Rebuilds a [FocusTimer] from an existing [log] snapshot stored in a fresh
  /// [MemoryEventStore].
  factory FocusTimer.fromLog(TimerConfig config, List<TimerEvent> log) {
    final store = MemoryEventStore(maxEvents: log.length > 100000 ? log.length : 100000, initialEvents: log);
    return FocusTimer(config, store);
  }

  /// Timer cycle configuration.
  final TimerConfig config;

  /// Underlying append-only event store.
  final EventStore store;

  final StreamController<TimerState> _changesController = StreamController<TimerState>.broadcast(sync: true);

  Phase _phase = Phase.idle;
  bool _paused = false;
  Duration _remaining = Duration.zero;
  int _completedFocusCount = 0;
  String? _currentTag;
  DateTime? _lastEventAt;
  DateTime? _lastRunningAnchor;

  /// Current snapshot of the timer.
  TimerState get state => TimerState(
    phase: _phase,
    paused: _paused,
    remaining: _remaining,
    completedFocusCount: _completedFocusCount,
    currentTag: _currentTag,
  );

  /// Broadcast stream emitting the latest [TimerState] after each command or
  /// [tick].
  Stream<TimerState> get changes => _changesController.stream;

  /// Starts a focus session at [now] with an optional [tag] (at most 40
  /// characters).
  ///
  /// First catches up any phases that already elapsed before [now].
  /// Throws [FocusTimerException] with `'invalid_transition'` if a focus or
  /// break phase is still in progress at [now].
  TimerState startFocus(DateTime now, {String? tag}) {
    final utcNow = now.toUtc();
    final validatedTag = validateFocusTag(tag);
    final draft = _cloneEngine();
    final pending = <TimerEvent>[];
    draft._ensureMonotonic(utcNow);
    draft._catchUpTo(utcNow, pending);
    if (draft._phase != Phase.idle) {
      throw FocusTimerException('invalid_transition', 'Cannot start focus while in phase ${draft._phase.name}');
    }
    final event = FocusStarted(utcNow, tag: validatedTag);
    draft._applyEvent(event);
    pending.add(event);
    return _commit(draft, pending);
  }

  /// Pauses the active running phase at [now].
  ///
  /// First catches up any phases that already completed at or before [now].
  /// Throws [FocusTimerException] with `'invalid_transition'` if the timer is
  /// idle or already paused at [now].
  TimerState pause(DateTime now) {
    final utcNow = now.toUtc();
    final draft = _cloneEngine();
    final pending = <TimerEvent>[];
    draft._ensureMonotonic(utcNow);
    draft._catchUpTo(utcNow, pending);
    if (draft._phase == Phase.idle || draft._paused) {
      throw FocusTimerException(
        'invalid_transition',
        'Cannot pause when phase is ${draft._phase.name} (paused: ${draft._paused})',
      );
    }
    final event = Paused(utcNow);
    draft._applyEvent(event);
    pending.add(event);
    return _commit(draft, pending);
  }

  /// Resumes a paused phase at [now].
  ///
  /// Throws [FocusTimerException] with `'invalid_transition'` if the timer is
  /// not paused.
  TimerState resume(DateTime now) {
    final utcNow = now.toUtc();
    final draft = _cloneEngine();
    final pending = <TimerEvent>[];
    draft._ensureMonotonic(utcNow);
    if (draft._phase == Phase.idle || !draft._paused) {
      throw FocusTimerException(
        'invalid_transition',
        'Cannot resume when phase is ${draft._phase.name} (paused: ${draft._paused})',
      );
    }
    final event = Resumed(utcNow);
    draft._applyEvent(event);
    pending.add(event);
    return _commit(draft, pending);
  }

  /// Skips the current focus or break phase at [now].
  ///
  /// First catches up any phases that completed strictly before or at [now].
  /// If a focus phase is skipped, `completedFocusCount` is not incremented,
  /// and if `config.autoStartBreaks` is `true`, the next break begins at [now].
  /// If a break phase is skipped and `config.autoStartFocus` is `true`, the
  /// next focus phase begins at [now].
  /// Throws [FocusTimerException] with `'invalid_transition'` if the timer is
  /// idle at [now].
  TimerState skip(DateTime now) {
    final utcNow = now.toUtc();
    final draft = _cloneEngine();
    final pending = <TimerEvent>[];
    draft._ensureMonotonic(utcNow);
    draft._catchUpTo(utcNow, pending);
    if (draft._phase == Phase.idle) {
      throw FocusTimerException('invalid_transition', 'Cannot skip while timer is idle');
    }
    final skippedPhase = draft._phase;
    final skipEvent = Skipped(utcNow);
    draft._applyEvent(skipEvent);
    pending.add(skipEvent);

    if (skippedPhase == Phase.focus && config.autoStartBreaks) {
      final kind = draft._nextBreakKind();
      final breakStart = BreakStarted(utcNow, kind: kind);
      draft._applyEvent(breakStart);
      pending.add(breakStart);
    } else if ((skippedPhase == Phase.shortBreak || skippedPhase == Phase.longBreak) && config.autoStartFocus) {
      final focusStart = FocusStarted(utcNow);
      draft._applyEvent(focusStart);
      pending.add(focusStart);
    }
    return _commit(draft, pending);
  }

  /// Resets the timer to [Phase.idle] at [now], clearing any running or paused
  /// phase and resetting `completedFocusCount` to `0`.
  ///
  /// Resetting while a phase is paused or running does not record a completion
  /// for the interrupted phase.
  TimerState reset(DateTime now) {
    final utcNow = now.toUtc();
    final draft = _cloneEngine();
    final pending = <TimerEvent>[];
    draft._ensureMonotonic(utcNow);
    final event = Reset(utcNow);
    draft._applyEvent(event);
    pending.add(event);
    return _commit(draft, pending);
  }

  /// Advances the timer to [now], appending every completion and auto-started
  /// phase event that should have occurred up to [now] with its exact UTC
  /// timestamp.
  TimerState tick(DateTime now) {
    final utcNow = now.toUtc();
    final draft = _cloneEngine();
    final pending = <TimerEvent>[];
    draft._ensureMonotonic(utcNow);
    draft._catchUpTo(utcNow, pending);
    return _commit(draft, pending);
  }

  _EngineState _cloneEngine() => _EngineState(
    config: config,
    phase: _phase,
    paused: _paused,
    remaining: _remaining,
    completedFocusCount: _completedFocusCount,
    currentTag: _currentTag,
    lastEventAt: _lastEventAt,
    lastRunningAnchor: _lastRunningAnchor,
  );

  TimerState _commit(_EngineState draft, List<TimerEvent> pending) {
    for (final event in pending) {
      store.append(event);
    }
    _phase = draft.phase;
    _paused = draft.paused;
    _remaining = draft.remaining;
    _completedFocusCount = draft.completedFocusCount;
    _currentTag = draft.currentTag;
    _lastEventAt = draft.lastEventAt;
    _lastRunningAnchor = draft.lastRunningAnchor;
    final current = state;
    _changesController.add(current);
    return current;
  }

  void _replayAll(List<TimerEvent> events) {
    final draft = _cloneEngine();
    for (final event in events) {
      draft._ensureMonotonic(event.at);
      draft._applyEvent(event);
    }
    _phase = draft.phase;
    _paused = draft.paused;
    _remaining = draft.remaining;
    _completedFocusCount = draft.completedFocusCount;
    _currentTag = draft.currentTag;
    _lastEventAt = draft.lastEventAt;
    _lastRunningAnchor = draft.lastRunningAnchor;
  }
}

final class _EngineState {
  _EngineState({
    required this.config,
    required this.phase,
    required this.paused,
    required this.remaining,
    required this.completedFocusCount,
    required this.currentTag,
    required this.lastEventAt,
    required this.lastRunningAnchor,
  });

  final TimerConfig config;
  Phase phase;
  bool paused;
  Duration remaining;
  int completedFocusCount;
  String? currentTag;
  DateTime? lastEventAt;
  DateTime? lastRunningAnchor;

  Phase get _phase => phase;
  bool get _paused => paused;

  void _ensureMonotonic(DateTime utcTime) {
    final previous = lastEventAt;
    if (previous != null && utcTime.isBefore(previous)) {
      throw FocusTimerException(
        'clock_went_backwards',
        'Timestamp ${utcTime.toIso8601String()} is earlier than '
            'last event at ${previous.toIso8601String()}',
      );
    }
  }

  BreakKind _nextBreakKind() {
    if (completedFocusCount > 0 && completedFocusCount % config.longBreakEvery == 0) {
      return BreakKind.long;
    }
    return BreakKind.short;
  }

  void _catchUpTo(DateTime utcNow, List<TimerEvent> pending) {
    while (phase != Phase.idle && !paused) {
      final anchor = lastRunningAnchor!;
      final elapsed = utcNow.difference(anchor);
      if (elapsed < remaining) {
        remaining = remaining - elapsed;
        lastRunningAnchor = utcNow;
        lastEventAt = utcNow;
        return;
      }
      final boundaryTime = anchor.add(remaining);
      if (phase == Phase.focus) {
        final completed = FocusCompleted(boundaryTime);
        _applyEvent(completed);
        pending.add(completed);
        if (config.autoStartBreaks) {
          final breakKind = _nextBreakKind();
          final breakStart = BreakStarted(boundaryTime, kind: breakKind);
          _applyEvent(breakStart);
          pending.add(breakStart);
        }
      } else {
        final completed = BreakCompleted(boundaryTime);
        _applyEvent(completed);
        pending.add(completed);
        if (config.autoStartFocus) {
          final focusStart = FocusStarted(boundaryTime);
          _applyEvent(focusStart);
          pending.add(focusStart);
        }
      }
    }
    if (lastEventAt == null || utcNow.isAfter(lastEventAt!)) {
      lastEventAt = utcNow;
    }
  }

  void _applyEvent(TimerEvent event) {
    final at = event.at;
    switch (event) {
      case FocusStarted():
        if (phase != Phase.idle) {
          throw FocusTimerException('invalid_transition', 'FocusStarted is only valid from idle (was ${phase.name})');
        }
        phase = Phase.focus;
        paused = false;
        remaining = config.focus;
        currentTag = event.tag;
        lastRunningAnchor = at;
        lastEventAt = at;

      case BreakStarted():
        if (phase != Phase.idle) {
          throw FocusTimerException('invalid_transition', 'BreakStarted is only valid from idle (was ${phase.name})');
        }
        phase = event.kind == BreakKind.long ? Phase.longBreak : Phase.shortBreak;
        paused = false;
        remaining = event.kind == BreakKind.long ? config.longBreak : config.shortBreak;
        currentTag = null;
        lastRunningAnchor = at;
        lastEventAt = at;

      case Paused():
        if (phase == Phase.idle || paused) {
          throw FocusTimerException(
            'invalid_transition',
            'Paused requires a running phase (was ${phase.name}, paused: $paused)',
          );
        }
        final anchor = lastRunningAnchor!;
        final elapsed = at.difference(anchor);
        final updated = remaining - elapsed;
        remaining = updated.isNegative ? Duration.zero : updated;
        paused = true;
        lastRunningAnchor = null;
        lastEventAt = at;

      case Resumed():
        if (phase == Phase.idle || !paused) {
          throw FocusTimerException(
            'invalid_transition',
            'Resumed requires a paused phase (was ${phase.name}, paused: $paused)',
          );
        }
        paused = false;
        lastRunningAnchor = at;
        lastEventAt = at;

      case FocusCompleted():
        if (phase != Phase.focus || paused) {
          throw FocusTimerException('invalid_transition', 'FocusCompleted requires running focus phase');
        }
        phase = Phase.idle;
        paused = false;
        remaining = Duration.zero;
        completedFocusCount += 1;
        currentTag = null;
        lastRunningAnchor = null;
        lastEventAt = at;

      case BreakCompleted():
        if ((phase != Phase.shortBreak && phase != Phase.longBreak) || paused) {
          throw FocusTimerException('invalid_transition', 'BreakCompleted requires running break phase');
        }
        phase = Phase.idle;
        paused = false;
        remaining = Duration.zero;
        currentTag = null;
        lastRunningAnchor = null;
        lastEventAt = at;

      case Skipped():
        if (phase == Phase.idle) {
          throw FocusTimerException('invalid_transition', 'Skipped requires an active or paused phase');
        }
        phase = Phase.idle;
        paused = false;
        remaining = Duration.zero;
        currentTag = null;
        lastRunningAnchor = null;
        lastEventAt = at;

      case Reset():
        phase = Phase.idle;
        paused = false;
        remaining = Duration.zero;
        completedFocusCount = 0;
        currentTag = null;
        lastRunningAnchor = null;
        lastEventAt = at;
    }
  }
}
