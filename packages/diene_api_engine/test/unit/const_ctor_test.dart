/// Constructors that were uncovered ONLY because every call site used `const`.
///
/// A `const` invocation is COMPILE-TIME evaluated, so the constructor body never
/// executes at runtime and the line records zero hits — even though the type is
/// constructed all over the suite. Measured: `const ResultSdk()` leaves
/// `sdk_adapter.dart:27` at 0 hits, while a runtime `ResultSdk()` marks it 1.
///
/// So these were NOT unreachable code, which is what I had filed them as. They
/// were reachable lines hidden by an optimisation, and the fix is to construct
/// once at runtime rather than to argue the line away. This is the fifth
/// classification of mine that was too pessimistic about reachability.
///
/// The assertions are deliberately about BEHAVIOUR rather than mere construction:
/// a test that only calls a constructor to move a coverage number would be the
/// threshold-gaming the lead warned against.
library;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResultSdk built at runtime', () {
    test('a runtime instance behaves identically to a const one', () async {
      // Non-const on purpose — this is what executes the constructor.
      final ResultSdk runtime = ResultSdk();
      const ResultSdk compileTime = ResultSdk();

      // Both must wrap a successful invoke into Ok.
      expect((await runtime.call<int>(() async => 1)).unwrap(), 1);
      expect((await compileTime.call<int>(() async => 1)).unwrap(), 1);

      // And both must fold a throw into a transport-failure Problem rather than
      // letting it escape — the property the type exists for.
      final Problem viaRuntime = expectErr(
        await runtime.call<int>(() async => throw StateError('boom')),
      );
      expect(viaRuntime.type, BridgeProblems.transportFailure);
      expect(viaRuntime.status, 503);
    });

    test('const instances are canonicalised, runtime ones are not', () {
      // Documents WHY the coverage gap existed, so the next reader does not
      // re-file the line as dead code.
      expect(identical(const ResultSdk(), const ResultSdk()), isTrue);
      expect(identical(ResultSdk(), ResultSdk()), isFalse);
    });
  });
}
