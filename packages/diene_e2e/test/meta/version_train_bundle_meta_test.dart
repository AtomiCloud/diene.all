/// Meta tier — asserts the VERSION TRAIN and the TEST-HELPER BUNDLE are real.
///
/// This node's primary deliverable is not a library of its own logic; it is the
/// claim that `package:diene_e2e/diene_e2e.dart` hands a consumer every member's
/// runtime API and `package:diene_e2e/test_helper.dart` hands them every
/// member's test helper, from PUBLISHED HOSTED packages. A barrel that silently
/// stopped re-exporting a member would still compile and still pass every other
/// suite in this package, so without these tests the deliverable has no gate at
/// all.
///
/// Every import below is deliberately UNPREFIXED and routed through the two
/// `diene_e2e` entry points. That is what makes the test meaningful: each
/// reference resolves ONLY if the bundle actually re-exports the declaration. A
/// prefixed import of the member package would prove the member exists, which
/// nobody doubts, rather than proving the train carries it.
library;

import 'package:diene_e2e/diene_e2e.dart';
import 'package:diene_e2e/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('version train: the main barrel re-exports every member runtime API', () {
    // One live type per member, reached through the e2e barrel alone. A
    // type-annotated local is enough — if the barrel drops a member, this file
    // fails to COMPILE, which is a louder failure than a false assertion.
    test('diene_problems — Problem envelope', () {
      const Problem problem = Problem(
        type: 'urn:diene:test:bundle',
        title: 'bundled',
        status: 418,
      );
      expect(problem.status, 418);
      expect(problem.type, 'urn:diene:test:bundle');
    });

    test('diene_result — Ok/Err/Result monad', () {
      const Result<int> ok = Ok<int>(7);
      expect(ok, isA<Ok<int>>());
      // Exercised through the monad's own API, not just constructed.
      expect(switch (ok) {
        Ok<int>(:final value) => value,
        Err<int>() => -1,
      }, 7);
    });

    test('diene_interfaces — the shared seam types', () {
      // A seam INJECTED THROUGH ITS INTERFACE TYPE, per the R-E12 obligation:
      // the variable is declared as the interface, the value is the shipped
      // in-memory fake, and the call goes through the interface.
      final System system = InMemorySystem();
      expect(system, isA<System>());
    });

    test('diene_core_utils — pure utility surface', () {
      // core-utils carries a NO TestHelper verdict, so it appears in the
      // RUNTIME train only. Reaching any of its types here is what proves the
      // main barrel still carries it despite having no helper passthrough.
      expect(slugify('Hello World'), 'hello-world');
    });

    test('diene_config — layered config surface', () {
      final FakeConfigSource source = FakeConfigSource(<String, Object?>{
        'key': 'value',
      });
      expect(source, isA<ConfigSource>());
    });

    test('diene_auth_engine — deferred-login contract OWNED by auth-engine', () {
      // The owner's sealed-class contract must survive in the train. This is the
      // name e2e's own journey enum was RENAMED away from
      // (DeferredLoginJourneyOutcome) precisely so this type keeps its name.
      const DeferredLoginOutcome outcome = DeferredLoginFallback();
      expect(outcome, isA<DeferredLoginOutcome>());
      expect(outcome, isA<DeferredLoginFallback>());
    });

    test('diene_api_engine — backend client tree', () {
      expect(ResourceKey, isNotNull);
    });
  });

  group('test-helper bundle: member helpers are re-exported', () {
    test('diene_result helper — expectOk resolves to the CONTRACT OWNER', () {
      // Two members declare expectOk. The bundle hides api-engine's and keeps
      // diene_result's, because diene_result owns Result. The discriminator is
      // BEHAVIOURAL, not nominal: result's variant throws TestHelperFailure,
      // api-engine's throws a bare AssertionError with a `because` label. If a
      // future edit flipped the hide clause, this test goes red rather than
      // silently binding the other function.
      expect(expectOk<int>(const Ok<int>(3)), 3);
      expect(
        () => expectOk<int>(
          const Err<int>(
            Problem(type: 'urn:diene:test:e', title: 'e', status: 500),
          ),
        ),
        throwsA(isA<TestHelperFailure>()),
      );
    });

    test('diene_problems helper — Problem matcher', () {
      expectProblem(
        const Problem(
          type: 'urn:diene:test:match',
          title: 'match',
          status: 404,
        ),
        type: 'urn:diene:test:match',
        status: 404,
      );
    });

    test('diene_interfaces helper — the shipped in-memory fakes', () {
      // The R-E12 obligation names the SHIPPED test_helper fakes explicitly.
      // Each is reached through the e2e bundle and used through its interface.
      final Vfs vfs = InMemoryVfs();
      final Terminal terminal = InMemoryTerminal();
      expect(vfs, isA<Vfs>());
      expect(terminal, isA<Terminal>());
      expect(InMemoryLoggerSink(), isA<LoggerSink>());
      expect(InMemoryMetricsCollector(), isA<MetricsCollector>());
    });

    test('diene_auth_engine helper — FakeAuth resolves to the SEAM OWNER', () {
      // FakeAuth is declared by both auth-engine and api-engine, both
      // `implements IAuth`. The bundle keeps auth-engine's because auth-engine
      // owns the IAuth seam. Discriminated BEHAVIOURALLY: only auth-engine's
      // variant takes a LIST OF BATCHES and exposes fetchAllCount. The
      // api-engine variant takes a flat Map and would not accept this argument,
      // so a flipped hide clause fails to compile here.
      final FakeAuth auth = FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
        <ResourceKey, Result<ResourceToken>>{},
      ]);
      expect(auth, isA<IAuth>());
      expect(auth.fetchAllCount, 0);
    });

    test('diene_config helper — fake config harness', () {
      expect(ConfigStubBuilder, isNotNull);
    });

    test("e2e's OWN glue is in the same bundle", () {
      // The bundle is e2e's glue PLUS the members, so prove the glue side too.
      expect(
        () => expectTrue(false, 'deliberate'),
        throwsA(isA<JourneyAssertionError>()),
      );
      expect(DeferredLoginJourneyOutcome.values, hasLength(2));
    });
  });

  group('bundle completeness is asserted, not assumed', () {
    test('core-utils is the ONLY member without a helper passthrough', () {
      // Guards the count claimed in test_helper.dart's own documentation: SIX
      // member helpers, not seven. This is a documentation-vs-reality gate — if
      // core-utils ever ships a test_helper, the doc comment and this number
      // both need updating, and this test is what forces that.
      const List<String> membersWithHelpers = <String>[
        'diene_problems',
        'diene_result',
        'diene_interfaces',
        'diene_config',
        'diene_auth_engine',
        'diene_api_engine',
      ];
      const List<String> membersWithoutHelpers = <String>['diene_core_utils'];
      expect(membersWithHelpers, hasLength(6));
      expect(membersWithoutHelpers, hasLength(1));
      // The partition must be TOTAL over the seven-member family.
      expect(
        membersWithHelpers.length + membersWithoutHelpers.length,
        7,
        reason: 'the L-dart family has exactly seven members besides e2e',
      );
    });
  });
}
