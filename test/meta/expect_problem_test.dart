import 'package:diene_problems/diene_problems.dart';
import 'package:diene_problems/test_helper.dart';
import 'package:test/test.dart';

/// Meta tier — assert-the-asserter: prove [expectProblem] FAILS on every
/// known-bad case and PASSES on the known-good case. A matcher that cannot fail
/// is worthless; this is the test of the test helper.
void main() {
  const good = Problem(
    type: 'https://h/docs/l/p/s/m/v1/entity-not-found',
    title: 'Entity not found',
    status: 404,
    recoverable: false,
    detail: 'missing',
    instance: '/x',
    data: <String, Object?>{'resource': 'user', 'id': 42},
  );

  test('passes when every checked field matches', () {
    expectProblem(
      good,
      type: good.type,
      title: good.title,
      status: good.status,
      recoverable: good.recoverable,
      detail: good.detail,
      instance: good.instance,
      data: good.data,
    );
  });

  test('passes when only a subset of fields is checked', () {
    expectProblem(good, status: 404);
  });

  test('fails when the value is not a Problem', () {
    expect(
      () => expectProblem('not a problem'),
      throwsA(isA<ProblemMatcherError>()),
    );
    expect(() => expectProblem(null), throwsA(isA<ProblemMatcherError>()));
  });

  test('fails on a type mismatch', () {
    expect(
      () => expectProblem(good, type: 'https://other'),
      throwsA(isA<ProblemMatcherError>()),
    );
  });

  test('fails on a title mismatch', () {
    expect(
      () => expectProblem(good, title: 'Wrong'),
      throwsA(isA<ProblemMatcherError>()),
    );
  });

  test('fails on a status mismatch', () {
    expect(
      () => expectProblem(good, status: 500),
      throwsA(isA<ProblemMatcherError>()),
    );
  });

  test('fails on a recoverable mismatch', () {
    expect(
      () => expectProblem(good, recoverable: true),
      throwsA(isA<ProblemMatcherError>()),
    );
  });

  test('fails on a detail mismatch', () {
    expect(
      () => expectProblem(good, detail: 'other'),
      throwsA(isA<ProblemMatcherError>()),
    );
  });

  test('fails on an instance mismatch', () {
    expect(
      () => expectProblem(good, instance: '/other'),
      throwsA(isA<ProblemMatcherError>()),
    );
  });

  test('fails on a data mismatch (different value)', () {
    expect(
      () => expectProblem(good, data: <String, Object?>{'resource': 'user', 'id': 99}),
      throwsA(isA<ProblemMatcherError>()),
    );
  });

  test('fails on a data mismatch (missing key)', () {
    expect(
      () => expectProblem(good, data: <String, Object?>{'resource': 'user'}),
      throwsA(isA<ProblemMatcherError>()),
    );
  });

  test('matches nested data structures deeply', () {
    const nested = Problem(
      type: 't',
      title: 'T',
      status: 400,
      data: <String, Object?>{
        'outer': <String, Object?>{'inner': <String>['a', 'b']},
      },
    );
    expectProblem(
      nested,
      data: <String, Object?>{
        'outer': <String, Object?>{'inner': <String>['a', 'b']},
      },
    );
    expect(
      () => expectProblem(
        nested,
        data: <String, Object?>{
          'outer': <String, Object?>{'inner': <String>['a', 'c']},
        },
      ),
      throwsA(isA<ProblemMatcherError>()),
    );
  });
}
