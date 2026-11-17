/// Thrown when the input is empty or only whitespace, instead of returning an empty string.
class BlankInputError extends ArgumentError {
  /// Creates the error with the message "input is blank".
  BlankInputError() : super('input is blank');
}
