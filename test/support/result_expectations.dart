import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

T expectSuccess<T>(Result<T> result) => switch (result) {
  Ok<T>(:final T value) => value,
  Err<T>(:final Problem problem) => throw TestFailure(
    'Expected Ok<$T>, got Err(${problem.title})',
  ),
};

Problem expectFailure<T>(Result<T> result) => switch (result) {
  Ok<T>() => throw TestFailure('Expected Err<$T>, got Ok'),
  Err<T>(:final Problem problem) => problem,
};

Err<T> failure<T>(String id) => Err<T>(
  Problem(type: 'https://example.test/problems/$id', title: id, status: 500),
);
