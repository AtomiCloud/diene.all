/// Identifies the monad that rejected an explicit unwrap operation.
enum MonadKind {
  /// A [Result] value.
  result,

  /// An [Option] value.
  option,
}

/// Thrown only when an explicit unwrap asks for the wrong variant.
final class UnwrapError extends StateError {
  /// Creates an unwrap diagnostic.
  UnwrapError({
    required this.monad,
    required this.expected,
    required this.actual,
    this.payload,
  }) : super('Expected $expected, got $actual.');

  /// Monad whose variant was inspected.
  final MonadKind monad;

  /// Variant requested by the caller.
  final String expected;

  /// Variant actually present.
  final String actual;

  /// Payload carried by the actual variant, when one exists.
  final Object? payload;

  @override
  String toString() =>
      'UnwrapError(monad: ${monad.name}, expected: $expected, '
      'actual: $actual, payload: $payload)';
}
