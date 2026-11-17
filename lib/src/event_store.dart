import 'exceptions.dart';
import 'timer_event.dart';

/// Append-only persistence interface for [TimerEvent] records.
abstract interface class EventStore {
  /// Returns an unmodifiable snapshot of all stored events in append order.
  List<TimerEvent> load();

  /// Appends [e] to the store.
  void append(TimerEvent e);
}

/// Bounded in-memory implementation of [EventStore].
///
/// Enforces a maximum capacity of [maxEvents] (defaults to `100000`).
/// Appending beyond [maxEvents] throws a [FocusTimerException] with code
/// `'log_full'`.
final class MemoryEventStore implements EventStore {
  /// Creates a [MemoryEventStore] with an optional [maxEvents] limit and
  /// optional [initialEvents].
  MemoryEventStore({this.maxEvents = 100000, Iterable<TimerEvent>? initialEvents}) : _events = <TimerEvent>[] {
    if (maxEvents < 1) {
      throw FocusTimerException('invalid_config', 'maxEvents must be at least 1 (got $maxEvents)');
    }
    if (initialEvents != null) {
      for (final event in initialEvents) {
        append(event);
      }
    }
  }

  /// Maximum number of events allowed in this store.
  final int maxEvents;

  final List<TimerEvent> _events;

  @override
  List<TimerEvent> load() => List<TimerEvent>.unmodifiable(_events);

  @override
  void append(TimerEvent e) {
    if (_events.length >= maxEvents) {
      throw FocusTimerException('log_full', 'Event store reached maximum capacity of $maxEvents events');
    }
    _events.add(e);
  }
}
