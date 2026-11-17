import 'blank_input_error.dart';

final _asciiUpper = RegExp('[A-Z]');

/// Trims surrounding whitespace and lower-cases the ASCII letters of [input].
///
/// Throws a [BlankInputError] when nothing is left after trimming, instead of returning an empty string.
String normalize(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw BlankInputError();
  }
  return trimmed.replaceAllMapped(_asciiUpper, (match) => match[0]!.toLowerCase());
}
