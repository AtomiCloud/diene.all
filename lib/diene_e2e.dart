/// `diene_e2e` — the L-dart family version-train and consumer test-harness.
///
/// This primary library is the family **version train**: the single package a
/// consumer (flutter-base's E4 swap-in) depends on to get a coherent set of
/// the seven L-dart libraries at once, instead of pinning each individually.
/// It re-exports the runtime API of every member that exists.
///
/// It also exposes the pure-value **contract models** this package owns — the
/// C0 §7 app-handoff (deferred-login) wire shapes and carrier codec — which
/// the shared fixture and consumer journeys build and parse.
///
/// The dependency-light TEST harness (stub server, journey drivers, the shared
/// app-handoff fixture, plain-throw assertions, and the member test-helper
/// re-exports) lives on the separate `package:diene_e2e/test_helper.dart`
/// entry point, so importing it never adds test-framework or heavy deps to a
/// consumer's production graph.
///
/// ## Version-train re-export seam — INTEGRATION-HELD
///
/// The seven L-dart members are built in parallel branches and are not yet
/// published packages, so their runtime re-exports cannot be wired in this
/// isolated lane. When the member packages land and are stacked, add the
/// runtime re-exports here (one `export` per member that exists), e.g.:
///
/// ```dart
/// export 'package:diene_result/diene_result.dart';
/// export 'package:diene_interfaces/diene_interfaces.dart';
/// export 'package:diene_core_utils/diene_core_utils.dart';
/// export 'package:diene_config/diene_config.dart';
/// export 'package:diene_problems/diene_problems.dart';
/// export 'package:diene_auth_engine/diene_auth_engine.dart';
/// export 'package:diene_api_engine/diene_api_engine.dart';
/// ```
///
/// Wiring these deps + the flutter-base dogfood swap-in is conductor-owned
/// integration work (see the node completion note).
library;

export 'src/app_handoff/carrier.dart';
export 'src/app_handoff/wire.dart';
