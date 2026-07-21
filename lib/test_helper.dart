/// `package:diene_e2e/test_helper.dart` — the L-dart family test-harness
/// bundle.
///
/// This dependency-light sub-library is what consumers import in their int/e2e
/// tiers. It carries `diene_e2e`'s OWN harness glue and, once the members are
/// published, re-exports every family member's `test_helper.dart` — one import
/// for the whole family's test helpers.
///
/// Dependency-light rule: everything here is fakes / builders / plain-throw
/// assertions built on `dart:io` and `dart:core` only. There are NO
/// test-framework deps (`test`, `matcher`, mocking packages), so importing
/// this entry point adds nothing to a consumer's production dependency graph.
///
/// ## Member test-helper re-export seam — INTEGRATION-HELD
///
/// Each family member ships its own `package:diene_<name>/test_helper.dart`
/// (opt-in per the usefulness criterion). e2e re-exports ONLY the ones that
/// EXIST — no stub passthroughs for members without a helper. The members are
/// built in parallel branches and are not yet available as deps in this lane,
/// so the passthroughs are not wired here. When the member packages land and
/// are stacked, add a re-export for each member whose TestHelper exists, e.g.:
///
/// ```dart
/// export 'package:diene_result/test_helper.dart';      // expectOk/expectErr…
/// export 'package:diene_interfaces/test_helper.dart';  // in-memory seams
/// export 'package:diene_problems/test_helper.dart';    // Problem matchers
/// export 'package:diene_config/test_helper.dart';       // fake config layers
/// export 'package:diene_auth_engine/test_helper.dart';  // fake IdP/token seams
/// export 'package:diene_api_engine/test_helper.dart';   // fake backends
/// // NOTE: diene_core_utils has NO TestHelper (NO-verdict) — no passthrough.
/// ```
///
/// Wiring these + the flutter-base dogfood is conductor-owned integration work
/// (see the node completion note).
library;

// e2e's own harness glue (this package's contribution to the bundle).
export 'src/assertions/assertions.dart';
export 'src/journey/deferred_login_journey.dart';
export 'src/journey/journey.dart';
export 'src/stub/app_handoff_stub.dart';
export 'src/stub/stub_server.dart';
