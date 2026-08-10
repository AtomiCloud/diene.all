// Production dead-code root for the published diene_result surface.
// This is tooling, not a test: DCL otherwise assumes only diene_result.dart is
// an entrypoint and incorrectly reports the test_helper.dart public functions.
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:diene_result/test_helper.dart';

void main() {
  final Problem problem = Problem(
    type: 'about:blank',
    title: 'Dead-code entrypoint',
    status: 500,
  );

  expectOk(const Result<int>.ok(1));
  expectErr<int>(Result<int>.err(problem));
  expectSome(const Option<int>.some(1));
  expectNone(const Option<int>.none());
}
