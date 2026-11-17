/// Base exception thrown by the focus timer library.
///
/// Every error exposes a stable machine-readable [code] and ensures that
/// untrusted snippets included in [message] are truncated to at most 200
/// characters.
final class FocusTimerException extends ArgumentError implements Exception {
  /// Creates a [FocusTimerException] with the given [code] and [message].
  FocusTimerException(this.code, String message) : super(_sanitizeMessage(message));

  /// Creates an exception wrapping an untrusted [input] snippet.
  factory FocusTimerException.withInput(String code, String prefix, String input) {
    final snippet = input.length <= _maxInputSnippet ? input : '${input.substring(0, _maxInputSnippet)}...';
    return FocusTimerException(code, '$prefix: $snippet');
  }

  static const int _maxInputSnippet = 200;

  /// Machine-readable error code.
  ///
  /// One of:
  /// - `'invalid_transition'`
  /// - `'invalid_config'`
  /// - `'clock_went_backwards'`
  /// - `'corrupt_log'`
  /// - `'unsupported_version'`
  /// - `'input_too_large'`
  /// - `'log_full'`
  final String code;

  static String _sanitizeMessage(String text) {
    if (text.length <= 280) {
      return text;
    }
    return '${text.substring(0, 280)}...';
  }

  @override
  String toString() => 'FocusTimerException($code): $message';
}
