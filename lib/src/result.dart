import 'dart:async';

import 'option.dart';
import 'problem.dart';
import 'unwrap_error.dart';
import 'wire.dart';

/// A value that is either [Ok] or [Err].
///
/// Dart's C0 contract fixes the error channel to [Problem], retaining the
/// single generic parameter of the Flutter seed while matching the Bun
/// capability names.
sealed class Result<T> {
  const Result();

  /// Creates an [Ok] result.
  const factory Result.ok(T value) = Ok<T>;

  /// Creates an [Err] result.
  const factory Result.err(Problem problem) = Err<T>;

  /// Decodes the C0 `['ok', value] | ['err', problem]` wire form.
  factory Result.fromSerial(
    ResultSerial serial, {
    required T Function(Object? value) decodeOk,
    Problem Function(Object? value)? decodeErr,
  }) {
    final (String tag, Object? value) = readTaggedWire(
      serial,
      monad: 'Result',
      tags: const <String>{'ok', 'err'},
    );

    if (tag == 'ok') {
      return Ok<T>(decodeOk(value));
    }

    return Err<T>((decodeErr ?? Problem.fromWire)(value));
  }

  /// Whether this result contains an [Ok] value.
  bool get isOk => this is Ok<T>;

  /// Whether this result contains an [Err] problem.
  bool get isErr => this is Err<T>;

  /// Transforms an [Ok] value and leaves an [Err] untouched.
  Result<R> map<R>(R Function(T value) mapper) => switch (this) {
    Ok<T>(:final value) => Ok<R>(mapper(value)),
    Err<T>(:final problem) => Err<R>(problem),
  };

  /// Transforms an [Err] problem and leaves an [Ok] untouched.
  Result<T> mapErr(Problem Function(Problem problem) mapper) => switch (this) {
    Ok<T>(:final value) => Ok<T>(value),
    Err<T>(:final problem) => Err<T>(mapper(problem)),
  };

  /// Chains another fallible operation after an [Ok] value.
  Result<R> andThen<R>(Result<R> Function(T value) mapper) => switch (this) {
    Ok<T>(:final value) => mapper(value),
    Err<T>(:final problem) => Err<R>(problem),
  };

  /// Folds both variants into one return type.
  R match<R>({
    required R Function(T value) ok,
    required R Function(Problem problem) err,
  }) => switch (this) {
    Ok<T>(:final value) => ok(value),
    Err<T>(:final problem) => err(problem),
  };

  /// Runs an [Ok]-side effect without capturing exceptions.
  Result<T> run(void Function(T value) sideEffect) {
    if (this case Ok<T>(:final value)) {
      sideEffect(value);
    }

    return this;
  }

  /// Runs an [Ok]-side effect and explicitly maps a thrown object to [Problem].
  Result<T> exec(
    void Function(T value) sideEffect, {
    required Problem Function(Object error, StackTrace stackTrace) onException,
  }) {
    if (this case Ok<T>(:final value)) {
      try {
        sideEffect(value);
      } on Object catch (error, stackTrace) {
        return Err<T>(onException(error, stackTrace));
      }
    }

    return this;
  }

  /// Returns the [Ok] value or throws [UnwrapError].
  T unwrap() => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>(:final problem) => throw UnwrapError(
      monad: MonadKind.result,
      expected: 'Ok',
      actual: 'Err',
      payload: problem,
    ),
  };

  /// Returns the [Err] problem or throws [UnwrapError].
  Problem unwrapErr() => switch (this) {
    Ok<T>(:final value) => throw UnwrapError(
      monad: MonadKind.result,
      expected: 'Err',
      actual: 'Ok',
      payload: value,
    ),
    Err<T>(:final problem) => problem,
  };

  /// Returns the [Ok] value, or [fallback] for [Err].
  T unwrapOr(T fallback) => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => fallback,
  };

  /// Returns the [Ok] value, or computes a fallback from the [Err] problem.
  T unwrapOrElse(T Function(Problem problem) fallback) => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>(:final problem) => fallback(problem),
  };

  /// Projects the [Ok] channel into an [Option].
  Option<T> ok() => switch (this) {
    Ok<T>(:final value) => Some<T>(value),
    Err<T>() => None<T>(),
  };

  /// Projects the [Err] channel into an [Option].
  Option<Problem> err() => switch (this) {
    Ok<T>() => const None<Problem>(),
    Err<T>(:final problem) => Some<Problem>(problem),
  };

  /// Returns the payload of whichever variant is present.
  Object? native() => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>(:final problem) => problem,
  };

  /// Encodes this result using the C0 tagged-array wire contract.
  ResultSerial serial({Object? Function(T value)? encodeOk}) => switch (this) {
    Ok<T>(:final value) => taggedWire('ok', encodeOk?.call(value) ?? value),
    Err<T>(:final problem) => taggedWire('err', problem.toJson()),
  };
}

/// The successful [Result] variant.
final class Ok<T> extends Result<T> {
  /// Creates a successful result.
  const Ok(this.value);

  /// Successful value.
  final T value;

  @override
  String toString() => 'Ok($value)';
}

/// The failed [Result] variant.
final class Err<T> extends Result<T> {
  /// Creates a failed result.
  const Err(this.problem);

  /// Failure problem.
  final Problem problem;

  @override
  String toString() => 'Err($problem)';
}

/// Async composition for Dart's idiomatic `Future<Result<T>>` shape.
extension FutureResult<T> on Future<Result<T>> {
  /// Async-aware counterpart of [Result.map].
  Future<Result<R>> map<R>(FutureOr<R> Function(T value) mapper) async {
    final Result<T> result = await this;
    return switch (result) {
      Ok<T>(:final value) => Ok<R>(await mapper(value)),
      Err<T>(:final problem) => Err<R>(problem),
    };
  }

  /// Async-aware counterpart of [Result.mapErr].
  Future<Result<T>> mapErr(
    FutureOr<Problem> Function(Problem problem) mapper,
  ) async {
    final Result<T> result = await this;
    return switch (result) {
      Ok<T>(:final value) => Ok<T>(value),
      Err<T>(:final problem) => Err<T>(await mapper(problem)),
    };
  }

  /// Async-aware counterpart of [Result.andThen].
  Future<Result<R>> andThen<R>(
    FutureOr<Result<R>> Function(T value) mapper,
  ) async {
    final Result<T> result = await this;
    return switch (result) {
      Ok<T>(:final value) => await mapper(value),
      Err<T>(:final problem) => Err<R>(problem),
    };
  }

  /// Async-aware counterpart of [Result.match].
  Future<R> match<R>({
    required FutureOr<R> Function(T value) ok,
    required FutureOr<R> Function(Problem problem) err,
  }) async {
    final Result<T> result = await this;
    return switch (result) {
      Ok<T>(:final value) => await ok(value),
      Err<T>(:final problem) => await err(problem),
    };
  }

  /// Awaits the result and unwraps its [Ok] value.
  Future<T> unwrap() async => (await this).unwrap();

  /// Awaits the result and unwraps its [Err] problem.
  Future<Problem> unwrapErr() async => (await this).unwrapErr();
}
