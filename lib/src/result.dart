// VENDORED CONTRACT — pending `diene_result` / `diene_problems`.
//
// Under the STEP-6 optimistic-concurrency rule this branch may not import
// uncommitted sibling lanes, so `diene_api_engine` carries the minimal
// `Result`/`Problem` surface it consumes, seeded verbatim in shape from the
// flutter-base neon seed (`lib/core/result.dart`) and aligned to the C0 §5
// cross-language monad contract (same combinator names). When `diene_result`
// and `diene_problems` land, this file is deleted and the imports re-pointed —
// see the node note's dependency-stacking section.
import 'package:meta/meta.dart';

/// RFC 9457 problem envelope with the diene `data` extension.
///
/// Mirrors the neon seed and the `diene_problems` wire contract: a problem is
/// the sole error channel of [Result].
@immutable
class Problem {
  const Problem({
    required this.type,
    required this.title,
    required this.status,
    this.detail,
    this.instance,
    this.recoverable = false,
    this.data = const <String, Object?>{},
  });

  /// Decodes an RFC 9457 body, tolerating absent fields the way the seed does.
  factory Problem.fromJson(Map<String, Object?> json) => Problem(
        type: json['type'] as String? ?? 'about:blank',
        title: json['title'] as String? ?? 'Unexpected problem',
        status: json['status'] as int? ?? 500,
        detail: json['detail'] as String?,
        instance: json['instance'] as String?,
        recoverable: json['recoverable'] as bool? ?? false,
        data: (json['data'] as Map<Object?, Object?>? ??
                const <Object?, Object?>{})
            .map(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        ),
      );

  final String type;
  final String title;
  final int status;
  final String? detail;
  final String? instance;
  final bool recoverable;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'title': title,
        'status': status,
        if (detail != null) 'detail': detail,
        if (instance != null) 'instance': instance,
        'recoverable': recoverable,
        'data': data,
      };

  Problem copyWith(
          {String? detail, String? instance, Map<String, Object?>? data}) =>
      Problem(
        type: type,
        title: title,
        status: status,
        detail: detail ?? this.detail,
        instance: instance ?? this.instance,
        recoverable: recoverable,
        data: data ?? this.data,
      );

  @override
  String toString() => 'Problem($type, $status, $title)';
}

/// A total, throw-free computation outcome: [Ok] on success, [Err] carrying a
/// [Problem] on failure. Single type parameter matches the neon seed and the
/// dart-family "sealed `Result<T>`" surface; the error type is always
/// [Problem].
@immutable
sealed class Result<T> {
  const Result();

  /// Success constructor (C0 combinator name `ok`).
  const factory Result.ok(T value) = Ok<T>;

  /// Failure constructor (C0 combinator name `err`).
  const factory Result.err(Problem problem) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// Retained neon-seed alias.
  bool get isSuccess => isOk;

  /// Exhaustive collapse (neon seed name).
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Problem failure) onFailure,
  }) =>
      switch (this) {
        Ok<T>(:final value) => onSuccess(value),
        Err<T>(:final problem) => onFailure(problem),
      };

  /// C0 combinator name for [fold].
  R match<R>({
    required R Function(T value) ok,
    required R Function(Problem problem) err,
  }) =>
      fold(onSuccess: ok, onFailure: err);

  /// Maps the success value; passes [Err] through unchanged.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Ok<T>(:final value) => Ok<R>(transform(value)),
        Err<T>(:final problem) => Err<R>(problem),
      };

  /// Maps the failure problem; passes [Ok] through unchanged.
  Result<T> mapErr(Problem Function(Problem problem) transform) =>
      switch (this) {
        Ok<T>() => this,
        Err<T>(:final problem) => Err<T>(transform(problem)),
      };

  /// Monadic bind (C0 `andThen`).
  Result<R> andThen<R>(Result<R> Function(T value) transform) => switch (this) {
        Ok<T>(:final value) => transform(value),
        Err<T>(:final problem) => Err<R>(problem),
      };

  /// Unwrap family.
  T unwrap() => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>(:final problem) => throw StateError(
            'unwrap() on Err: ${problem.type} (${problem.status})',
          ),
      };

  T unwrapOr(T fallback) => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => fallback,
      };

  T unwrapOrElse(T Function(Problem problem) recover) => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>(:final problem) => recover(problem),
      };

  /// Success projection (`Option`-style; null when [Err]).
  T? get ok => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  /// Failure projection (null when [Ok]).
  Problem? get problem => switch (this) {
        Ok<T>() => null,
        Err<T>(:final problem) => problem,
      };
}

@immutable
final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok<T>, value);

  @override
  String toString() => 'Ok($value)';
}

@immutable
final class Err<T> extends Result<T> {
  const Err(this.problem);

  @override
  final Problem problem;

  @override
  bool operator ==(Object other) =>
      other is Err<T> && other.problem.type == problem.type;

  @override
  int get hashCode => Object.hash(Err<T>, problem.type);

  @override
  String toString() => 'Err($problem)';
}
