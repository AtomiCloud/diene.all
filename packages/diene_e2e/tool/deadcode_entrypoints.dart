// Production dead-code root for the published diene_e2e surface.
//
// This is tooling, not a test. dart_code_linter otherwise treats only the public
// barrel (diene_e2e.dart) as an entrypoint and incorrectly reports the
// test_helper.dart public declarations as unused. Referencing every public
// export here keeps the production-only dead-code pass honest without any
// exclusion list (R12: two passes, no exclusions). deadcode.sh copies this file
// to bin/main.dart inside the production-only sandbox, so it lives in the member
// package where `package:diene_e2e` resolves cleanly (and is kept out of the
// published archive by .pubignore).
//
// SHAPE: this file REFERENCES the public surface rather than exercising it —
// class and enum declarations via `Type` literals, functions via tear-offs.
// Behaviour is the tests' job. This is the shape the api-engine sibling arrived
// at after an earlier draft that CONSTRUCTED every export produced 30-odd
// analyzer errors saying nothing about dead code. The file this one replaces was
// dart-lib's Note-sample version, inherited with the scaffolding, which failed
// for exactly that reason — 15 analyzer issues, every one a dangling reference to
// the deleted sample rather than a dead-code finding.
//
// SCOPE NOTE specific to this node: diene_e2e is the family VERSION TRAIN, so its
// barrels re-export SEVEN other packages' surfaces. Those are deliberately NOT
// listed here. Each member's own dead-code pass owns its own surface, and
// re-listing them would redden this node whenever any member added an export — a
// coupling to seven other release cadences for no reachability benefit. Only
// declarations THIS package declares are listed.
//
// If a public export of this package is added or removed, this list must change
// too — that coupling is the point, and it is the only one.
import 'package:diene_e2e/diene_e2e.dart';
import 'package:diene_e2e/test_helper.dart';

/// Every public declaration `diene_e2e` OWNS, as a reachable reference.
const List<Object?> _publicSurface = <Object?>[
  // --- app-handoff contract models (main barrel) ----------------------------
  AppHandoffDevice,
  AppHandoffExpired,
  AppHandoffMint,
  AppHandoffNonceState,
  AppHandoffRedeemRequest,
  AppHandoffRedeemResponse,
  AppHandoffUser,
  // --- harness glue (test_helper sub-library) -------------------------------
  AppHandoffStub,
  DeferredLoginJourney,
  DeferredLoginJourneyOutcome,
  DeferredLoginResult,
  Journey,
  JourneyAssertionError,
  JourneyResult,
  JourneyStep,
  JourneyStepResult,
  StubHandler,
  StubRequest,
  StubResponse,
  StubServer,
  // --- plain-throw assertion helpers, as tear-offs --------------------------
  expectEquals,
  expectJourneyFailedAt,
  expectJourneyOk,
  expectTrue,
];

void main() {
  // Referencing the list is what makes every element reachable.
  if (_publicSurface.isEmpty) {
    throw StateError('public surface list must not be empty');
  }
}
