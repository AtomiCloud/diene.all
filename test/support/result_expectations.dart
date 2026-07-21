import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

T expectSuccess<T>(Result<T> result) => switch (result) {
  Success<T>(:final T value) => value,
  Failure<T>(:final Problem problem) => throw TestFailure(
    'Expected Success<$T>, got Failure(${problem.title})',
  ),
};

Problem expectFailure<T>(Result<T> result) => switch (result) {
  Success<T>() => throw TestFailure('Expected Failure<$T>, got Success'),
  Failure<T>(:final Problem problem) => problem,
};

Failure<T> failure<T>(String id) => Failure<T>(
  Problem(type: 'https://example.test/problems/$id', title: id, status: 500),
);
