import 'exceptions.dart';

/// Kind of break phase started by a [BreakStarted] event.
enum BreakKind {
  /// A short break between focus sessions.
  short,

  /// A longer break after completing `longBreakEvery` focus sessions.
  long;

  /// Parses a [BreakKind] by name (`'short'` or `'long'`).
  static BreakKind fromName(String raw) {
    switch (raw) {
      case 'short':
        return BreakKind.short;
      case 'long':
        return BreakKind.long;
      default:
        throw FocusTimerException.withInput('corrupt_log', 'Unknown break kind', raw);
    }
  }
}

/// Maximum allowed length in characters for a focus session tag.
const int maxFocusTagLength = 40;

/// Validates and normalizes an optional focus tag.
String? validateFocusTag(String? tag) {
  if (tag == null) {
    return null;
  }
  if (tag.length > maxFocusTagLength) {
    throw FocusTimerException.withInput('invalid_config', 'Focus tag exceeds $maxFocusTagLength characters', tag);
  }
  return tag;
}

/// Immutable record in the append-only focus timer event log.
///
/// Every event carries its timestamp [at] normalized to UTC.
sealed class TimerEvent {
  const TimerEvent._(this.at);

  /// UTC timestamp at which the event occurred.
  final DateTime at;

  /// Event type discriminator used in serialized logs.
  String get typeName;
}

/// Recorded when a focus session begins.
final class FocusStarted extends TimerEvent {
  /// Creates a [FocusStarted] event at [at] (converted to UTC) with optional
  /// [tag] (at most 40 characters).
  FocusStarted(DateTime at, {String? tag}) : tag = validateFocusTag(tag), super._(at.toUtc());

  /// Optional category or task label (at most 40 characters).
  final String? tag;

  @override
  String get typeName => 'FocusStarted';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FocusStarted && at == other.at && tag == other.tag;

  @override
  int get hashCode => Object.hash(typeName, at, tag);

  @override
  String toString() => tag == null
      ? 'FocusStarted(at: ${at.toIso8601String()})'
      : 'FocusStarted(at: ${at.toIso8601String()}, tag: $tag)';
}

/// Recorded when a short or long break begins.
final class BreakStarted extends TimerEvent {
  /// Creates a [BreakStarted] event at [at] (converted to UTC) of [kind].
  BreakStarted(DateTime at, {required this.kind}) : super._(at.toUtc());

  /// Whether this break is [BreakKind.short] or [BreakKind.long].
  final BreakKind kind;

  @override
  String get typeName => 'BreakStarted';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BreakStarted && at == other.at && kind == other.kind;

  @override
  int get hashCode => Object.hash(typeName, at, kind);

  @override
  String toString() => 'BreakStarted(at: ${at.toIso8601String()}, kind: ${kind.name})';
}

/// Recorded when an active focus or break phase is paused.
final class Paused extends TimerEvent {
  /// Creates a [Paused] event at [at] (converted to UTC).
  Paused(DateTime at) : super._(at.toUtc());

  @override
  String get typeName => 'Paused';

  @override
  bool operator ==(Object other) => identical(this, other) || (other is Paused && at == other.at);

  @override
  int get hashCode => Object.hash(typeName, at);

  @override
  String toString() => 'Paused(at: ${at.toIso8601String()})';
}

/// Recorded when a paused focus or break phase is resumed.
final class Resumed extends TimerEvent {
  /// Creates a [Resumed] event at [at] (converted to UTC).
  Resumed(DateTime at) : super._(at.toUtc());

  @override
  String get typeName => 'Resumed';

  @override
  bool operator ==(Object other) => identical(this, other) || (other is Resumed && at == other.at);

  @override
  int get hashCode => Object.hash(typeName, at);

  @override
  String toString() => 'Resumed(at: ${at.toIso8601String()})';
}

/// Recorded when a focus phase reaches its full configured duration.
final class FocusCompleted extends TimerEvent {
  /// Creates a [FocusCompleted] event at [at] (converted to UTC).
  FocusCompleted(DateTime at) : super._(at.toUtc());

  @override
  String get typeName => 'FocusCompleted';

  @override
  bool operator ==(Object other) => identical(this, other) || (other is FocusCompleted && at == other.at);

  @override
  int get hashCode => Object.hash(typeName, at);

  @override
  String toString() => 'FocusCompleted(at: ${at.toIso8601String()})';
}

/// Recorded when a short or long break phase reaches its full duration.
final class BreakCompleted extends TimerEvent {
  /// Creates a [BreakCompleted] event at [at] (converted to UTC).
  BreakCompleted(DateTime at) : super._(at.toUtc());

  @override
  String get typeName => 'BreakCompleted';

  @override
  bool operator ==(Object other) => identical(this, other) || (other is BreakCompleted && at == other.at);

  @override
  int get hashCode => Object.hash(typeName, at);

  @override
  String toString() => 'BreakCompleted(at: ${at.toIso8601String()})';
}

/// Recorded when the user skips the current active or paused phase.
final class Skipped extends TimerEvent {
  /// Creates a [Skipped] event at [at] (converted to UTC).
  Skipped(DateTime at) : super._(at.toUtc());

  @override
  String get typeName => 'Skipped';

  @override
  bool operator ==(Object other) => identical(this, other) || (other is Skipped && at == other.at);

  @override
  int get hashCode => Object.hash(typeName, at);

  @override
  String toString() => 'Skipped(at: ${at.toIso8601String()})';
}

/// Recorded when the timer is reset back to idle.
final class Reset extends TimerEvent {
  /// Creates a [Reset] event at [at] (converted to UTC).
  Reset(DateTime at) : super._(at.toUtc());

  @override
  String get typeName => 'Reset';

  @override
  bool operator ==(Object other) => identical(this, other) || (other is Reset && at == other.at);

  @override
  int get hashCode => Object.hash(typeName, at);

  @override
  String toString() => 'Reset(at: ${at.toIso8601String()})';
}
