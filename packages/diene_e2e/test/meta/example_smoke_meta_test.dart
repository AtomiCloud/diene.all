/// Meta tier — the SHIPPED EXAMPLE must actually run.
///
/// pana awards 10 points for "Package has an example", and it awards them for a
/// file EXISTING. An example that no longer compiles still scores, still ships in
/// the archive, and is the first thing a new consumer copies — so the points are
/// not the gate, this test is.
///
/// Run through the `flutter test` runner deliberately. `dart run` on this package
/// crashes in the VM's FFI use-site transform ("type 'InvalidType' is not a
/// subtype of type 'FunctionType' in type cast") because the version train pulls
/// Flutter plugins transitively via diene_auth_engine. That is a toolchain
/// limitation of `dart run` against a Flutter package, NOT a defect in the
/// example: `flutter analyze --fatal-infos` on the same file reports "No issues
/// found". Asserting through the runner that works proves the example's LOGIC,
/// which is what a consumer copies.
library;

import 'package:flutter_test/flutter_test.dart';

import '../../example/diene_e2e_example.dart' as example;

void main() {
  test('the shipped example runs to completion', () async {
    // No assertion beyond completion: the example itself calls expectJourneyOk
    // and expectTrue, so a regression surfaces as a JourneyAssertionError from
    // inside it rather than as a weaker check out here.
    await example.main();
  });
}
