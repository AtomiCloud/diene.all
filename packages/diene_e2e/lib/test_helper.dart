/// `package:diene_e2e/test_helper.dart` — the L-dart family test-harness
/// bundle.
///
/// This dependency-light sub-library is what consumers import in their int/e2e
/// tiers. It carries `diene_e2e`'s OWN harness glue and re-exports every family
/// member's `test_helper.dart` — one import for the whole family's test helpers.
///
/// Dependency-light rule: `diene_e2e`'s own glue here is fakes / builders /
/// plain-throw assertions built on `dart:io` and `dart:core` only, with NO
/// test-framework deps (`test`, `matcher`, mocking packages). Each member's
/// helper is dependency-light under the same family rule, so this entry point
/// stays a sub-library of the main package rather than the escape-hatch
/// `diene_e2e_test_helper` package.
///
/// ## Member test-helper re-exports
///
/// Each member ships its own `package:diene_<name>/test_helper.dart`, opt-in per
/// the family usefulness criterion. e2e re-exports ONLY the ones that EXIST —
/// there are no stub passthroughs for members without a helper.
///
/// **`diene_core_utils` is deliberately absent.** It carries a NO verdict in the
/// family TestHelper table (pure functions — slugify, merge, coercions — with
/// nothing to fake), and the published `diene_core_utils` 1.0.1 archive
/// confirms it: 14 dart files under `lib/`, no `lib/test_helper.dart`. So this
/// bundle re-exports SIX member helpers, not seven, and the absence is a
/// verified fact rather than an oversight.
///
/// ## Two collisions, disambiguated deliberately
///
/// A duplicate-name audit across the six published helper surfaces found **36
/// reachable declarations and exactly TWO colliding names**. A blind
/// `export`-everything bundle would not compile, so each collision is resolved
/// toward the package that OWNS the underlying contract:
///
/// - **`expectOk`** is declared by both `diene_result` and `diene_api_engine`.
///   `diene_result` owns `Result`, so its `expectOk<T>(Result<T>)` is the one
///   the bundle exposes. The api-engine variant is a different function, not a
///   superset — it takes a `{String? because}` label and throws a bare
///   `AssertionError`, where the result variant throws the family's
///   `TestHelperFailure`. `expectErr` collides for the same reason and is
///   resolved the same way.
/// - **`FakeAuth`** is declared by both `diene_auth_engine` and
///   `diene_api_engine`, and both `implements IAuth`. `diene_auth_engine` owns
///   the `IAuth` seam, so its `FakeAuth` is the one exposed. Again these are
///   genuinely different fakes rather than one containing the other: the
///   auth-engine fake scripts BATCHES of token maps and counts
///   fetch/invalidate calls, while the api-engine fake holds a flat token map
///   and records queried map-keys for bleed assertions.
///
/// **Nothing is lost.** A consumer that specifically wants an api-engine variant
/// imports it directly and prefixed, which is the normal Dart remedy:
///
/// ```dart
/// import 'package:diene_e2e/test_helper.dart';
/// import 'package:diene_api_engine/test_helper.dart' as api;
///
/// final value = expectOk(result);        // diene_result's, via the bundle
/// final fake  = api.FakeAuth({'svc': 'tok'});  // api-engine's, explicitly
/// ```
///
/// The `hide` clauses below are what make this file compile, so they are load
/// bearing: `test/meta/version_train_bundle_meta_test.dart` asserts the bundle
/// resolves each contested name to the owning package's declaration, and would
/// fail if a future member re-introduced either name.
library;

// Member test-helper passthroughs, in family-DAG order (problems is the root).
// `hide` clauses resolve the two audited collisions toward the contract owner.
export 'package:diene_api_engine/test_helper.dart'
    hide FakeAuth, expectErr, expectOk;
export 'package:diene_auth_engine/test_helper.dart';
export 'package:diene_config/test_helper.dart';
export 'package:diene_interfaces/test_helper.dart';
export 'package:diene_problems/test_helper.dart';
export 'package:diene_result/test_helper.dart';

// e2e's own harness glue (this package's contribution to the bundle).
export 'src/assertions/assertions.dart';
export 'src/journey/deferred_login_journey.dart';
export 'src/journey/journey.dart';
export 'src/stub/app_handoff_stub.dart';
export 'src/stub/stub_server.dart';
