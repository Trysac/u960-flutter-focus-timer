import 'dart:convert';

import 'exceptions.dart';
import 'timer_event.dart';

/// Versioned JSON serializer and parser for [TimerEvent] logs.
///
/// Encoded payloads always begin with
/// `{"format":"focus-timer-log","version":1,"events":[...]}` and serialize
/// every event with keys in a deterministic order.
final class LogCodec {
  const LogCodec._();

  /// Format identifier written to every exported JSON log.
  static const String formatName = 'focus-timer-log';

  /// Supported schema version.
  static const int currentVersion = 1;

  /// Default maximum character length accepted by [decode].
  static const int defaultMaxChars = 16777216;

  /// Serializes [events] into a deterministic versioned JSON string.
  static String encode(List<TimerEvent> events) {
    final buffer = StringBuffer('{"format":"$formatName","version":$currentVersion,"events":[');
    for (var i = 0; i < events.length; i++) {
      if (i > 0) {
        buffer.write(',');
      }
      final event = events[i];
      final atIso = jsonEncode(event.at.toUtc().toIso8601String());
      final typeIso = jsonEncode(event.typeName);
      switch (event) {
        case FocusStarted():
          if (event.tag != null) {
            final tagJson = jsonEncode(event.tag);
            buffer.write('{"type":$typeIso,"at":$atIso,"tag":$tagJson}');
          } else {
            buffer.write('{"type":$typeIso,"at":$atIso}');
          }
        case BreakStarted():
          final kindJson = jsonEncode(event.kind.name);
          buffer.write('{"type":$typeIso,"at":$atIso,"kind":$kindJson}');
        case Paused():
        case Resumed():
        case FocusCompleted():
        case BreakCompleted():
        case Skipped():
        case Reset():
          buffer.write('{"type":$typeIso,"at":$atIso}');
      }
    }
    buffer.write(']}');
    return buffer.toString();
  }

  /// Parses a versioned JSON log [text] into an unmodifiable list of
  /// [TimerEvent]s.
  ///
  /// Throws [FocusTimerException] with:
  /// - `'input_too_large'` when `text.length > maxChars`.
  /// - `'unsupported_version'` when the envelope version is an integer other
  ///   than `1`.
  /// - `'corrupt_log'` when JSON is malformed, fields are missing or invalid,
  ///   or an unknown event type is encountered.
  static List<TimerEvent> decode(String text, {int maxChars = defaultMaxChars}) {
    if (maxChars < 1) {
      throw FocusTimerException('invalid_config', 'maxChars must be at least 1 (got $maxChars)');
    }
    if (text.length > maxChars) {
      throw FocusTimerException(
        'input_too_large',
        'Log input length ${text.length} exceeds limit of $maxChars characters',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw FocusTimerException.withInput('corrupt_log', 'Invalid JSON (${error.message})', text);
    }

    if (decoded is! Map<String, Object?>) {
      throw FocusTimerException.withInput('corrupt_log', 'Top-level JSON value must be an object', text);
    }

    final format = decoded['format'];
    if (format != formatName) {
      throw FocusTimerException.withInput('corrupt_log', 'Unexpected or missing format field', '$format');
    }

    final version = decoded['version'];
    if (version is! int) {
      throw FocusTimerException.withInput('corrupt_log', 'Missing or non-integer version field', '$version');
    }
    if (version != currentVersion) {
      throw FocusTimerException('unsupported_version', 'Unsupported log version $version (expected $currentVersion)');
    }

    final eventsRaw = decoded['events'];
    if (eventsRaw is! List<Object?>) {
      throw FocusTimerException.withInput('corrupt_log', 'Missing or non-list events field', '$eventsRaw');
    }

    final result = <TimerEvent>[];
    for (var i = 0; i < eventsRaw.length; i++) {
      final item = eventsRaw[i];
      if (item is! Map<String, Object?>) {
        throw FocusTimerException.withInput('corrupt_log', 'Event at index $i is not a JSON object', '$item');
      }
      result.add(_decodeEvent(item, i));
    }
    return List<TimerEvent>.unmodifiable(result);
  }

  static TimerEvent _decodeEvent(Map<String, Object?> map, int index) {
    final type = map['type'];
    if (type is! String) {
      throw FocusTimerException.withInput(
        'corrupt_log',
        'Event at index $index has missing or non-string type',
        '$type',
      );
    }

    final atRaw = map['at'];
    if (atRaw is! String) {
      throw FocusTimerException.withInput(
        'corrupt_log',
        'Event at index $index has missing or non-string timestamp',
        '$atRaw',
      );
    }
    final DateTime parsedAt;
    try {
      parsedAt = DateTime.parse(atRaw).toUtc();
    } on FormatException {
      throw FocusTimerException.withInput('corrupt_log', 'Event at index $index has invalid ISO 8601 timestamp', atRaw);
    }

    switch (type) {
      case 'FocusStarted':
        final tagRaw = map['tag'];
        if (tagRaw != null && tagRaw is! String) {
          throw FocusTimerException.withInput(
            'corrupt_log',
            'FocusStarted tag at index $index must be a string',
            '$tagRaw',
          );
        }
        final tag = tagRaw as String?;
        if (tag != null && tag.length > maxFocusTagLength) {
          throw FocusTimerException.withInput(
            'corrupt_log',
            'FocusStarted tag at index $index exceeds $maxFocusTagLength chars',
            tag,
          );
        }
        return FocusStarted(parsedAt, tag: tag);

      case 'BreakStarted':
        final kindRaw = map['kind'];
        if (kindRaw is! String) {
          throw FocusTimerException.withInput(
            'corrupt_log',
            'BreakStarted kind at index $index must be a string',
            '$kindRaw',
          );
        }
        return BreakStarted(parsedAt, kind: BreakKind.fromName(kindRaw));

      case 'Paused':
        return Paused(parsedAt);
      case 'Resumed':
        return Resumed(parsedAt);
      case 'FocusCompleted':
        return FocusCompleted(parsedAt);
      case 'BreakCompleted':
        return BreakCompleted(parsedAt);
      case 'Skipped':
        return Skipped(parsedAt);
      case 'Reset':
        return Reset(parsedAt);
      default:
        throw FocusTimerException.withInput('corrupt_log', 'Unknown event type at index $index', type);
    }
  }
}
