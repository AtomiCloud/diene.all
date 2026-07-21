// Sealed `Result<T>` / `Option<T>` monad.
//
// DEPENDENCY STACKING: self-carried subset of the `diene_result` contract that
// `diene_auth_engine` needs while it is built in isolation. Combinator names
// track the C0 §5 cross-language table (map / mapErr / andThen / match). When
// the family is stacked, this file is deleted and imports repoint at
// `package:diene_result/diene_result.dart`. See docs/standards/auth/index.md.

import 'problem.dart';

/// A computation that either succeeds with a `T` or fails with a [Problem].
sealed class Result<T> {
  const Result();

  /// Lifts a value into a successful result.
  factory Result.ok(T value) = Success<T>;

  /// Lifts a problem into a failed result.
  factory Result.err(Problem problem) = Failure<T>;

  /// Whether this is a [Success].
  bool get isSuccess => this is Success<T>;

  /// Whether this is a [Failure].
  bool get isFailure => this is Failure<T>;

  /// Collapses both arms into a single `R`.
  R match<R>({
    required R Function(T value) onSuccess,
    required R Function(Problem problem) onFailure,
  }) => switch (this) {
    Success<T>(:final T value) => onSuccess(value),
    Failure<T>(:final Problem problem) => onFailure(problem),
  };

  /// Alias of [match] kept for parity with the neon seed.
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Problem failure) onFailure,
  }) => match(onSuccess: onSuccess, onFailure: onFailure);

  /// Maps the success value, leaving a failure untouched.
  Result<R> map<R>(R Function(T value) transform) => match(
    onSuccess: (T value) => Success<R>(transform(value)),
    onFailure: (Problem problem) => Failure<R>(problem),
  );

  /// Maps the failure problem, leaving a success untouched.
  Result<T> mapErr(Problem Function(Problem problem) transform) => match(
    onSuccess: Success<T>.new,
    onFailure: (Problem problem) => Failure<T>(transform(problem)),
  );

  /// Chains another fallible step onto a success.
  Result<R> andThen<R>(Result<R> Function(T value) transform) => match(
    onSuccess: transform,
    onFailure: (Problem problem) => Failure<R>(problem),
  );

  /// Returns the success value or `fallback` on failure.
  T unwrapOr(T fallback) =>
      match(onSuccess: (T value) => value, onFailure: (_) => fallback);

  /// The success value, or `null` for a failure.
  T? get valueOrNull =>
      match(onSuccess: (T value) => value, onFailure: (_) => null);

  /// The failure problem, or `null` for a success.
  Problem? get problemOrNull =>
      match(onSuccess: (_) => null, onFailure: (Problem problem) => problem);
}

/// The successful arm of a [Result].
final class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Success<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// The failed arm of a [Result].
final class Failure<T> extends Result<T> {
  const Failure(this.problem);

  final Problem problem;

  @override
  bool operator ==(Object other) =>
      other is Failure<T> && other.problem == problem;

  @override
  int get hashCode => problem.hashCode;
}

/// An optional value: [Some] or [None].
sealed class Option<T> {
  const Option();

  /// Wraps a present value.
  factory Option.some(T value) = Some<T>;

  /// The absent value.
  factory Option.none() = None<T>;

  /// Builds an [Option] from a nullable, mapping `null` to [None].
  factory Option.of(T? value) => value == null ? None<T>() : Some<T>(value);

  /// Whether a value is present.
  bool get isSome => this is Some<T>;

  /// Whether the value is absent.
  bool get isNone => this is None<T>;

  /// Collapses both arms into a single `R`.
  R match<R>({
    required R Function(T value) onSome,
    required R Function() onNone,
  }) => switch (this) {
    Some<T>(:final T value) => onSome(value),
    None<T>() => onNone(),
  };

  /// The value or `fallback` when absent.
  T unwrapOr(T fallback) =>
      match(onSome: (T value) => value, onNone: () => fallback);

  /// The value, or `null` when absent.
  T? get valueOrNull => match(onSome: (T value) => value, onNone: () => null);
}

/// The present arm of an [Option].
final class Some<T> extends Option<T> {
  const Some(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Some<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// The absent arm of an [Option].
final class None<T> extends Option<T> {
  const None();

  @override
  bool operator ==(Object other) => other is None<T>;

  @override
  int get hashCode => (None<T>).hashCode;
}
