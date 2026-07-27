// Production dead-code root for the published diene_api_engine surface.
//
// This is tooling, not a test. dart_code_linter otherwise treats only the public
// barrel (diene_api_engine.dart) as an entrypoint and incorrectly reports the
// test_helper.dart public functions as unused. Referencing every public export
// here keeps the production-only dead-code pass honest without any exclusion
// list (R12: two passes, no exclusions). deadcode.sh copies this file to
// bin/main.dart inside the production-only sandbox, so it lives in the member
// package where `package:diene_api_engine` resolves cleanly (and is kept out of
// the published archive by .pubignore).
//
// SHAPE: this file REFERENCES the public surface rather than exercising it —
// class declarations via `Type` literals, functions and constructors via
// tear-offs. Behaviour is the tests' job, and duplicating it here was actively
// harmful: an earlier draft constructed every export, which coupled a pure
// reachability marker to the exact signature of every constructor and produced
// 30-odd analyzer errors that said nothing about dead code. A reference list
// cannot drift out of sync with behaviour because it asserts none.
//
// If a public export is added or removed, this list must change too — that
// coupling is the point, and it is now the ONLY coupling.
import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';

/// Every public export of `package:diene_api_engine/diene_api_engine.dart` and
/// `package:diene_api_engine/test_helper.dart`, as a reachable reference.
const List<Object?> _publicSurface = <Object?>[
  // --- bridge ---------------------------------------------------------------
  BridgeProblems,
  isProblemJson,
  toResult,
  tryDecodeObject,
  // --- client tree ----------------------------------------------------------
  ClientTree,
  // --- engine-owned config block -------------------------------------------
  ApiEngineConfig,
  BackendConfig,
  LpsmCoordinate,
  RescueConfig,
  // --- engine ---------------------------------------------------------------
  ApiEngine,
  Backend,
  BackendClientAdapter,
  // --- OA3 SDK wrapper ------------------------------------------------------
  ResultSdk,
  // --- rescue router --------------------------------------------------------
  DocA,
  DocC,
  RescueOutcome,
  RescueRouter,
  RescueUnavailable,
  Rescued,
  FileRescueStore,
  InMemoryRescueStore,
  RescueStore,
  // --- transport ------------------------------------------------------------
  HttpMethod,
  HttpRequest,
  HttpResponse,
  HttpTransport,
  IoHttpTransport,
  NetworkFailure,
  Received,
  RetryOnceTransport,
  TransportOutcome,
  // --- re-exported owned contracts ------------------------------------------
  IAuth,
  ResourceKey,
  ResourceToken,
  Problem,
  Err,
  Ok,
  Result,
  // --- TestHelper: assertions ----------------------------------------------
  check,
  expectErr,
  expectOk,
  expectProblemType,
  // --- TestHelper: builders -------------------------------------------------
  networkFailure,
  nonJsonResponse,
  nonProblemJson,
  okJson,
  problemFixture,
  problemResponse,
  // --- TestHelper: fakes ----------------------------------------------------
  FakeAuth,
  FakeClock,
  FakeHttpTransport,
  FakeRescueStore,
  HangingTransport,
  noJitter,
  noSleep,
];

void main() {
  // Consume the list so it is not itself dead. `length` is enough to make every
  // element reachable; printing the count also means this entrypoint cannot pass
  // by producing no output at all.
  // ignore: avoid_print
  print('diene_api_engine public surface references: ${_publicSurface.length}');
}
